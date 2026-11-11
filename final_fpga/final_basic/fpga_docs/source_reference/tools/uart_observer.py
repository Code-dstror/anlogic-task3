"""Decode TX-only observer frames; serial reception requires explicit --listen.

This protocol has no commands. COM12 may only be read; COM7 is RK Linux control
and is rejected. Ordinary invocation with --input never imports a serial driver.
"""
from __future__ import annotations

import argparse
import importlib
import json
import struct
import sys
import time
from pathlib import Path

MAGIC = b"OB"
VERSION = 2
FRAME_BYTES = 29
CFG_MAGIC = b"CG"
CFG_VERSIONS = (1, 2)
CFG_TYPE = 1
CFG_FRAME_BYTES = 68
BAUD = 115200
DOMAIN_NAMES = ("pixel", "dfi", "user")
SYS_FLAG_NAMES = (
    "debug_cold_reset_n", "debug_app_reset_n", "pcie_perst_n", "pixel_pll_locked",
    "camera_pll_locked", "ddr_cal_done", "ddr_app_ready", "ddr_phy_reset_n",
    "pcie_user_link_up", "pcie_user_reset_n", "endpoint_reset_n", "session_ready",
    "session_armed", "session_rearm_required", "memory_owner_ready", "effective_app_enable",
)
LEVEL_NAMES = {
    "pixel": ("pixel_reset_n", "config_initialized", "camera_config_done", "camera_phy_ready",
              "camera_delay_ready", "camera_hdr_mode", "camera_hdr_stable", "frame_active",
              "jpeg_idle", "raw_processing_idle", "native_pipeline_idle", "camera_config_error"),
    "dfi": ("dfi_reset_n", "ddr_cal_done", "ddr_app_ready", "ddr_phy_reset_n", "bridge_fault",
            "store_recovery", "writer_ack_valid", "store_ready_valid", "credit_reserved",
            "hdr_writer_quiescent", "hdr_owner_empty", "hdr_scheduler_busy"),
    "user": ("pcie_user_reset_n", "pcie_user_link_up", "config_initialized", "raw_pci_bme",
             "pcie_supervisor_ready", "product_buffer_armed", "phase_bit0", "phase_bit1",
             "phase_bit2", "transport_recovery", "memory_owner_ready", "reset_pending"),
}
# OB/V2 has no on-wire layout selector. Use the camera mode known at capture.
STEREO_PIXEL_LEVEL_NAMES = (
    "pixel_reset_n", "config_initialized", "camera0_config_done", "camera0_phy_ready",
    "camera0_config_error", "camera1_config_done", "camera1_phy_ready", "frame_active",
    "jpeg_idle", "raw_processing_idle", "native_pipeline_idle", "camera1_config_error",
)
FAULT_NAMES = {
    "pixel": ("camera_config_error", "camera_receive_or_identity", "jpeg_failed_result",
              "admission_or_processing_or_record"),
    "dfi": ("bridge_fault", "store_recovery", "arbiter_or_ticket_recovery", "writer_failed_ack"),
    "user": ("first_pcie_supervisor", "first_completion", "first_memory", "first_product_or_protocol"),
}
EVENT_NAMES = {
    "pixel": ("frame_admission", "jpeg_result_handshake"),
    "dfi": ("writer_ack_handshake", "store_ready_claim"),
    "user": ("native_descriptor_accept", "jpeg_retire_handshake"),
}
CFG_USER_FLAG_NAMES = {
    0: "request_valid", 1: "commit_accepted", 2: "commit_packet_last_sent",
    3: "matched_applied_final_present", 4: "active_copy_started",
    5: "copy_complete_seen", 6: "matched_applied_final_taken", 7: "published_atomic",
    8: "effective_ready", 9: "session_initialized", 10: "owned", 11: "stream_ready",
    12: "failed", 13: "reply_mismatch_seen", 24: "response_valid",
    25: "response_ready", 26: "command_valid", 27: "command_ready",
    28: "publish_complete", 29: "copy_busy", 30: "app_reset_n",
    31: "reset_generation_saturated",
}
CFG_PIXEL_FLAG_NAMES = {
    0: "commit_valid", 1: "remote_sent_seen", 2: "matched_positive_ack_seen",
    3: "matched_negative_ack_seen", 4: "unmatched_ack_while_tracking",
    5: "first_qualified_sof_seen_after_positive_ack", 6: "apply_seen",
    7: "applied_reply_last_sent", 8: "first_qualified_sof_eligible",
    9: "first_qualified_sof_idle", 10: "first_qualified_sof_response_space",
    11: "live_eligible", 12: "live_idle", 13: "live_response_space", 14: "pause",
    15: "remote_pending", 16: "remote_sent", 17: "remote_applied",
    18: "remote_fault", 19: "source_ready", 20: "frame_accept",
    24: "first_offered_sensor_fs_seen_after_positive_ack", 25: "app_reset_n",
    31: "reset_generation_saturated",
}
CFG_PIXEL_CAUSE_NAMES = {
    26: "physical_identity_quarantine", 27: "camera_source_identity_fault",
    28: "capture_frontend_fault", 29: "binding_fault", 30: "cleanup_fault",
}
CFG_OFFERED_FS_GATE_NAMES = (
    "enable_pixel", "armed", "config_source_ready", "config_pause",
    "capture_config_valid", "reset_pause", "local_stop", "live_source_block",
    "native_pipeline_idle", "physical_admit_enable", "physical_sdr_source_idle",
    "record_product_available", "record_format_busy", "camera_mode_running",
    "camera_receive_fault", "physical_admission_inhibit",
)


