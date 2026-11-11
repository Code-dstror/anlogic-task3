"""Public SDK parameter checks against a CFG BAR register model."""

import json
import unittest
from pathlib import Path

from dual_host.camera_shared import validate_profile
from dual_host.debug_modes import SharedControls
from linux.task3_pipeline.config_transaction import ConfigError, Configuration, ConfigTransactions
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration


ROOT = Path(__file__).resolve().parents[5]
PROTOCOL = json.loads((ROOT / "docs/pcie_protocol_v1.json").read_text(encoding="utf-8"))
REG = {name: int(offset, 0) for name, offset in PROTOCOL["registers"].items()}
CFG = PROTOCOL["config_transaction"]
EXT = PROTOCOL["advanced_config"]
V2 = PROTOCOL["advanced_config_v2"]
COMMAND = CFG["commands"]
STATUS = {name: 1 << bit for name, bit in CFG["status_bits"].items()}
SESSION = 0x5A120011
MAX_NS = 0xFFFFFFFF
BASE_FIELDS = {
    "mode": "MODE",
    "quality": "QUALITY",
    "flags": "FLAGS",
    "min_quality": "MIN_QUALITY",
    "frame_budget": "FRAME_BUDGET",
    "restart_mcus": "RESTART_MCUS",
}
BASE_DEFAULT = {
    "mode": 0,
    "quality": 75,
    "flags": 0,
    "min_quality": 1,
    "frame_budget": 0,
    "restart_mcus": 0,
}
HDR_POLICY = {
    "hdr_ratio": 4,
    "hdr_black_long": 50,
    "hdr_black_short": 50,
    "hdr_motion_base": 64,
    "hdr_motion_shift": 3,
    "hdr_qualification": 15,
    "hdr_max_delta_ns": 50_000_000,
    "hdr_max_wait_ns": 100_000_000,
    "hdr_max_age_ns": 1_000_000_000,
}
SDR_PROFILE = {
    "product_mode": 0,
    "processing_enables": 0,
    "dehaze_lut_generation": 0,
    **dict.fromkeys(HDR_POLICY, 0),
}
HDR_PROFILE = dict(SDR_PROFILE, product_mode=2, processing_enables=2 | 8, **HDR_POLICY)


