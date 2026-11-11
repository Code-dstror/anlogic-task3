"""Check released public SDK entry points against an independent CFG1 BAR oracle."""

import argparse
import json
import traceback
from pathlib import Path

import dual_host.debug_modes as debug_modes
import linux.task3_pipeline.config_transaction as transactions
import linux.task3_pipeline.mono_config_v2 as schema2


PROJECT = Path(__file__).resolve().parents[3]
ABI = json.loads((PROJECT / "docs/pcie_protocol_v1.json").read_text(encoding="utf-8"))
RECORD_V4 = json.loads((PROJECT.parents[1] / "docs/pcie_protocol_v1.json").read_text(encoding="utf-8"))["record_v4"]
QUALITY = json.loads((PROJECT / "docs/quality_control_v1.json").read_text(encoding="utf-8"))
REG = {name: int(offset, 0) for name, offset in ABI["registers"].items()}
CFG = ABI["config_transaction"]
EXT = ABI["advanced_config"]
V2 = ABI["advanced_config_v2"]
FEATURE_QUALITY = 1 << QUALITY["feature_bit"]
BASE_FIELDS = {
    "mode": "MODE", "quality": "QUALITY", "flags": "FLAGS", "min_quality": "MIN_QUALITY",
    "frame_budget": "FRAME_BUDGET", "restart_mcus": "RESTART_MCUS",
}
BOOT_BASE = dict(mode=0, quality=75, flags=0, min_quality=1, frame_budget=0, restart_mcus=0)
CUSTOM_BASE = dict(mode=0, quality=88, flags=1, min_quality=31, frame_budget=406_119, restart_mcus=59)
QUALITY_VALUES = dict(quality_version=1, hdr_tone_preset=3, hdr_fusion_preset=1,
                      isp_wb_enable=1, isp_wb_r=997, isp_wb_g=311, isp_wb_b=743)
WORD_COUNT = V2["word_count"]
ZERO_WORDS = (0,) * WORD_COUNT
# RATE_CONTROL_CONTRACT.md, JPEG = 0 and RAW = 1.
COLD_ACTIVE_PRODUCT = 0xFAC


def wire_words(extension):
    packed = 0
    fields = V2["fields"] + QUALITY["fields"]
    assert extension.keys() <= {field["name"].lower() for field in fields}
    for field in fields:
        value = extension.get(field["name"].lower(), 0)
        assert type(value) is int and 0 <= value < 1 << field["width"]
        packed |= value << field["offset"]
    return tuple((packed >> (32 * index)) & 0xFFFFFFFF for index in range(WORD_COUNT))


def extension_document(product_mode=0, processing_enables=0):
    result = {field["name"].lower(): 0 for field in V2["fields"]}
    result.update(schema=2, product_mode=product_mode, processing_enables=processing_enables)
    if product_mode == 2:
        result.update(hdr_ratio=4, hdr_black_long=50, hdr_black_short=50, hdr_qualification=15,
                      hdr_motion_base=1287, hdr_motion_shift=9, hdr_max_delta_ns=38_617_123,
                      hdr_max_wait_ns=102_410_427, hdr_max_age_ns=802_931_547)
    if processing_enables & 2:
        result["dehaze_lut_generation"] = 1
    return result


def document(extension, base=CUSTOM_BASE):
    return {"schema": 2, "base": base.copy(), "extension": extension.copy()}


def configuration(base):
    return transactions.Configuration(**base)


def extension_object(extension):
    return schema2.MonoConfiguration(**{key: value for key, value in extension.items() if key != "schema"})