def crc8(data: bytes) -> int:
    value = 0
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = ((value << 1) ^ (0x07 if value & 0x80 else 0)) & 0xFF
    return value


def crc16(data: bytes) -> int:
    """CRC-16/CCITT-FALSE: 1021, FFFF, non-reflected, xorout zero."""
    value = 0xFFFF
    for byte in data:
        value ^= byte << 8
        for _ in range(8):
            value = ((value << 1) ^ (0x1021 if value & 0x8000 else 0)) & 0xFFFF
    return value


def decode_cfg_frame(data: bytes) -> dict:
    if (len(data) != CFG_FRAME_BYTES or data[:2] != CFG_MAGIC or
            data[2] not in CFG_VERSIONS or data[3:6] != bytes((CFG_TYPE, CFG_FRAME_BYTES, 0))):
        raise ValueError("unsupported CFG frame header")
    if data[8] & 0xFC or data[9] & 0xFC:
        raise ValueError("reserved CFG validity bits are nonzero")
    if crc16(data[:66]) != int.from_bytes(data[66:68], "little"):
        raise ValueError("CFG frame CRC mismatch")
    version = data[2]
    result = {"frame_type": "cfg", "version": version, "type": CFG_TYPE,
              "sequence": int.from_bytes(data[6:8], "little"),
              "fresh_mask": data[8], "reset_n_mask": data[9], "domains": {}}
    for index, name in enumerate(("user", "pixel")):
        words = list(struct.unpack_from("<7I", data, 10 + index * 28))
        domain = {"words": words, "fresh": bool(data[8] & (1 << index)),
                  "in_reset": not bool(data[9] & (1 << index)),
                  "session": words[0], "request_sequence": words[1],
                  "target_epoch": words[2], "flags": words[5],
                  "reset_generation": words[6] & 0xFFFF}
        flags = words[5]
        labels = CFG_USER_FLAG_NAMES if name == "user" else CFG_PIXEL_FLAG_NAMES
        domain["flag_values"] = {label: bool(flags & (1 << bit))
                                 for bit, label in labels.items()}
        domain["identity_valid"] = bool(flags & 1)
        domain["reset_generation_saturated"] = bool(flags & (1 << 31))
        app_reset_bit = 30 if name == "user" else 25
        domain["evidence_usable"] = (domain["fresh"] and not domain["in_reset"] and
                                     bool(flags & (1 << app_reset_bit)) and
                                     not domain["reset_generation_saturated"])
        domain["evidence_state"] = "SAMPLED" if domain["evidence_usable"] else "UNKNOWN"
        domain["sample_state"] = "in_reset" if domain["in_reset"] else (
            "fresh" if domain["fresh"] else "stale_or_unavailable")
        if name == "user":
            domain.update(published_epoch=words[3], published_first_sequence=words[4],
                          bar_state=(flags >> 14) & 7, bar_job=(flags >> 17) & 15,
                          error_code=(flags >> 21) & 7,
                          request_identity_kind="prepare_admitted_not_full_validation")
        else:
            # V1 reserved zeroes carry no cause evidence. V2 bits are live
            # values at the PIX snapshot edge, not sticky transaction causes.
            available = version >= 2
            domain["cause_bits_available"] = available
            domain["cause_state"] = "SAMPLED" if available and domain["evidence_usable"] else "UNKNOWN"
            domain["cause_values"] = {
                label: bool(flags & (1 << bit)) if available else None
                for bit, label in CFG_PIXEL_CAUSE_NAMES.items()}
            if available:
                domain["flag_values"].update(domain["cause_values"])
            domain.update(commit_session=words[0], commit_sequence=words[1],
                          first_post_positive_ack_qualified_sof_sequence=words[3],
                          actual_apply_sequence=words[4],
                          first_post_ack_offered_sensor_fs_gates=words[6] >> 16,
                          engine_state=(flags >> 21) & 7)
            qualified_seen = bool(flags & (1 << 5))
            offered_seen = bool(flags & (1 << 24))
            domain["qualified_sof_gates"] = (
                {label: bool(flags & (1 << (8 + bit))) for bit, label in enumerate(
                    ("eligible", "pipeline_idle", "response_space"))} if qualified_seen else None)
            domain["offered_sensor_fs_gates"] = (
                {label: bool(words[6] & (1 << (16 + bit)))
                 for bit, label in enumerate(CFG_OFFERED_FS_GATE_NAMES)} if offered_seen else None)
        result["domains"][name] = domain
    user, pixel = result["domains"]["user"], result["domains"]["pixel"]
    relation = "UNKNOWN"
    if user["evidence_usable"] and pixel["evidence_usable"]:
        if not user["identity_valid"]:
            relation = "USER_REQUEST_IDENTITY_NOT_VALID"
        elif not user["flag_values"]["commit_accepted"]:
            relation = "USER_REQUEST_BEFORE_ACCEPTED_COMMIT"
        elif not pixel["identity_valid"]:
            relation = "PIX_IDENTITY_NOT_VALID"
        elif (user["session"], user["request_sequence"], user["target_epoch"]) != (
                pixel["session"], pixel["request_sequence"], pixel["target_epoch"]):
            relation = "OLD_OR_UNRELATED_PIX_IDENTITY"
        else:
            relation = "MATCHING_IDENTITY_VALUES_ONLY"
    result["association"] = relation
    result["association_note"] = (
        "Per-domain sampled evidence only; missing or old identity does not prove COMMIT non-receipt. "
        "Matching identity values alone do not establish a reset cohort. Reset generations are "
        "independent per domain and are not compared for equality.")
    # A complete per-domain sample is not a simultaneous cross-domain sample,
    # and report sequence/UART arrival provides no milestone event timestamp.
    result["event_time_basis"] = "domain_samples_only_no_event_timestamps"
    return result