def extension_words(profile):
    """Pack the public field offsets independently of the SDK serializer."""
    values = {**profile, "schema": V2["schema"]}
    packed = 0
    for field in V2["fields"]:
        value = values[field["name"].lower()]
        if not 0 <= value < (1 << field["width"]):
            raise AssertionError(f"invalid oracle input for {field['name']}: {value}")
        packed |= value << field["offset"]
    raw = packed.to_bytes(V2["width_bits"] // 8, "little")
    return tuple(int.from_bytes(raw[i:i + 4], "little") for i in range(0, len(raw), 4))


class ConfigBar:
    """Serve only public BAR I/O, with separate READY and APPLIED polls."""

    def __init__(self, *, dual=False, corrupt_active=False):
        self.registers = {
            REG["DEVICE_MAGIC"]: int(PROTOCOL["device_magic"], 0),
            REG["PROTOCOL_VERSION"]: PROTOCOL["protocol_version"],
            REG["CAPABILITIES"]: 1 << PROTOCOL["capability_bits"]["CONFIG_TRANSACTION"],
            REG["SLOT_COUNT"]: PROTOCOL["slot_count"],
            REG["MAX_PAYLOAD"]: PROTOCOL["max_payload"],
            REG["HEADER_LENGTH"]: PROTOCOL["header_length"],
            REG["CFG_MAGIC"]: int(CFG["magic"], 0),
            REG["CFG_ABI_VERSION"]: CFG["abi_version"],
            REG["CFG_FEATURES"]: sum(1 << bit for bit in CFG["features"].values()),
            REG["CFG_COMPILED_PROFILE"]: CFG["profiles"]["DUAL1920" if dual else "MONO1920"],
            REG["CFG_CAMERA_PRESENT"]: 3 if dual else 1,
            REG["CFG_MAX_WIDTH"]: 1920,
            REG["CFG_MAX_HEIGHT"]: 1080,
            REG["CFG_SESSION"]: SESSION,
            REG["CFG_STATUS"]: STATUS["SESSION_READY"],
            REG["CFG_RESPONSE_SEQUENCE"]: 0,
            REG["CFG_ERROR"]: CFG["error_codes"]["OK"],
            REG["CFG_MODE_EPOCH"]: 0,
            REG["CFG_APPLIED_FIRST_SEQUENCE"]: 0,
            REG["CFG_APPLIED_CAMERA"]: 0,
            REG["CFG_ACTIVE_SESSION"]: SESSION,
            REG["CFG_HOST_CAPABILITIES"]: 1,
            REG["CFG_EXT_MAGIC"]: int(EXT["magic"], 0),
            REG["CFG_EXT_ABI_VERSION"]: EXT["abi_version"],
            REG["CFG_EXT_WIDTH"]: EXT["width_bits"],
            REG["CFG_EXT_SUPPORTED"]: 0x34,
            REG["CFG_EXT_STRIPS"]: 4,
            REG["CFG_EXT_APPLIED_LUT_GENERATION"]: 0,
            REG["CFG_EXT_COMBINATIONS"]: 0,
            REG["CFG_EXT_SCHEMAS"]: V2["supported_schemas"],
            REG["CFG_EXT_V2_MODES"]: 0b101,
            REG["CFG_EXT_V2_ENABLES"]: 0x0F if dual else 0x3F,
        }
        self.shadow = tuple(REG["CFG_EXT_SHADOW_BASE"] + i * 4 for i in range(V2["word_count"]))
        self.active = tuple(REG["CFG_EXT_ACTIVE_BASE"] + i * 4 for i in range(V2["word_count"]))
        self.request = {REG[f"CFG_REQUEST_{field}"] for field in BASE_FIELDS.values()}
        self.request.update({REG["CFG_REQUEST_SEQUENCE"], REG["CFG_REQUEST_SESSION"]})
        self.registers.update(dict.fromkeys(self.shadow + self.active, 0))
        self.registers.update(dict.fromkeys(self.request, 0))
        for key, suffix in BASE_FIELDS.items():
            self.registers[REG[f"CFG_ACTIVE_{suffix}"]] = BASE_DEFAULT[key]
        self.writes = []
        self.prepares = []
        self.commits = []
        self.next_status = None
        self.status_polls_remaining = 0
        self.corrupt_active = corrupt_active

    def read32(self, offset):
        if offset == REG["CFG_STATUS"] and self.next_status is not None:
            self.status_polls_remaining -= 1
            if self.status_polls_remaining == 0:
                if self.next_status == "APPLIED":
                    self.publish_active()
                busy = STATUS["BUSY"] if self.next_status == "READY" else 0
                self.registers[offset] = STATUS["SESSION_READY"] | busy | STATUS[self.next_status]
                self.next_status = None
        return self.registers[offset]

    def write32(self, offset, value):
        self.writes.append((offset, value))
        if offset in self.request or offset in self.shadow or offset == REG["CFG_HOST_CAPABILITIES"]:
            self.registers[offset] = value
            return
        if offset != REG["CFG_COMMAND"]:
            raise AssertionError(f"unexpected BAR write at {offset:#x}")

        session = self.registers[REG["CFG_REQUEST_SESSION"]]
        sequence = self.registers[REG["CFG_REQUEST_SEQUENCE"]]
        if session != SESSION or sequence == 0:
            raise AssertionError(f"incorrect CFG request identity {(session, sequence)}")

        if value == COMMAND["PREPARE_EXT"]:
            if self.registers[REG["CFG_STATUS"]] & STATUS["BUSY"]:
                raise AssertionError("PREPARE_EXT arrived while CFG was busy")
            base = {
                key: self.registers[REG[f"CFG_REQUEST_{suffix}"]]
                for key, suffix in BASE_FIELDS.items()
            }
            words = tuple(self.registers[address] for address in self.shadow)
            self.prepares.append((sequence, base, words))
            self.registers[REG["CFG_RESPONSE_SEQUENCE"]] = sequence
            self.next_status = "READY"
        elif value == COMMAND["COMMIT"]:
            if not self.registers[REG["CFG_STATUS"]] & STATUS["READY"]:
                raise AssertionError("COMMIT arrived before READY")
            if sequence != self.prepares[-1][0]:
                raise AssertionError("COMMIT did not retain the prepared sequence")
            self.commits.append(sequence)
            self.next_status = "APPLIED"
        else:
            raise AssertionError(f"unexpected CFG command {value}")

        self.registers[REG["CFG_STATUS"]] = STATUS["SESSION_READY"] | STATUS["BUSY"]
        self.status_polls_remaining = 2

    def publish_active(self):
        _, base, words = self.prepares[-1]
        for key, suffix in BASE_FIELDS.items():
            self.registers[REG[f"CFG_ACTIVE_{suffix}"]] = base[key]
        self.registers.update(zip(self.active, words, strict=True))
        if self.corrupt_active:
            self.registers[self.active[-1]] ^= 1
        self.registers[REG["CFG_MODE_EPOCH"]] += 1
        self.registers[REG["CFG_APPLIED_FIRST_SEQUENCE"]] = 300 + self.registers[REG["CFG_MODE_EPOCH"]]
        self.registers[REG["CFG_EXT_APPLIED_LUT_GENERATION"]] = words[11]


class ParameterContractTests(unittest.TestCase):
    def make_owner(self, *, dual=False, corrupt_active=False):
        bar = ConfigBar(dual=dual, corrupt_active=corrupt_active)
        transactions = ConfigTransactions(bar, timeout_s=0.25, poll_interval_s=0.001)
        controls = SharedControls(transactions, lut_timeout_s=0.25)
        return bar, transactions, controls

    def propose(self, bar, transactions, controls, document):
        before = list(bar.writes)
        try:
            proposal = controls.propose(document)
            validate_profile(transactions, proposal.configuration, proposal.extension)
        finally:
            self.assertEqual(bar.writes, before, "preflight wrote to BAR")
        return proposal

    def apply(self, bar, transactions, controls, document, *, base, profile):
        before = controls.read_active()
        proposal = self.propose(bar, transactions, controls, document)
        expected = extension_words(profile)
        self.assertEqual(proposal.configuration, Configuration(**base))
        self.assertEqual(proposal.extension, MonoConfiguration(**profile))
        self.assertEqual(proposal.extension_words, expected)

        writes_before = len(bar.writes)
        prepared = transactions.prepare(proposal.configuration, extension=proposal.extension)
        self.assertEqual(bar.read32(REG["CFG_STATUS"]), STATUS["READY"] | STATUS["BUSY"] | STATUS["SESSION_READY"])
        self.assertEqual(bar.read32(REG["CFG_MODE_EPOCH"]), before.mode_epoch)
        self.assertEqual(tuple(bar.read32(address) for address in bar.active), before.extension_words)
        transactions.commit(prepared)

        actual_writes = bar.writes[writes_before:]
        commands = [value for address, value in actual_writes if address == REG["CFG_COMMAND"]]
        self.assertEqual(commands, [COMMAND["PREPARE_EXT"], COMMAND["COMMIT"]])
        shadow_writes = [(address, value) for address, value in actual_writes if address in bar.shadow]
        self.assertEqual(sorted(shadow_writes), list(zip(bar.shadow, expected, strict=True)))
        sequence, sent_base, sent_words = bar.prepares[-1]
        self.assertEqual(bar.commits[-1], sequence)
        self.assertEqual(sent_base, base)
        self.assertEqual(sent_words, expected)

        active = controls.read_active()
        self.assertEqual(active.session, SESSION)
        self.assertEqual(active.mode_epoch, before.mode_epoch + 1)
        self.assertEqual(active.first_actual_frame_sequence, 300 + active.mode_epoch)
        self.assertEqual(active.request_sequence, sequence)
        self.assertEqual(active.configuration, Configuration(**base))
        self.assertEqual(active.extension, MonoConfiguration(**profile))
        self.assertEqual(active.extension_words, expected)
        self.assertEqual(active.schema, 2)
        return active

    def test_discovery_publishes_parameter_limits_and_topology(self):
        base_bounds = {
            "quality": (1, 100, "quality", 75),
            "min_quality": (1, 100, "quality", 1),
            "flags": (0, 1, "bitmask", 0),
            "frame_budget": (0, 16_777_216, "bytes", 0),
            "restart_mcus": (0, 65_535, "MCU", 0),
        }
        hdr_bounds = {
            "hdr_motion_base": (0, 16_383, "RAW14 code", None),
            "hdr_motion_shift": (0, 15, "bit", None),
            "hdr_max_delta_ns": (0, MAX_NS, "ns", None),
            "hdr_max_wait_ns": (1, MAX_NS, "ns", None),
            "hdr_max_age_ns": (1, MAX_NS, "ns", None),
        }
        hdr_fixed = {
            "hdr_ratio": (4, "log2"),
            "hdr_black_long": (50, "RAW10 code"),
            "hdr_black_short": (50, "RAW10 code"),
            "hdr_qualification": (15, "bitmask"),
        }
        for dual in (False, True):
            with self.subTest(dual=dual):
                bar, _, controls = self.make_owner(dual=dual)
                before = list(bar.writes)
                report = controls.discover()
                self.assertEqual(report["profile"], "camera_shared_r1")
                self.assertIn("base", report)
                self.assertIn("schema2", report)
                self.assertEqual(report["active"], controls.read_active().as_dict())
                self.assertEqual(bar.writes, before)

                parameters = report["parameters"]
                base = {row["path"]: row for row in parameters["base"]}
                schema = {row["path"]: row for row in parameters["schemas"]["2"]}
                self.assertEqual(len(base), len(parameters["base"]))
                self.assertEqual(len(schema), len(parameters["schemas"]["2"]))
                for prefix, rows, bounds in (("base", base, base_bounds), ("extension", schema, hdr_bounds)):
                    for name, expected in bounds.items():
                        row = rows[f"{prefix}.{name}"]
                        self.assertEqual(tuple(row[key] for key in ("minimum", "maximum", "unit", "default")),
                                         expected, name)
                        self.assertEqual(row["access"], "writable", name)
                        if prefix == "extension":
                            self.assertEqual(row["disabled_value"], 0, name)
                for name, (value, unit) in hdr_fixed.items():
                    row = schema[f"extension.{name}"]
                    self.assertEqual((row["value"], row["minimum"], row["maximum"], row["unit"], row["access"],
                                      row["disabled_value"]), (value, value, value, unit, "fixed", 0), name)
                self.assertEqual((base["base.mode"]["value"], base["base.mode"]["access"]), (0, "fixed"))
                self.assertEqual((schema["extension.schema"]["value"], schema["extension.schema"]["access"]),
                                 (2, "fixed"))
                self.assertTrue(base["base.min_quality"]["depends_on"])
                self.assertEqual(base["base.flags"]["symbols"], {"ADAPTIVE_QUALITY": 1})
                self.assertEqual(schema["extension.product_mode"]["symbols"], {"MONO_SDR": 0, "MONO_HDR": 2})
                enables = {key: mask for key, mask in V2["enables"].items() if not dual or mask & 0x0F}
                self.assertEqual(schema["extension.processing_enables"]["symbols"], enables)
                generation = schema["extension.dehaze_lut_generation"]
                self.assertEqual((generation["minimum"], generation["maximum"], generation["default"],
                                  generation["access"]), (0, 1, 0, "writable"))
                constraints = parameters["constraints"]
                self.assertEqual(constraints["dual_d2_quality"], 75)
                self.assertIs(constraints["raw_online_cfg"], False)
                self.assertIs(constraints["host_lut_upload"], False)

    def test_mono_updates_preserve_the_entire_active_snapshot(self):
        bar, transactions, controls = self.make_owner()
        boot = controls.read_active()
        self.assertEqual((boot.schema, boot.mode_epoch, boot.configuration), (0, 0, Configuration(**BASE_DEFAULT)))
        self.assertEqual(boot.extension_words, (0,) * 32)

        base = dict(BASE_DEFAULT, quality=79, flags=1, min_quality=22, frame_budget=16_777_216, restart_mcus=65_535)
        first_profile = dict(HDR_PROFILE, hdr_motion_base=16_383, hdr_max_delta_ns=MAX_NS,
                             hdr_max_wait_ns=1, hdr_max_age_ns=MAX_NS, dehaze_lut_generation=1)
        first = {"schema": 2, "base": dict(base, flags=["ADAPTIVE_QUALITY"]), "extension": first_profile}
        self.apply(bar, transactions, controls, json.dumps(first), base=base, profile=first_profile)

        base = dict(base, quality=80)
        next_profile = dict(first_profile, hdr_motion_shift=4)
        patch = {"base": {"quality": 80}, "extension": {"hdr_motion_shift": 4}}
        self.apply(bar, transactions, controls, patch, base=base, profile=next_profile)

        sdr = dict(SDR_PROFILE, processing_enables=1 | 4 | 8 | 16 | 32)
        base = dict(BASE_DEFAULT, quality=1)
        self.apply(bar, transactions, controls, {"base": base, "extension": sdr}, base=base, profile=sdr)
        self.assertEqual(sorted(set(bar.commits)), bar.commits)

    def test_dual_uses_existing_sdr_and_hdr_controls(self):
        bar, transactions, controls = self.make_owner(dual=True)
        base = dict(BASE_DEFAULT, quality=100, min_quality=100)
        sdr = dict(SDR_PROFILE, processing_enables=1 | 2 | 4 | 8, dehaze_lut_generation=1)
        self.apply(bar, transactions, controls, {"schema": 2, "base": base, "extension": sdr},
                   base=base, profile=sdr)
        hdr = dict(HDR_PROFILE, hdr_motion_base=0, hdr_motion_shift=15, hdr_max_delta_ns=0,
                   hdr_max_wait_ns=MAX_NS, hdr_max_age_ns=1)
        self.apply(bar, transactions, controls, {"extension": hdr}, base=base, profile=hdr)

    def test_rejects_bad_requests_before_any_cfg_writes(self):
        bad_base = {
            "quality below range": {"quality": 0},
            "quality above range": {"quality": 101},
            "min quality above quality": {"quality": 71, "min_quality": 72},
            "min quality below range": {"min_quality": 0},
            "unknown numeric flag": {"flags": 2},
            "unknown flag name": {"flags": ["UNKNOWN"]},
            "adaptive without budget": {"flags": 1, "frame_budget": 0},
            "budget above range": {"frame_budget": 16_777_217},
            "restart above range": {"restart_mcus": 65_536},
            "non-color schema2 base": {"mode": 1},
        }
        bad_profile = {
            "dynamic ratio": {"hdr_ratio": 3},
            "dynamic long black": {"hdr_black_long": 51},
            "dynamic short black": {"hdr_black_short": 49},
            "other qualification": {"hdr_qualification": 14},
            "motion above range": {"hdr_motion_base": 16_384},
            "shift above range": {"hdr_motion_shift": 16},
            "delta high word": {"hdr_max_delta_ns": MAX_NS + 1},
            "wait zero": {"hdr_max_wait_ns": 0},
            "age zero": {"hdr_max_age_ns": 0},
            "other dehaze generation": {"dehaze_lut_generation": 2},
            "generation while dehaze disabled": {"processing_enables": 8, "dehaze_lut_generation": 1},
            "SDR with stale HDR policy": {"product_mode": 0},
            "LZ product": {"product_mode": 1},
            "unknown processing bit": {"processing_enables": 64},
            "mono lane without F22": {"processing_enables": 32},
        }
        cases = {
            **{label: {"schema": 2, "base": change, "extension": HDR_PROFILE} for label, change in bad_base.items()},
            **{label: {"schema": 2, "extension": dict(HDR_PROFILE, **change)} for label, change in bad_profile.items()},
            "schema0 cannot supply a missing HDR policy": {"schema": 2, "extension": {"product_mode": 2}},
            "schema0 cannot supply a missing SDR field": {
                "schema": 2,
                "extension": {key: value for key, value in SDR_PROFILE.items() if key != "dehaze_lut_generation"},
            },
        }
        bar, transactions, controls = self.make_owner()
        before = controls.read_active()
        for label, document in cases.items():
            with self.subTest(label=label), self.assertRaises((ConfigError, ValueError)):
                self.propose(bar, transactions, controls, document)
        self.assertEqual(controls.read_active(), before)
        self.apply(bar, transactions, controls, {"schema": 2, "extension": HDR_PROFILE},
                   base=BASE_DEFAULT, profile=HDR_PROFILE)

    def test_dual_rejects_mono_only_bits(self):
        bar, transactions, controls = self.make_owner(dual=True)
        before = controls.read_active()
        for enables in (16, 16 | 32):
            with self.subTest(enables=enables), self.assertRaises((ConfigError, ValueError)):
                self.propose(bar, transactions, controls,
                             {"schema": 2, "extension": dict(SDR_PROFILE, processing_enables=enables)})
        self.assertEqual(controls.read_active(), before)

    def test_commit_rejects_corruption_in_the_last_active_word(self):
        bar, transactions, controls = self.make_owner(corrupt_active=True)
        proposal = self.propose(bar, transactions, controls, {"schema": 2, "extension": HDR_PROFILE})
        prepared = transactions.prepare(proposal.configuration, extension=proposal.extension)
        with self.assertRaises(ConfigError):
            transactions.commit(prepared)
        self.assertEqual(len(bar.commits), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