class PublicBar:
    def __init__(self, profile, features, enables, *, active=ZERO_WORDS, schema_mask=None, product=0):
        self.profile = profile
        self.features = features
        self.enables = enables
        self.modes = 1 if profile == 3 else 5
        self.present = 3 if profile == 2 else 1
        self.width, self.height = (3840, 2160) if profile == 3 else (1920, 1080)
        self.schemas = (4 if profile == 3 else 6) if schema_mask is None else schema_mask
        self.product = product
        self.session = 0x10493FA9
        self.status = 20
        self.sequence = 0
        self.epoch = 0
        self.first = 0
        self.active_words = active
        self.active_base = BOOT_BASE.copy()
        self.shadow_base = {}
        self.shadow_words = {}
        self.writes = []
        self.commands = []
        self.host_capabilities = 0
        self.expect_base = None
        self.expect_words = None
        self.pending = None
        self.corrupt_word = None

    def expect(self, base, extension, *, corrupt_word=None):
        self.expect_base = base.copy()
        self.expect_words = wire_words(extension)
        self.corrupt_word = corrupt_word

    def read32(self, offset):
        if offset == COLD_ACTIVE_PRODUCT:
            return self.product
        active_offset = offset - REG["CFG_EXT_ACTIVE_BASE"]
        if 0 <= active_offset < 4 * WORD_COUNT and active_offset % 4 == 0:
            return self.active_words[active_offset // 4]
        values = {
            "DEVICE_MAGIC": int(ABI["device_magic"], 0), "PROTOCOL_VERSION": ABI["protocol_version"],
            "CAPABILITIES": ((1 << ABI["capability_bits"]["CONFIG_TRANSACTION"])
                             | (1 << ABI["capability_bits"]["RECORD_V2"])),
            "SLOT_COUNT": ABI["slot_count"], "MAX_PAYLOAD": ABI["max_payload"],
            "HEADER_LENGTH": ABI["header_length"],
            "CONTROL": 1 << ABI["control_bits"]["APP_ENABLE"],
            "STATUS": (1 << ABI["status_bits"]["LINK_UP"]) | (1 << ABI["status_bits"]["USER_RESET_RELEASED"]),
            "RECORD_MAGIC": int(ABI["record_v2"]["magic"], 0),
            "RECORD_ABI_VERSION": ABI["record_v2"]["abi_version"],
            # LANE_POINTS is a record format capability. It does not enable lane processing.
            "RECORD_FEATURES": 7 | (1 << RECORD_V4["features"]["VERSION4"])
                               | (1 << RECORD_V4["features"]["LANE_POINTS"]),
            "RECORD_SUPPORTED_VERSIONS": RECORD_V4["supported_versions"],
            "RECORD_STATUS": 1 << ABI["record_v2"]["status_bits"]["DONE"],
            "RECORD_SELECTED_VERSION": RECORD_V4["version"],
            "RECORD_SELECTED_HEADER_LENGTH": RECORD_V4["header_length"],
            "RECORD_RESPONSE_SEQUENCE": 1, "RECORD_RESPONSE_SESSION": self.session,
            "RECORD_ERROR": 0, "RECORD_SELECTION_EPOCH": 1,
            "ALGO_MAGIC": 0, "RAW_MAGIC": 0, "JPEG_MAGIC": 0,
            "CFG_MAGIC": int(CFG["magic"], 0), "CFG_ABI_VERSION": CFG["abi_version"],
            "CFG_FEATURES": self.features, "CFG_COMPILED_PROFILE": self.profile,
            "CFG_CAMERA_PRESENT": self.present, "CFG_MAX_WIDTH": self.width,
            "CFG_MAX_HEIGHT": self.height, "CFG_SESSION": self.session,
            "CFG_STATUS": self.status, "CFG_RESPONSE_SEQUENCE": self.sequence,
            "CFG_ERROR": 0, "CFG_MODE_EPOCH": self.epoch,
            "CFG_APPLIED_FIRST_SEQUENCE": self.first, "CFG_APPLIED_CAMERA": 0,
            "CFG_HOST_CAPABILITIES": self.host_capabilities, "CFG_ACTIVE_SESSION": self.session,
            "CFG_EXT_MAGIC": int(EXT["magic"], 0), "CFG_EXT_ABI_VERSION": EXT["abi_version"],
            "CFG_EXT_WIDTH": EXT["width_bits"], "CFG_EXT_SUPPORTED": 4 if self.profile == 1 else 0,
            "CFG_EXT_STRIPS": 0, "CFG_EXT_COMBINATIONS": 0,
            "CFG_EXT_APPLIED_LUT_GENERATION": self.active_words[11],
            "CFG_EXT_SCHEMAS": self.schemas, "CFG_EXT_V2_MODES": self.modes,
            "CFG_EXT_V2_ENABLES": self.enables,
        }
        values.update({f"CFG_ACTIVE_{suffix}": self.active_base[field] for field, suffix in BASE_FIELDS.items()})
        by_offset = {REG[name]: value for name, value in values.items()}
        assert offset in by_offset, f"unexpected BAR read at {offset:#x}"
        return by_offset[offset]

    def write32(self, offset, value):
        assert type(value) is int and 0 <= value <= 0xFFFFFFFF
        self.writes.append((offset, value))
        if offset == REG["CFG_HOST_CAPABILITIES"]:
            assert value == 1
            self.host_capabilities = value
            return
        shadow_offset = offset - REG["CFG_EXT_SHADOW_BASE"]
        if 0 <= shadow_offset < 4 * WORD_COUNT and shadow_offset % 4 == 0:
            self.shadow_words[shadow_offset // 4] = value
            return
        if offset == REG["CFG_COMMAND"]:
            self.command(value)
            return
        request_offsets = {REG[f"CFG_REQUEST_{suffix}"]: field for field, suffix in BASE_FIELDS.items()}
        request_offsets.update({REG["CFG_REQUEST_SESSION"]: "session", REG["CFG_REQUEST_SEQUENCE"]: "sequence"})
        assert offset in request_offsets, f"unexpected BAR write at {offset:#x}"
        self.shadow_base[request_offsets[offset]] = value

    def command(self, value):
        self.commands.append(value)
        if value == CFG["commands"]["PREPARE_EXT"]:
            assert self.pending is None and self.host_capabilities == 1
            assert self.shadow_base["session"] == self.session
            next_sequence = self.shadow_base["sequence"]
            assert next_sequence != 0 and next_sequence != self.sequence
            staged_base = {field: self.shadow_base[field] for field in BASE_FIELDS}
            assert staged_base == self.expect_base, (staged_base, self.expect_base)
            assert set(self.shadow_words) == set(range(WORD_COUNT)), "PREPARE_EXT did not stage all 32 words"
            staged_words = tuple(self.shadow_words[index] for index in range(WORD_COUNT))
            assert staged_words == self.expect_words, (staged_words, self.expect_words)
            assert self.features & FEATURE_QUALITY or (staged_words[1] == staged_words[12] == 0)
            self.sequence = next_sequence
            self.pending = (staged_base, staged_words)
            self.status = 19
        elif value == CFG["commands"]["COMMIT"]:
            assert self.pending is not None and self.status == 19
            assert self.shadow_base["session"] == self.session
            assert self.shadow_base["sequence"] == self.sequence
            self.active_base, self.active_words = self.pending
            if self.corrupt_word is not None:
                corrupted = list(self.active_words)
                corrupted[self.corrupt_word] ^= 1
                self.active_words = tuple(corrupted)
            self.epoch += 1
            self.first = 123 + self.epoch * 17
            self.status = 20
            self.pending = None
            self.shadow_words.clear()
        else:
            raise AssertionError(f"unexpected CFG command {value}")


def owner(bar):
    return transactions.ConfigTransactions(bar, timeout_s=0.2, poll_interval_s=0.001)


def controls(tx):
    return debug_modes.SharedControls(tx, lut_timeout_s=0.2)


def expect_rejection(action, bar, reason, code=None):
    previous = (len(bar.writes), bar.epoch, bar.active_words)
    try:
        action()
    except (transactions.ConfigError, ValueError) as error:
        if code is not None:
            assert getattr(error, "code", None) == CFG["error_codes"][code], (reason, type(error), str(error))
    else:
        raise AssertionError(f"{reason} unexpectedly accepted")
    assert previous == (len(bar.writes), bar.epoch, bar.active_words), f"{reason} changed the BAR"


def check_capabilities(edition):
    profiles = [(1, 63, 63), (1, 127, 63), (2, 63, 15), (2, 127, 15),
                (3, 15, 0), (3, 63, 13), (3, 127, 13)]
    for profile, features, enables in profiles:
        bar = PublicBar(profile, features, enables, active=wire_words(extension_document()))
        if edition == "old" and profile == 3 and features & FEATURE_QUALITY:
            expect_rejection(lambda: owner(bar).mono_capabilities(), bar, "old SDK on new UHD", "UNSUPPORTED")
            print("compat old SDK on new UHD rejected UNSUPPORTED before BAR writes")
            continue
        tx = owner(bar)
        expected_version = int(edition == "new" and features & FEATURE_QUALITY != 0)
        base = tx.capabilities
        assert (base.compiled_profile, base.features, base.camera_present, base.max_width, base.max_height) == (
            profile, features, bar.present, bar.width, bar.height)
        mono = tx.mono_capabilities()
        assert (mono.modes, mono.enables, getattr(mono, "quality_version", 0)) == (bar.modes, enables, expected_version)
        discovered = controls(tx).discover()
        live_schema = discovered["schema2"]
        assert (live_schema["modes"], live_schema["enables"], live_schema.get("quality_version", 0)) == (
            bar.modes, enables, expected_version)
        assert discovered["base"]["features"] == features
        catalog = {row["path"]: row for row in discovered["parameters"]["schemas"]["2"]}
        assert ("extension.hdr_ratio" in catalog) == (profile != 3)
        assert ("extension.isp_wb_enable" in catalog) == bool(expected_version)
        tone = catalog.get("extension.hdr_tone_preset")
        if profile == 3 and tone is not None:
            assert tone.get("minimum") == tone.get("maximum") == 0, "UHD advertised writable HDR tone"
        assert not bar.writes, "discovery wrote the BAR"
        print(f"caps profile={profile} features={features:#04x} modes={bar.modes:#04x} enables={enables:#04x} "
              f"quality_version={expected_version}")
    missing_schema = PublicBar(1, 127, 63, schema_mask=2)
    expect_rejection(owner(missing_schema).mono_capabilities, missing_schema, "schema2 absent", "UNSUPPORTED")


def check_proposal_and_apply(tx, proposal, bar, base, extension):
    expected = wire_words(extension)
    assert proposal.extension_words == expected, (proposal.extension_words, expected)
    assert proposal.configuration == configuration(base)
    assert proposal.extension.words() == expected
    before_epoch = bar.epoch
    before_commands = len(bar.commands)
    bar.expect(base, extension)
    prepared = tx.prepare(proposal.configuration, extension=proposal.extension)
    assert prepared.session == bar.session and prepared.previous_mode_epoch == before_epoch
    assert prepared.request_sequence == bar.sequence and prepared.extension.words() == expected
    applied = tx.commit(prepared)
    assert applied.mode_epoch == bar.epoch == before_epoch + 1
    assert applied.session == bar.session and applied.request_sequence == prepared.request_sequence
    assert applied.camera == 0 and applied.first_actual_frame_sequence == bar.first
    assert applied.configuration == configuration(base) and applied.extension.words() == expected
    assert bar.commands[before_commands:] == [CFG["commands"]["PREPARE_EXT"], CFG["commands"]["COMMIT"]]
    assert controls(tx).read_active().extension_words == expected
    return expected


def check_legacy_on_new(edition):
    bar = PublicBar(2, 127, 15)
    tx = owner(bar)
    baseline = extension_document(2, 10)
    proposal = controls(tx).propose(document(baseline))
    words = check_proposal_and_apply(tx, proposal, bar, CUSTOM_BASE, baseline)
    assert words[1] == words[12] == 0
    if edition == "old":
        return

    quality = baseline | QUALITY_VALUES
    proposal = controls(tx).propose({"extension": QUALITY_VALUES})
    words = check_proposal_and_apply(tx, proposal, bar, CUSTOM_BASE, quality)
    assert words[1] == 0x40000000 | 743 << 20 | 311 << 10 | 997
    assert words[12] == 0x17
    decoded = schema2.MonoConfiguration.from_words(words)
    for key, value in QUALITY_VALUES.items():
        assert getattr(decoded, key) == value
    base_patch = CUSTOM_BASE | {"quality": 79}
    ext_patch = quality | {"isp_wb_b": 523, "hdr_motion_shift": 2}
    proposal = controls(tx).propose({"base": {"quality": 79}, "extension": {"isp_wb_b": 523, "hdr_motion_shift": 2}})
    check_proposal_and_apply(tx, proposal, bar, base_patch, ext_patch)

    for patch in ({"isp_wb_r": True}, {"isp_wb_r": 315.0}, {"isp_wb_r": "315"},
                  {"isp_wb_r": 1024}, {"isp_wb_g": 0}, {"quality_version": 2},
                  {"isp_wb_enable": 0}, {"hdr_fusion_preset": 2}):
        expect_rejection(lambda: controls(tx).propose({"extension": patch}), bar, f"invalid quality {patch}")
    bad_complete = quality | {"isp_wb_r": "315"}
    expect_rejection(lambda: controls(tx).propose(document(bad_complete)), bar, "string in complete quality document")
    expect_rejection(lambda: tx.prepare(configuration(CUSTOM_BASE), extension=extension_object(bad_complete)),
                     bar, "string in direct SDK quality transaction")
    for index, mask in ((1, 1 << 31), (12, 1 << 31), (31, 1)):
        malformed = list(words)
        malformed[index] |= mask
        expect_rejection(lambda: schema2.MonoConfiguration.from_words(malformed), bar, f"reserved W{index}")


def check_new_on_legacy():
    bar = PublicBar(2, 63, 15)
    tx = owner(bar)
    extension = extension_document(2, 10)
    proposal = controls(tx).propose(document(extension))
    check_proposal_and_apply(tx, proposal, bar, CUSTOM_BASE, extension)
    with_quality = extension | QUALITY_VALUES
    expect_rejection(lambda: tx.prepare(configuration(CUSTOM_BASE), extension=extension_object(with_quality)),
                     bar, "new quality request on a featureless BAR", "UNSUPPORTED")


def check_uhd_scope():
    legacy = extension_document(0, 13)
    legacy_bar = PublicBar(3, 63, 13)
    legacy_tx = owner(legacy_bar)
    legacy_proposal = controls(legacy_tx).propose(document(legacy))
    check_proposal_and_apply(legacy_tx, legacy_proposal, legacy_bar, CUSTOM_BASE, legacy)

    extension = legacy | (QUALITY_VALUES | {"hdr_tone_preset": 0, "hdr_fusion_preset": 0})
    bar = PublicBar(3, 127, 13)
    tx = owner(bar)
    proposal = controls(tx).propose(document(extension))
    check_proposal_and_apply(tx, proposal, bar, CUSTOM_BASE, extension)
    for label, unsupported in (("HDR", extension_document(2, 0)), ("dehaze", extension_document(0, 2)),
                               ("lane", extension_document(0, 48))):
        expect_rejection(lambda: tx.prepare(configuration(CUSTOM_BASE), extension=extension_object(unsupported)),
                         bar, f"UHD {label}", "UNSUPPORTED")
    expect_rejection(lambda: controls(tx).propose({"extension": {"hdr_tone_preset": 1}}), bar, "SDR tone")
    raw_bar = PublicBar(3, 127, 13, product=1)
    raw_tx = owner(raw_bar)
    expect_rejection(lambda: raw_tx.prepare(configuration(CUSTOM_BASE), extension=extension_object(extension)),
                     raw_bar, "UHD RAW online CFG", "UNSUPPORTED")


def check_bad_active():
    extension = extension_document(2, 10) | QUALITY_VALUES
    for bad_word in (1, 12):
        bar = PublicBar(2, 127, 15)
        tx = owner(bar)
        bar.expect(CUSTOM_BASE, extension, corrupt_word=bad_word)
        prepared = tx.prepare(configuration(CUSTOM_BASE), extension=extension_object(extension))
        try:
            tx.commit(prepared)
        except transactions.ConfigError as error:
            assert error.code == CFG["error_codes"]["STALE"], (bad_word, error.code, str(error))
        else:
            raise AssertionError(f"altered ACTIVE W{bad_word} accepted")
        assert bar.commands == [CFG["commands"]["PREPARE_EXT"], CFG["commands"]["COMMIT"]], "unexpected retry"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", choices=("new", "old"), required=True)
    parser.add_argument("--sdk-root", type=Path, required=True)
    args = parser.parse_args()
    sdk_root = args.sdk_root.resolve()
    for module in (debug_modes, transactions, schema2):
        loaded = Path(module.__file__).resolve()
        assert loaded.is_relative_to(sdk_root), f"{module.__name__} loaded from {loaded}"
        print(f"import {module.__name__} {loaded}")

    checks = [("capabilities", lambda: check_capabilities(args.sdk)),
              ("legacy_on_new", lambda: check_legacy_on_new(args.sdk))]
    if args.sdk == "new":
        checks.extend([("new_on_legacy", check_new_on_legacy), ("uhd_scope", check_uhd_scope),
                       ("wrong_active", check_bad_active)])
    failed = []
    for name, check in checks:
        try:
            check()
        except Exception:
            failed.append(name)
            print(f"FUSION_SDK_CASE_FAIL edition={args.sdk} case={name}")
            traceback.print_exc()
        else:
            print(f"FUSION_SDK_CASE_PASS edition={args.sdk} case={name}")
    if failed:
        raise SystemExit(1)
    print(f"FUSION_SDK_PASS edition={args.sdk}")


if __name__ == "__main__":
    main()