def decode_frame(data: bytes, *, pixel_layout: str = "mono") -> dict:
    if len(data) != FRAME_BYTES or data[:4] != MAGIC + bytes((VERSION, FRAME_BYTES)):
        raise ValueError("unsupported observer frame header")
    if data[6] & 0xF8 or data[7] & 0xF8:
        raise ValueError("reserved validity bits are nonzero")
    if crc8(data[:-1]) != data[-1]:
        raise ValueError("observer frame CRC mismatch")
    result = {
        "version": VERSION,
        "sequence": int.from_bytes(data[4:6], "little"),
        "fresh_mask": data[6],
        "reset_n_mask": data[7],
        "sys_flags": int.from_bytes(data[8:10], "little"),
        "domains": {},
    }
    result["sys_status"] = {name: bool(result["sys_flags"] & (1 << bit))
                            for bit, name in enumerate(SYS_FLAG_NAMES)}
    for index, name in enumerate(DOMAIN_NAMES):
        flags, event0, event1 = struct.unpack_from("<HHH", data, 10 + index * 6)
        names = STEREO_PIXEL_LEVEL_NAMES if name == "pixel" and pixel_layout == "stereo" else LEVEL_NAMES[name]
        result["domains"][name] = {
            "fresh": bool(data[6] & (1 << index)),
            "in_reset": not bool(data[7] & (1 << index)),
            "levels": flags & 0xFFF,
            "sticky_faults": flags >> 12,
            "event0_mod65536": event0,
            "event1_mod65536": event1,
            "level_flags": {label: bool(flags & (1 << bit))
                            for bit, label in enumerate(names)},
            "sticky_fault_names": [label for bit, label in enumerate(FAULT_NAMES[name])
                                   if flags & (1 << (12 + bit))],
            "event_labels": EVENT_NAMES[name],
        }
    user = result["domains"]["user"]
    result["domains"]["pixel"]["level_layout"] = pixel_layout
    phase = (user["levels"] >> 6) & 7
    user["transport_phase"] = ("IDLE", "WAIT_RECORD", "LAUNCH", "RUN",
                               "FENCE", "COMPLETION", "RESULT", "FAULT")[phase]
    user["phase_kind"] = "first_observed_fault_phase" if user["sticky_faults"] else "current_phase"
    return result


RX_MAGIC=b"RX"
RX_FRAME_BYTES=64
TRACE_MAGIC=b"RT"
TRACE_FRAME_BYTES=64


def decode_trace_sample(value: int) -> dict:
    """WORD-edge values, in lane0-first order. No wall-clock timestamps."""
    def bits(at, width=1):
        return (value >> at) & ((1 << width) - 1)
    result = {name: bits(at, width) for name, at, width in (
        ("raw_word", 0, 32), ("byte_aligned_word", 32, 32),
        ("aligned_word", 64, 32), ("geared_word", 96, 32),
        ("lane_valid", 128, 4), ("byte_offsets", 132, 12),
        ("lane_found", 144, 4), ("lane_taps", 148, 12),
        ("source_count", 160, 32), ("parser_state", 192, 2),
        ("bytes_left", 194, 16), ("syndrome", 210, 6),
        ("calibration", 224, 16))}
    for name, at in (
        ("good_header", 216), ("raw_packet", 217), ("sequence_started", 218),
        ("sequence_trusted", 219), ("parser_done", 220), ("crc_lo_seen", 221),
        ("dropping", 222), ("frame_open", 223), ("aligned_valid", 240),
        ("geared_valid", 241), ("wait_sync", 242), ("packet_done", 243),
        ("phy_done", 244), ("decoder_reset_n", 245), ("word_reset_n", 246),
        ("publish", 247), ("hdr_mode", 248), ("identity_started", 249),
        ("phy_reset_n", 250), ("cohort_reset_n", 251), ("trigger", 252)):
        result[name] = bool(bits(at))
    calibration = result["calibration"]
    result["calibration_fields"] = {
        "tap": calibration & 31, "window": (calibration >> 5) & 63,
        **{name: bool(calibration & (1 << at)) for name, at in (
            ("scan_done", 11), ("window_valid", 12), ("failed", 13),
            ("manual", 14), ("status_valid", 15))}}
    result["lane_byte_offsets"] = [(result["byte_offsets"] >> (3 * lane)) & 7 for lane in range(4)]
    result["lane_tap_indices"] = [(result["lane_taps"] >> (3 * lane)) & 7 for lane in range(4)]
    return result


def decode_trace_frame(data: bytes) -> dict:
    if len(data) != TRACE_FRAME_BYTES or data[:6] != b"RT\x01\x01\x40\x00":
        raise ValueError("unsupported RT frame header")
    if data[8] & 0xFE or data[9] or any(data[50:62]):
        raise ValueError("RT reserved fields")
    if int.from_bytes(data[62:64], "little") != crc16(data[:62]):
        raise ValueError("RT CRC16 mismatch")
    payload = int.from_bytes(data[10:50], "little")
    sample = payload & ((1 << 256) - 1)
    index = (payload >> 304) & 63
    pre_count = (payload >> 310) & 63
    ready, post, valid, enabled = [bool(payload & (1 << bit)) for bit in range(316, 320)]
    expected_valid = ready and index < 40 and index >= 32 - pre_count
    if (sample >> 253 or index not in (*range(40), 63) or pre_count > 32 or
            ready and post or valid != expected_valid):
        raise ValueError("RT payload schema/reserved fields")
    fresh = bool(data[8] & 1)
    return {
        "frame_type": "trace", "version": 1, "type": 1,
        "sequence": int.from_bytes(data[6:8], "little"), "fresh_mask": data[8],
        "fresh": fresh, "generation": (payload >> 256) & 65535,
        "trigger_cycle": (payload >> 272) & 0xFFFFFFFF, "sample_index": index,
        "valid_pre_count": pre_count, "capture_ready": ready,
        "capturing_post": post, "sample_valid": valid, "enabled": enabled,
        "sample_hex": f"{sample:064x}", "sample": decode_trace_sample(sample),
        "evidence_state": "CAPTURED_SAMPLE" if fresh and valid else (
            "STATUS_ONLY" if fresh and index == 63 else "UNKNOWN"),
        "evidence_scope": "WORD_EDGE_HISTORY_NO_ABSOLUTE_EVENT_TIME_OR_CROSS_DOMAIN_ORDER",
        "enabled_note": "Held cohort enable at snapshot time; disabled preserves prior capture, stale is not live status.",
    }


class TraceAssembler:
    """Only a fresh ready status can anchor a sweep; never mix generations.

    All 40 indices are required, including explicitly invalid prehistory slots.
    A stale or late old-generation result cannot establish ready or add evidence.
    """
    def __init__(self):
        self.current = None
        self.latest_key = None
        self.completed = []
        self.rejected = {"stale": 0, "unanchored": 0, "old_generation": 0, "conflict": 0}

    def feed(self, frame):
        if frame.get("frame_type") != "trace":
            return
        if not frame["fresh"]:
            self.rejected["stale"] += 1
            return
        key = (frame["generation"], frame["trigger_cycle"])
        if self.latest_key is None or key[0] > self.latest_key[0]:
            # Do not carry an incomplete previous-cohort sample set forward.
            self.current = None
            self.latest_key = (key[0], None)
        elif key[0] < self.latest_key[0]:
            # The hardware generation saturates, never wraps. An observer cold
            # restart needs a new capture file/assembler, not a guessed cohort.
            self.rejected["old_generation"] += 1
            return
        if frame["capture_ready"] or frame["capturing_post"]:
            # Before the trigger, status carries a provisional zero cycle.
            # Only post/ready fixes the immutable trigger identity of this gen.
            if self.latest_key[1] is not None and key[1] != self.latest_key[1]:
                self.rejected["old_generation"] += 1
                return
            self.latest_key = key
        if not frame["capture_ready"]:
            self.current = None
            return
        if self.current is None:
            if frame["sample_index"] != 63:
                self.rejected["unanchored"] += 1
                return
            self.current = {"key": key, "valid_pre_count": frame["valid_pre_count"],
                            "samples": {}, "conflict": False, "exported": False}
        group = self.current
        if frame["valid_pre_count"] != group["valid_pre_count"]:
            group["conflict"] = True
            self.rejected["conflict"] += 1
            self._invalidate_export(group)
            return
        index = frame["sample_index"]
        if index == 63:
            return
        sample = {"index": index, "valid": frame["sample_valid"],
                  "relative_word_cycle": index - 32,
                  "word_cycle_mod2p32": (key[1] + index - 32) & 0xFFFFFFFF,
                  "sample_hex": frame["sample_hex"], "sample": frame["sample"]}
        previous = group["samples"].get(index)
        if previous is not None and previous != sample:
            group["conflict"] = True
            self.rejected["conflict"] += 1
            self._invalidate_export(group)
            return
        group["samples"][index] = sample
        if len(group["samples"]) == 40 and not group["conflict"] and not group["exported"]:
            self.completed.append(self._group(group))
            group["exported"] = True

    def _invalidate_export(self, group):
        if group["exported"]:
            for capture in self.completed:
                if (capture["generation"], capture["trigger_cycle"]) == group["key"]:
                    capture["complete"] = False
                    capture["conflict"] = True

    @staticmethod
    def _group(group):
        return {"generation": group["key"][0], "trigger_cycle": group["key"][1],
                "valid_pre_count": group["valid_pre_count"],
                "invalid_pre_indices": list(range(32 - group["valid_pre_count"])),
                "complete": len(group["samples"]) == 40 and not group["conflict"],
                "conflict": group["conflict"],
                "missing_indices": sorted(set(range(40)) - group["samples"].keys()),
                "samples": [group["samples"][index] for index in sorted(group["samples"])]}

    def snapshot(self):
        return {"schema": "RT_V1_CAPTURE_ASSEMBLY", "captures": self.completed,
                "current": self._group(self.current) if self.current is not None else None,
                "rejected": dict(self.rejected),
                "time_basis": "WORD_CYCLES_RELATIVE_TO_TRIGGER_NO_ABSOLUTE_TIME"}

def decode_rx_frame(data):
    if len(data)!=64 or data[:6]!=b"RX\x01\x01\x40\x00" or data[8]&248 or data[9]&248 or any(data[58:62]):
        raise ValueError("RX header/reserved fields")
    if int.from_bytes(data[62:64],"little")!=crc16(data[:62]):
        raise ValueError("RX CRC16 mismatch")
    banks=[list(struct.unpack("<4I",data[10+16*i:26+16*i])) for i in range(3)]
    w,c,p=banks;r=w[0];state=c[0];phase=p[3]
    return dict(frame_type="rx",version=1,sequence=int.from_bytes(data[6:8],"little"),
        fresh_mask=data[8],reset_n_mask=data[9],words=banks,
        word=dict(first_loss_schema=r&15,first_loss_causes=(r>>4)&7,
            first_loss_sequence_low16=r>>16,first_loss_syndrome=(r>>10)&63,
            first_loss_decoder_reset_n=bool(r&512),first_loss_word_valid=bool(r&256),
            first_loss_parser_header_state=bool(r&128),first_loss_raw_header=w[1],
            long_fs_count=w[2],short_fs_count=w[3]),
        cfg=dict(state=(state>>12)&15,register_index=(state>>16)&255,warmup_count=state>>24,
            flags=state&4095,i2c_done_count=c[1]&65535,i2c_error_count=c[1]>>16,
            pair_event_count=c[2]&65535,pair_good_count=c[2]>>16,last_register=c[3]&0xffffff),
        pixel=dict(good_pair_count=p[0],bad_pair_count=p[1],not_admitted_pair_count=p[2],
            first_bad_reason=phase>>24,last_bad_reason=(phase>>16)&255,phase=phase&65535),
        evidence_scope="PER_DOMAIN_HELD_SNAPSHOTS_NOT_ATOMIC_NOT_EVENT_TIMESTAMPS",
        cohort_note="WORD identity reset and HDR mode reset clear their local diagnostics; fresh/reset masks do not prove cross-domain cohort equality")

def decode_job_frame(data):
    """DJ pages are independent local-domain snapshots, never event timestamps."""
    if len(data) != 68 or data[:2] != b"DJ" or data[2] not in (1, 2, 3) or data[3:6] != b"\x01\x44\x00" or data[8] & ~3 or data[9] & ~3:
        raise ValueError("DJ header or masks")
    if int.from_bytes(data[66:68], "little") != crc16(data[:66]):
        raise ValueError("DJ CRC16 mismatch")
    dfi = int.from_bytes(data[10:38], "little")
    pix = int.from_bytes(data[38:66], "little")
    if data[2] in (2, 3):
        def sensor(word):
            return dict(raw=word, index=(word >> 16) & 255, phase=(word >> 12) & 15,
                        clock_locked=bool(word & 2048), source_fault=bool(word & 512),
                        written=bool(word & 64), stable=bool(word & 32),
                        error=bool(word & 16), i2c_error=bool(word & 1))
        flags=(dfi >> 216) & 255
        pix_flags=(pix >> 160) & 65535
        result = dict(frame_type="job",version=data[2],sequence=int.from_bytes(data[6:8],"little"),
            fresh_mask=data[8],reset_n_mask=data[9],
            dfi=dict(last_source=[dfi & 0xffffffff,(dfi >> 32) & 0xffffffff],
                     epoch=(dfi >> 64) & 0xffffffff,session=(dfi >> 96) & 0xffffffff,
                     jobs=[(dfi >> 128) & 65535,(dfi >> 144) & 65535],
                     begin_reject=[(dfi >> 160) & 255,(dfi >> 168) & 255],
                     pair_expire=[(dfi >> 176) & 255,(dfi >> 184) & 255],
                     bad_finish=[(dfi >> 192) & 255,(dfi >> 200) & 255],
                     bank_states=[(dfi >> (208+2*k)) & 3 for k in range(4)],
                     flags=flags,raw=bool(flags & 1),hdr=bool(flags & 2),run=bool(flags & 4)),
            pixel=dict(fs=[pix & 65535,(pix >> 16) & 65535],
                       capture_admit=[(pix >> (32+16*k)) & 65535 for k in range(4)],
                       epoch=(pix >> 176) & 0xffffffff,flags=pix_flags,
                       hdr=bool(pix_flags & 1),stereo=bool(pix_flags & 2),raw=bool(pix_flags & 4)),
            sensor_sys=[sensor((pix >> 96) & 0xffffffff),sensor((pix >> 128) & 0xffffffff)],
            evidence_scope="DFI_PIX_INDEPENDENT_SNAPSHOTS_SYS_AT_PACKET_FREEZE",
            counter_policy="16BIT_MOD_JOBS_FS_ADMIT_8BIT_MOD_REJECT_EXPIRE_BAD_RESET_ON_RUN")
        if data[2] == 3:
            result["pixel"].pop("fs")
            cfg_flags=(pix >> 208) & 65535
            names=("frame_accept", "source_ready", "response_active", "response_space",
                   "remote_fault", "remote_applied", "remote_sent", "remote_pending",
                   "frame_apply_eligible")
            result["pixel"].update(cfg_applied_epoch=pix & 0xffffffff, cfg_flags=cfg_flags,
                cfg_state=(cfg_flags >> 9) & 7,
                cfg_gates={name: bool(cfg_flags & (1 << k)) for k,name in enumerate(names)},
                quiet={name: bool(cfg_flags & (1 << (12+k))) for k,name in enumerate(
                    ("cfg_pipeline", "physical_source", "maintenance", "native_pipeline"))})
            result["counter_policy"]="16BIT_MOD_JOBS_ADMIT_8BIT_MOD_REJECT_EXPIRE_BAD_RESET_ON_RUN"
        return result
    dfi_known = bool(data[8] & data[9] & 1) and bool((dfi >> 203) & 1)
    # An all-zero cold PIX page has not captured a first-window observation.
    pixel_known = bool(data[8] & data[9] & 2) and bool((pix >> 64) & ((1 << 41) - 1))
    return dict(frame_type="job", version=1, sequence=int.from_bytes(data[6:8], "little"),
        fresh_mask=data[8], reset_n_mask=data[9],
        dfi=dict(sequence=dfi & 0xffffffff, generation=(dfi >> 32) & 0xffffffff,
            session=(dfi >> 64) & 0xffffffff, epoch=(dfi >> 96) & 0xffffffff,
            jobs=[(dfi >> 128) & 65535, (dfi >> 144) & 65535],
            milestones=(dfi >> 160) & 65535, levels=(dfi >> 176) & 65535,
            ticket_error=(dfi >> 192) & 255, slot=(dfi >> 200) & 3,
            stalled=(dfi >> 205) & 1, wait_gates=(dfi >> 206) & 65535,
            camera=(dfi >> 202) & 1, seen=(dfi >> 203) & 1, watching=(dfi >> 204) & 1,
            scheduler_state=(dfi >> 188) & 15, ticket_state=(dfi >> 185) & 7,
            hdr=bool((dfi >> 222) & 1) if dfi_known else None,
            raw=bool((dfi >> 223) & 1) if dfi_known else None,
            hdr_context_seen=bool((dfi >> 170) & 1) if dfi_known else None,
            hdr_start_seen=bool((dfi >> 171) & 1) if dfi_known else None),
        pixel=dict(fs=[pix & 65535,(pix >> 16) & 65535],
            raw_admit=[(pix >> 32) & 65535,(pix >> 48) & 65535],
            milestones=(pix >> 64) & 65535,levels=(pix >> 80) & 65535,
            first_admission=(pix >> 96) & 1,admission_state=(pix >> 97) & 7, ticket_flags=(pix >> 100) & 15,
            stalled=(pix >> 104) & 1,
            hdr_sof_seen=dict(cam0_long=bool((pix >> 73) & 1) if pixel_known else None,
                              cam0_short=bool((pix >> 74) & 1) if pixel_known else None,
                              cam1_long=bool((pix >> 75) & 1) if pixel_known else None,
                              cam1_short=bool((pix >> 76) & 1) if pixel_known else None)))


class FrameDecoder:
    """Incremental mixed OB/CG/RX/RT parser; valid frames are consumed whole."""
    def __init__(self, *, pixel_layout: str = "mono"):
        self.pixel_layout = pixel_layout
        self.buffer=bytearray();self.frames=0;self.discarded_bytes=0;self.crc_errors=0;self.invalid_headers=0
        for kind in ("ob","cfg","rx","trace","job"):
            for suffix in ("frames","crc_errors","invalid_headers"):setattr(self,kind+"_"+suffix,0)
    def feed(self,data):
        self.buffer.extend(data);frames=[]
        while self.buffer:
            starts=[n for magic in (MAGIC,CFG_MAGIC,RX_MAGIC,TRACE_MAGIC,b"DJ") if (n:=self.buffer.find(magic))>=0]
            if not starts:
                keep=int(self.buffer[-1:] in (b"O",b"C",b"R",b"D"));n=len(self.buffer)-keep
                self.discarded_bytes+=n;del self.buffer[:n];break
            n=min(starts);self.discarded_bytes+=n;del self.buffer[:n]
            magic=bytes(self.buffer[:2]);kind={MAGIC:"ob",CFG_MAGIC:"cfg",RX_MAGIC:"rx",TRACE_MAGIC:"trace",b"DJ":"job"}[magic]
            size={"ob":29,"cfg":68,"rx":64,"trace":64,"job":68}[kind];head=4 if kind=="ob" else 6
            if len(self.buffer)<head:break
            valid=(self.buffer[2:4]==bytes((VERSION,FRAME_BYTES)) if kind=="ob" else
                self.buffer[2] in CFG_VERSIONS and self.buffer[3:6]==bytes((CFG_TYPE,CFG_FRAME_BYTES,0)) if kind=="cfg" else
                self.buffer[2] in (1,2,3) and self.buffer[3:6]==bytes((1,68,0)) if kind=="job" else
                self.buffer[2:6]==bytes((1,1,64,0)))
            if not valid:
                self.invalid_headers+=1;setattr(self,kind+"_invalid_headers",getattr(self,kind+"_invalid_headers")+1)
                self.discarded_bytes+=1;del self.buffer[0];continue
            if len(self.buffer)<size:break
            packet=bytes(self.buffer[:size])
            try:
                if kind == "ob":
                    decoded = decode_frame(packet, pixel_layout=self.pixel_layout)
                else:
                    decoded = {"cfg": decode_cfg_frame, "rx": decode_rx_frame,
                               "trace": decode_trace_frame, "job": decode_job_frame}[kind](packet)
            except ValueError as error:
                suffix="crc_errors" if "CRC" in str(error) else "invalid_headers"
                setattr(self,suffix,getattr(self,suffix)+1);setattr(self,kind+"_"+suffix,getattr(self,kind+"_"+suffix)+1)
                self.discarded_bytes+=1;del self.buffer[0];continue
            del self.buffer[:size];self.frames+=1;setattr(self,kind+"_frames",getattr(self,kind+"_frames")+1);frames.append(decoded)
        return frames
    def summary(self):
        result=dict(frames=self.frames,discarded_bytes=self.discarded_bytes,crc_errors=self.crc_errors,invalid_headers=self.invalid_headers)
        for kind in ("ob","cfg","rx","trace","job"):
            for suffix in ("frames","crc_errors","invalid_headers"):result[kind+"_"+suffix]=getattr(self,kind+"_"+suffix)
        result["trailing_bytes"]=len(self.buffer);return result


class ProgressView:
    """Modulo deltas are diagnostic only; invalid/reset intervals break history."""

    def __init__(self, *, cfg_reset_capture_guaranteed=True):
        self.previous_sequence = None
        self.previous = {}
        self.cfg_previous = None
        self.trace_assembler = TraceAssembler()
        # This v1 hardware contract observes business reset through the local
        # synchronized release (at least three edges), clearing domain valid.
        # Callers using hardware that cannot guarantee capture of a short reset
        # pulse must disable CFG association instead of inferring a new cohort.
        self.cfg_reset_capture_guaranteed = cfg_reset_capture_guaranteed

    def annotate_cfg(self, frame: dict) -> dict:
        user, pixel = frame["domains"]["user"], frame["domains"]["pixel"]
        sequence = frame["sequence"]
        pair = (user["reset_generation"], pixel["reset_generation"])
        identity = (user["session"], user["request_sequence"], user["target_epoch"])
        raw_relation = frame["association"]
        frame["identity_value_association"] = raw_relation
        frame["association_qualified"] = False
        usable = user["evidence_usable"] and pixel["evidence_usable"]
        candidate = (usable and sequence != 0 and self.cfg_reset_capture_guaranteed and
                     raw_relation == "MATCHING_IDENTITY_VALUES_ONLY")
        previous = self.cfg_previous
        if not candidate:
            self.cfg_previous = None
            if not usable or not self.cfg_reset_capture_guaranteed or sequence == 0:
                frame["association"] = "UNKNOWN"
            frame["association_filter"] = "invalid_sample_or_identity_breaks_baseline"
        else:
            # A late held mailbox ACK may still carry a prior reset-era sample.
            # Two consecutive fresh four-phase snapshots with an unchanged
            # per-domain generation pair filter out that single delayed bank.
            # Never require USER generation == PIX generation. Requiring the
            # same identity twice also avoids promoting a just-replaced request.
            if (previous is not None and sequence == previous[0] + 1 and
                    pair == previous[1] and identity == previous[2]):
                frame["association"] = "SAME_TRANSACTION_SAMPLED"
                frame["association_qualified"] = True
                frame["association_filter"] = "two_consecutive_fresh_stable_domain_generations"
            else:
                frame["association_filter"] = "matching_values_waiting_for_second_stable_sample"
            self.cfg_previous = (sequence, pair, identity)
        # This is an observation association filter, never event-time evidence:
        # neither the report sequence nor UART arrival dates a CFG milestone.
        frame["association_contract"] = "requires_local_reset_capture_no_event_time_proof"
        return frame

    def annotate(self, frame: dict) -> dict:
        if frame.get("frame_type") == "trace":
            self.trace_assembler.feed(frame)
            return frame
        if frame.get("frame_type") in {"job","rx"}:return frame
        if frame.get("frame_type") == "cfg":
            # CFG has different fields and shares the same report sequence as
            # its preceding OB. It must not perturb the legacy OB delta state.
            return self.annotate_cfg(frame)
        contiguous = False
        if self.previous_sequence is not None:
            step = (frame["sequence"] - self.previous_sequence) & 0xFFFF
            frame["sequence_step_mod65536"] = step
            contiguous = step == 1 and frame["sequence"] != 0
        # Sequence zero can be a cold restart or a natural 16-bit wrap. This
        # tiny protocol cannot distinguish them, so omit one delta in both
        # cases instead of treating reset counters as a large forward jump.
        if not contiguous:
            self.previous.clear()
        frame["report_continuity"] = "contiguous" if contiguous else "start_gap_or_restart"
        self.previous_sequence = frame["sequence"]
        for name, domain in frame["domains"].items():
            current = (domain["event0_mod65536"], domain["event1_mod65536"])
            prior = self.previous.get(name)
            usable = domain["fresh"] and not domain["in_reset"]
            domain["sample_state"] = "in_reset" if domain["in_reset"] else (
                "fresh" if domain["fresh"] else "stale_or_unavailable")
            domain["event_deltas_mod65536"] = (
                [(value - old) & 0xFFFF for value, old in zip(current, prior)]
                if usable and prior is not None else None)
            self.previous[name] = current if usable else None
        return frame


def emit(decoder: FrameDecoder, view: ProgressView, data: bytes, output) -> None:
    for frame in decoder.feed(data):
        print(json.dumps(view.annotate(frame), sort_keys=True), file=output, flush=True)


def read_serial(port: str, seconds: float, decoder: FrameDecoder, output,
                capture=None, *, serial_module=None, monotonic=None, view=None) -> None:
    # Validate before loading pyserial or opening any device. A different COM
    # name is not a transport fallback and must never select RK's COM7.
    if port.upper() != "COM12":
        raise ValueError("observer reception is restricted to COM12; COM7 is RK control")
    if not 0 < seconds <= 3600:
        raise ValueError("--seconds must be in (0, 3600]")
    driver = serial_module or importlib.import_module("serial")
    clock = monotonic or time.monotonic
    connection = driver.Serial(port=None, baudrate=BAUD, bytesize=8, parity="N", stopbits=1,
                               timeout=0.25, xonxoff=False, rtscts=False, dsrdtr=False)
    connection.dtr = False
    connection.rts = False
    connection.port = "COM12"
    view = view or ProgressView()
    try:
        connection.open()
        deadline = clock() + seconds
        while clock() < deadline:
            data = connection.read(256)
            if capture is not None:
                capture.write(data)
            emit(decoder, view, data, output)
    finally:
        connection.close()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--input", type=Path, help="decode a saved binary capture, no serial access")
    mode.add_argument("--listen", action="store_true", help="explicitly open COM12 for receive-only observation")
    parser.add_argument("--port", default="COM12")
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--capture", type=Path, help="save received bytes during explicit --listen")
    parser.add_argument("--pixel-layout", choices=("mono", "stereo"), default="mono",
                        help="OB/V2 pixel flag layout known from the captured runtime mode")
    parser.add_argument("--trace-output", type=Path, help="create JSON of complete/incomplete RT captures; never overwrites")
    args = parser.parse_args(argv)
    if args.input is not None and args.capture is not None:
        parser.error("--capture is only used with --listen")
    decoder = FrameDecoder(pixel_layout=args.pixel_layout)
    view = ProgressView()
    try:
        if args.input is not None:
            with args.input.open("rb") as source:
                while data := source.read(4096):
                    emit(decoder, view, data, sys.stdout)
        elif args.capture is not None:
            with args.capture.open("xb") as capture:
                read_serial(args.port, args.seconds, decoder, sys.stdout, capture, view=view)
        else:
            read_serial(args.port, args.seconds, decoder, sys.stdout, view=view)
        if args.trace_output is not None:
            with args.trace_output.open("x", encoding="utf-8") as target:
                json.dump(view.trace_assembler.snapshot(), target, indent=2)
                target.write("\n")
    except (OSError, ValueError, ImportError) as error:
        parser.exit(2, str(error) + "\n")
    print(json.dumps({"decoder": decoder.summary()}), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
