"""Independent current-source HDR/SDR image, protocol and complete JPEG oracle.

No old production manifest, LZ seal or bind_candidate.py is consulted. Numerical
references remain the frozen scalar authorities; actual DUT traces are compared
with those references and never become the expected image.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict
import hashlib
import importlib.util
import io
import itertools
import json
from pathlib import Path
import re
import sys
import time

CASE = Path(__file__).resolve().parent
EXTENDED = CASE.parent
HERE = EXTENDED.parent
PROJECT = HERE.parents[1]
ROOT = PROJECT / "verification_reference"
sys.path.insert(0, str(EXTENDED))
from binding import assert_snapshot_binding
sys.path[:0] = [str(EXTENDED / "protocol_reference"), str(ROOT), str(ROOT / "src_fpga/simulation"), str(ROOT / "tools/preprocess_ref")]
from PIL import Image, __version__ as pillow_version
from linux.stream_diag.records import parse_header, parse_record
import jpeg_shared_encoder_reference as jpeg
from preprocess_ref import luma
from shared_wide_isp_reference import GAMMA

WIDTH, HEIGHT = 1920, 1080
GROUPS = WIDTH * HEIGHT // 4
LANE_REFERENCE = EXTENDED / "c1_reference_frozen.py"
QUARTER_Y_EDGES = (0, 67, 135, 202, 270)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def identity(path):
    path = Path(path).resolve()
    return {"path": path.as_posix(), "sha256": sha(path)}


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def need(condition, why):
    if not condition:
        raise AssertionError(why)


def words(path, bits):
    with Path(path).open(encoding="ascii") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            value = int(line, 16)
            need(0 <= value < (1 << bits), f"{Path(path).name}:{line_number}: outside {bits}-bit range")
            yield value


def constant_words(path, bits, value):
    count = 0
    for count, actual in enumerate(words(path, bits), 1):
        need(actual == value, f"{Path(path).name} group{count-1}: {actual:x} != {value:x}")
    need(count == GROUPS, f"{Path(path).name}: {count} groups != {GROUPS}")
    return {"groups": count, "bits": bits, "constant_word": f"{value:x}"}


def snapshot_binding(run, mode, names):
    qpath, sidpath = run / "qualification.json", run / "source_identity.json"
    q, sid = read_json(qpath), read_json(sidpath)
    expected_status = "PASS_HDR_MAIN" if mode == "hdr" else "PASS_SDR_MAIN"
    need(q["status"] == expected_status, f"MAIN status {q['status']} != {expected_status}")
    assert_snapshot_binding(sid)
    need(q.get("owned_warning_count", -1) == 0, "MAIN must explicitly classify owned warnings")
    rows = sid.get("inputs")
    need(isinstance(rows, list) and rows, "source_identity.inputs must be the actual nonempty path/hash list")
    by_path = {}
    for row in rows:
        path = Path(row["path"])
        if not path.is_absolute():
            raise AssertionError(f"Nonabsolute input: {row['path']}")
        path = path.resolve()
        actual = sha(path)
        need(actual == row["sha256"].lower(), f"Changed MAIN input: {path}")
        key = path.as_posix().casefold()
        need(key not in by_path or by_path[key] == actual, f"Conflicting input identities: {path}")
        by_path[key] = actual
    # Bind the new local sources themselves, rather than silently accepting the
    # old same-named production RTL through a historical manifest.
    for basename in ("anlogic2026.v", "full_raw_store.v", "lane_ridge_candidates1_lutram.v",
                     "jpeg_encoder_top.v", "jpeg_frame_ring.v", "product_record_cdc.v"):
        path = PROJECT / "src_fpga/rtl" / basename
        need(path.as_posix().casefold() in by_path, f"New owned source absent from actual compilation identity: {path}")
        need(by_path[path.as_posix().casefold()] == sha(path), f"Stale owned source: {path}")
    boundary = sid.get("boundary_models", q.get("boundary_models"))
    need(bool(boundary), "Electrical/DDR/native-host boundary models must be explicit")
    td_root = sid.get("td_root", q.get("td_root"))
    need(bool(td_root), "Actual TD model root must be explicit")
    need(sid.get("f23_profile") == read_json(HERE / "MAIN_FIXTURE.json")["f23_profile"],
         "MAIN must bind the C1 sparse-v4 profile")
    need(sid.get("f21_profile") == read_json(HERE / "MAIN_FIXTURE.json")["f21_profile"],
         "MAIN must explicitly bind the current automatic fixed-F21 profile")
    for path in (Path(__file__), LANE_REFERENCE):
        need(path.resolve().as_posix().casefold() in by_path, f"Oracle absent from actual MAIN identity: {path}")
    compile_args = (run / "filter_compile.args").read_text(encoding="utf-8")
    need("+define+C15_F23_FULLHEIGHT_PROFILE=0" in compile_args and
         "+define+C15_F23_FULLHEIGHT_PROFILE=1" not in compile_args, "MAIN compiled the wrong F23 profile")
    need("+define+F21_AUTO_FIXED_LUT_PROFILE=0" in compile_args,
         "MAIN did not compile the production automatic fixed-F21 profile")
    body = (run / "run.log").read_text(encoding="utf-8", errors="replace")
    need("RESULT: PASS REFACTOR HDR JPEG MAIN" in body, "MAIN log lacks the new testbench terminal")
    need(not re.search(r"\*\*\s+(?:Error|Fatal):", body), "MAIN log contains Error/Fatal")
    declared = q.get("source_identity_sha256")
    if declared is not None:
        need(declared.lower() == sha(sidpath), "Qualification/source identity hash mismatch")
    snapshots = {name: identity(run / name) for name in (*names, "run.log", "user_events.txt")}
    return {"status": "PASS_CURRENT_SOURCE_IDENTITY", "qualification": identity(qpath),
            "source_identity": identity(sidpath), "input_count": len(by_path),
            "inputs": rows, "boundary_models": boundary, "td_root": str(td_root),
            "outputs": snapshots}, body


def record_pair(run, local_name, actual_name):
    local = (run / local_name).read_bytes()
    actual = (run / actual_name).read_bytes()
    need(actual == local, "Actual C2H wire bytes differ from committed local record")
    record = parse_record(actual, expected_version=4)
    header = parse_header(actual[:2112], expected_version=4)
    need((record.width, record.height, header["quality"]) == (WIDTH, HEIGHT, 75), "Image/header geometry or quality mismatch")
    need(len(actual) == 2112 + len(record.jpeg), "Record has padding/truncation")
    need(record.metadata.jpeg_session != 0 and record.metadata.jpeg_generation != 0,
         "Successful JPEG requires actual session/generation")
    need(record.metadata.write_tag != 0, "Missing actual writer tag")
    return record, header, actual


def check_jpeg(record, pixels, output, flat=None):
    old = jpeg.pixels_for
    jpeg.pixels_for = lambda width, height, pattern: iter(pixels)
    row = {"case": 0, "width": WIDTH, "height": HEIGHT, "quality": 75,
           "restart": 0, "pattern": "independent_current_source_main"}
    try:
        jpeg.generate_frame(output, row)
    finally:
        jpeg.pixels_for = old
    expected_path = output / "case0.expected.jpg"
    expected = expected_path.read_bytes()
    if record.jpeg != expected:
        offset = next((i for i, (actual, golden) in enumerate(zip(record.jpeg, expected)) if actual != golden),
                      min(len(record.jpeg), len(expected)))
        raise AssertionError(f"Independent JPEG mismatch at byte{offset}: actual{len(record.jpeg)} expected{len(expected)}")
    (output / "actual.jpg").write_bytes(record.jpeg)
    with Image.open(io.BytesIO(record.jpeg)) as image:
        image.load()
        need(image.size == (WIDTH, HEIGHT), "Complete JPEG decode geometry")
        decoded = image.convert("RGB")
        if flat is not None:
            histogram = decoded.histogram()
            maximum = max(abs(value-flat[channel]) for channel in range(3) for value in range(256)
                          if histogram[channel*256+value])
            need(maximum == 0, f"Flat-field decoded RGB error: {maximum}")
            error = {"max_error": maximum, "mae": 0.0}
        else:
            absolute = maximum = 0
            for actual, golden in zip(decoded.getdata(), pixels):
                difference = tuple(abs(a-b) for a, b in zip(actual, golden))
                absolute += sum(difference)
                maximum = max(maximum, *difference)
            error = {"max_error": maximum, "mae": absolute / (WIDTH*HEIGHT*3)}
    return {"status": "PASS", "exact_bytes": len(expected), "jpeg_sha256": sha(expected_path),
            "complete_decode": "Pillow/libjpeg PASS", "decoded_rgb_error": error,
            "pillow_version": pillow_version, "sampling": "4:2:2", "quality": 75, "restart": 0}


def check_neutral(record, pixels):
    samples = [luma(pixels[y*WIDTH+x]) for y in range(3, HEIGHT, 6) for x in range(3, WIDTH, 6)]
    expected = {"sampled": 57600, "delivered": 57600, "sum_y": sum(samples),
                "dark": sum(value < 32 for value in samples), "bright": sum(value >= 224 for value in samples),
                "min_y": min(samples), "max_y": max(samples), "dark_threshold": 32,
                "bright_threshold": 224, "width": 320, "height": 180}
    need(asdict(record.metadata.neutral_stats) == expected, "Pre-F21 neutral statistics differ from independent image")
    return {"status": "PASS", "expected": expected}


def hdr_checks(run, output, log, hdr_startup_recovery=False):
    plan = read_json(EXTENDED / 'HDR_INPUT_PLAN.json')
    retained = plan['warmup_retained_sequences'] + [plan['first_product_sequence']]
    ledger = [json.loads(line) for line in (run / 'hdr_input_ledger.jsonl').read_text().splitlines() if line]
    expected_ledger = [dict(sequence=n, disposition='overlap_skip' if n in plan['overlap_skipped_sequences'] else 'retained',
                            long_frame_number=n+plan['long_frame_number_offset'],
                            short_frame_number=n+plan['short_frame_number_offset']) for n in range(1, 11)]
    need(ledger == expected_ledger, 'Complete independent input ledger including the skipped full overlap group')
    need(retained == [1,3,4,5,6,7,8,9,10], 'Frozen eight-good and first-product input plan')
    warmup = re.findall(r'HDR_STARTUP_RECOVERY WARMUP pair=(\d+) sequence=(\d+)/(\d+) stable=(\d+)', log)
    need([tuple(map(int,row)) for row in warmup] == [(n,n+1,n+1,int(n==8)) for n in range(1,9)],
         'Eight retained good warmups and exact independently planned physical sequence progression')
    need(log.count('HDR_STARTUP_OVERLAP INPUT_DONE retained_sequence=1 skipped_sequence=2') == 1,
         'One complete real overlapping group is consumed')
    record, header, data = record_pair(run, "local_record.bin", "actual_record.bin")
    count = GROUPS
    raw = {"long": constant_words(run / "capture_long.hex", 40, sum(306 << (10*k) for k in range(4))),
           "short": constant_words(run / "capture_short.hex", 40, sum(66 << (10*k) for k in range(4))),
           "merged": constant_words(run / "hdr_raw14.hex", 56, sum(256 << (14*k) for k in range(4)))}
    print("NUMERIC HDR RAW10/RAW14 PASS", flush=True)
    tone_path = ROOT / "src_fpga/stages/r8_stage3/pending/hdr_pairbank_20261014/numerical/tone96_reference.py"
    tone = load("isolated_hdr_tone_scalar", tone_path)
    rgb = tuple(GAMMA[value] for value in tone.tone_rgb((256, 256, 256)))
    packed = sum(((rgb[0] << 16) | (rgb[1] << 8) | rgb[2]) << (24*k) for k in range(4))
    isp = constant_words(run / "hdr_rgb888.hex", 96, packed)
    print("NUMERIC HDR T96/ISP PASS", flush=True)
    protocol_path = ROOT / "docs/pcie_protocol_v1.json"
    proto = read_json(protocol_path)
    recipe_path = ROOT / "src_fpga/stages/r8_stage3/pending/real_hdr_20261018/frontend/backend_recipe.json"
    recipe = read_json(recipe_path)
    fields = {}
    for row in proto["record_v2"]["header_extension"]["fields"]:
        value = data[row["offset"]:row["offset"]+row["size"]]
        need(len(value) == row["size"], f"Truncated JSON field: {row['name']}")
        fields[row["name"]] = value if row["type"] == "bytes" else int.from_bytes(value, "little")
    physical = proto["record_v2"]["source_kinds"]["PHYSICAL"]
    need(physical == recipe["source_kind_encoding"]["value"], "Protocol/recipe physical encoding mismatch")
    expected = {"source_camera": 0, "source_kind": physical,
                "source_format": proto["record_v2"]["source_formats"]["RAW10"],
                "exposure_role": proto["record_v2"]["exposure_roles"]["LONG"],
                "source_sequence": 10 if hdr_startup_recovery else 2, "actual_exposure": recipe["long_exposure_ticks"],
                "actual_gain": recipe["backend_gain_both"], "calibration_id": int(sha(recipe_path)[:8], 16),
                "exposure_group": 10 if hdr_startup_recovery else 2}
    for name, value in expected.items():
        need(fields[name] == value, f"HDR JSON field {name}: {fields[name]} != {value}")
    for name in ("source_session", "source_epoch", "jpeg_session", "jpeg_generation", "pair_id", "job_id", "write_tag"):
        need(fields[name] != 0, f"Missing HDR {name}")
    for flag in ("SOURCE_IDENTITY", "EXPOSURE", "GAIN", "CALIBRATION", "PAIR", "JOB", "QUALIFIED", "HDR_PRODUCT"):
        need(fields["validity_flags"] & (1 << proto["record_v2"]["validity_flags"][flag]), f"Missing HDR valid flag {flag}")
    need(fields["record_flags"] & (1 << proto["record_v2"]["record_flags"]["HDR_MERGED"]), "Missing HDR_MERGED flag")
    need(record.s07.enabled == 0 and record.s07.f22 is None and record.s07.f23 is None,
         "HDR fixture should not claim enabled sparse algorithms")
    neutral = check_neutral(record, list(itertools.repeat(rgb, WIDTH*HEIGHT)))
    events = (run / "user_events.txt").read_text()
    members = re.findall(r'^HDR_MEMBER role=(LONG|SHORT) session=(\d+) epoch=(\d+) sequence=(\d+)$', events, re.M)
    need(len(members)==2 and {member[0] for member in members}=={'LONG','SHORT'}, 'Both actual pre-DDR member identities observed once')
    for role, session, epoch, sequence in members:
        need((int(session),int(epoch),int(sequence)) ==
             (fields['source_session'],fields['source_epoch'],plan['first_product_sequence']),
             role+' member SOURCE must remain the frozen primary product identity through DDR/JPEG/record')
    finishes = re.findall(r'^HDR_MEMBER_FINISH role=(LONG|SHORT) session=(\d+) epoch=(\d+) sequence=10 group=10 ok=1$', events, re.M)
    need(len(finishes)==2 and {row[0] for row in finishes}=={'LONG','SHORT'}, 'Both actual successful DDR writer completions observed exactly once')
    for role, session, epoch in finishes:
        need((int(session),int(epoch))==(fields['source_session'],fields['source_epoch']),role+' DDR completion identity matches frozen pre-DDR SOURCE')
    need('HDR_COMMIT_CONTRACT PASS member_finish=1/1 legacy_long_commit=1 pair_acquire=1' in log,'Exact legacy-LONG observation and dual-member finish contract')
    starts = re.findall(r"^START case=1 phase=8 session=(\d+) sequence=(\d+)$", events, re.M)
    writers = re.findall(r"^WRITER case=1 phase=8 ok=1 error=0 slot=(\d+) gen=(\d+) session=(\d+) seq=(\d+) B=(\d+)/(\d+)$", events, re.M)
    need(len(starts) == len(writers) == 1, "HDR source/writer event count mismatch")
    start, writer = tuple(map(int, starts[0])), tuple(map(int, writers[0]))
    need(writer[4] == writer[5], "HDR writer has uncompleted AXI B responses")
    need(start == (fields["jpeg_session"], record.sequence), "START/record identity mismatch")
    need(writer[:4] == (header["slot_id"], fields["jpeg_generation"], fields["jpeg_session"], record.sequence),
         "WRITER/record slot/generation/session/sequence mismatch")
    steps = re.findall(r"REAL_HDR_STAGE (CFG_READ|CFG_READ_DONE|USER_LAST|SAFE|ACK|PAIR_RELEASE|QUIET) time=(\d+)", log)
    need([name for name, _ in steps] == ["CFG_READ", "CFG_READ_DONE", "USER_LAST", "SAFE", "ACK", "PAIR_RELEASE", "QUIET"], "HDR lifecycle stages missing/reordered")
    need(all(int(steps[i][1]) <= int(steps[i+1][1]) for i in range(len(steps)-1)), "HDR lifecycle time order")
    need("REAL_HDR_SDR_RETURN_CANCEL PASS starts=2 sourceBad=1 writerBad=1 applies=2 records=1" in log,
         "Actual SDR return and late CRC negative recovery were not completed")
    need(log.count("HDR_STARTUP_RECOVERY WARMUP pair=")==8 and "HDR_STARTUP_RECOVERY NOISE_REJECTED bad_headers=3" in log,"eight real warmup pairs after malformed lane startup")
    jpeg_result = check_jpeg(record, itertools.repeat(rgb, WIDTH*HEIGHT), output, flat=rgb)
    return {"raw": {"status": "PASS", **raw}, "isp_t96": {"status": "PASS", **isp, "rgb": rgb},
            "metadata": {"status": "PASS", "fields": expected}, "neutral": neutral, "jpeg": jpeg_result,
            "lifecycle": {"status": "PASS", "ordered_stages": steps, "writer": writer,
                          "input_ledger":ledger,"member_identities":members,
                          "SDR_return_bad_CRC": "PASS"}}, [tone_path, protocol_path, recipe_path, EXTENDED/'HDR_INPUT_PLAN.json']


def sdr_isp():
    """Known CSI RAW10 ramp; independent BLC50/reflect101 RGGB bilinear/color."""
    def at(x, y):
        x = -x if x < 0 else 2*WIDTH-2-x if x >= WIDTH else x
        y = -y if y < 0 else 2*HEIGHT-2-y if y >= HEIGHT else y
        value = 100 + ((x//16*3 + y//8*5) % 600)
        value += 180 if not (x % 2 or y % 2) else 20 if x % 2 and y % 2 else 90
        return max(0, value-50)
    result = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            centre = at(x, y)
            cross = (at(x-1,y)+at(x+1,y)+at(x,y-1)+at(x,y+1)+2)//4
            diag = (at(x-1,y-1)+at(x+1,y-1)+at(x-1,y+1)+at(x+1,y+1)+2)//4
            horizontal = (at(x-1,y)+at(x+1,y)+1)//2
            vertical = (at(x,y-1)+at(x,y+1)+1)//2
            rgb = ((centre,cross,diag), (horizontal,centre,vertical),
                   (vertical,centre,horizontal), (diag,cross,centre))[(y % 2)*2+x % 2]
            result.append(tuple(GAMMA[value] for value in rgb))
    return result


def pixels_equal(path, image, ys=None):
    stream = words(path, 128 if ys is not None else 96)
    for group in range(GROUPS):
        start = group*4
        expected = sum(((r << 16) | (g << 8) | b) << (24*lane)
                       for lane, (r,g,b) in enumerate(image[start:start+4]))
        if ys is not None:
            expected |= sum(ys[start+k] << (96+8*k) for k in range(4))
        actual = next(stream)
        need(actual == expected, f"{Path(path).name} group{group}: {actual:x} != {expected:x}")
    need(next(stream, None) is None, f"Extra groups in {Path(path).name}")
    return {"status": "PASS", "pixels": WIDTH*HEIGHT, "groups": GROUPS}


def sdr_checks(run, output, mask, *, require_refactor_markers=True, runtime_recovery=False, crc_recovery=False):
    record, header, data = record_pair(run, "local_record_0.bin", "actual_record_0.bin")
    m = record.metadata
    need(asdict(m.source) == {"session": 1, "epoch": 1, "sequence": 3 if crc_recovery else 5 if runtime_recovery else 1, "camera": 0,
                             "kind": 1, "format": 1, "role": 0}, "SDR physical SOURCE identity")
    need(not m.qualified and m.actual_exposure is None and m.actual_gain is None and m.calibration_id is None,
         "SDR unknown optical metadata must stay unknown")
    need(m.pair_id is None and m.processing_member == 0 and m.record_flags == 0, "SDR must not claim HDR pair/product")
    need(m.processing_mode == 128 | mask and m.schema2_processing_enables == mask, "SDR processing mask")
    need(record.s07.enabled == (3 if mask & 32 else 1) and not record.s07.frame_error, "Sparse enabled/error flags")
    need(record.s07.f22.ok and record.s07.f24 is None and record.s07.f25 is None, "F22 result or absent feature semantics")
    need((record.s07.f23 is not None) == bool(mask & 32), "F23 presence must match enable")
    golden = sdr_isp()
    ys = tuple(map(luma, golden))
    checks = {"metadata": {"status": "PASS", "source": asdict(m.source), "processing_mode": m.processing_mode},
              "isp": pixels_equal(run / "sdr_isp_0.hex", golden),
              "processed": pixels_equal(run / "sdr_processed_0.hex", golden, ys),
              "neutral": check_neutral(record, golden)}
    print("NUMERIC SDR ISP/processed/neutral PASS", flush=True)
    pyramid_path = ROOT / "src_fpga/stages/r8_stage2/simulation/preprocess_multiscale_reference.py"
    pyramid = load("isolated_main_scalar_pyramid", pyramid_path)
    levels = pyramid.pyramid_reference(pyramid.Plane(WIDTH, HEIGHT, ys))
    expected = pyramid.pack_record(levels, 40, record.s07.context)
    need(list(words(run / "sdr_f22_0.hex", 684)) == [expected], "All684 F22 terminal bits differ")
    need(record.s07.f22.original_record == expected, "F22 wire/independent terminal mismatch")
    lane_path = LANE_REFERENCE
    lanes = list(words(run / "sdr_f23_0.hex", 177))
    if mask & 32:
        import numpy as np
        lane = load("extended_frozen_c1",lane_path)
        bgr=np.asarray(golden,dtype=np.uint8).reshape(HEIGHT,WIDTH,3)[:,:,::-1].copy()
        points=lane.extract(bgr)
        expected_lane=(record.s07.context<<17)|(len(points)<<8)
        need(lanes==[expected_lane],"C1 177bit context/count/status terminal mismatch")
        wire=record.s07.f23
        need(wire.count==len(points)and wire.status==0,"C1 wire count/status")
        for actual,expected in zip(wire.points,points):
            need((actual.native_x,actual.native_y,actual.strength,actual.width_quarter,actual.marking_class)==
                tuple(expected[k]for k in ('native_x','native_y','strength','width_quarter','marking_class')),
                "C1 independently selected point differs from v4 wire")
        need((wire.roi_begin,wire.roi_end)==(169,269),"C1 exact road ROI")
    else:
        need(not lanes,"Disabled C1 emitted terminal")
    checks["analysis"]={"status":"PASS","F22":"all684bits","F23":"all177bit descriptor and every v4 point",
        "point_count":len(points)if mask&32 else 0,"reference":"frozen14df independent C1 integer model"}
    print("NUMERIC SDR F22/C1/v4 PASS",flush=True)
    checks["jpeg"] = check_jpeg(record, golden, output)
    events = (run / "user_events.txt").read_text()
    writers = re.findall(r"^WRITER case=1 phase=30 ok=1 error=0 slot=(\d+) gen=(\d+) session=(\d+) seq=(\d+) B=(\d+)/(\d+)$", events, re.M)
    need(len(writers) == 1, "SDR successful writer count")
    writer = tuple(map(int, writers[0]))
    need(writer[:4] == (header["slot_id"], m.jpeg_generation, m.jpeg_session, record.sequence), "SDR writer/record identity")
    need(writer[4] == writer[5], "SDR writer AXI B debt")
    checks["writer"] = {"status": "PASS", "identity_and_aw_b": writer}
    if require_refactor_markers:
        log = (run / "run.log").read_text(encoding="utf-8", errors="replace")
        need("SDR_JPEG_MAIN PASS" in log and f"F22=1 F23={1 if mask & 32 else 0} native_retire=1" in log,
             "Actual full SDR F22/F23/native retirement marker missing")
        need("REMOVED_LZ_REJECT PASS" in log, "Removed LZ configuration rejection not completed")
        need(re.search(r"C2_STOP_MAIN PASS [^\n]*after_products=1(?:\s|$)", log), "C2H STOP/drain/retire regression not completed")
        checks["lifecycle"] = {"status": "PASS", "native_retire": 1,
                               "removed_LZ_reject": "PASS", "C2H_STOP_after_product": "PASS"}
        if crc_recovery:
            need("CRC_RECOVERY_MAIN PASS short=0 failures=2 ignored=0 recovered_sequence=3" in log,
                 "Full admitted CRC-owner runtime recovery marker missing")
            checks["crc_recovery"] = {"status": "PASS", "failed_sources": [1, 2],
                                      "ignored_boundaries": [], "recovered_source": 3,
                                      "receive_faults": 0}
        elif runtime_recovery:
            need("RUNTIME_RECOVERY_MAIN PASS short=0 failures=2 ignored=2 recovered_sequence=5" in log,
                 "Full admitted-owner runtime recovery marker missing")
            checks["runtime_recovery"] = {"status": "PASS", "failed_sources": [1, 3],
                                           "ignored_boundaries": [2, 4], "recovered_source": 5}
    return checks, [pyramid_path, lane_path]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mode", choices=("hdr", "sdr"), required=True)
    ap.add_argument("--run-directory", type=Path, required=True)
    ap.add_argument("--output-directory", type=Path, required=True)
    ap.add_argument("--sdr-mask", type=int, choices=(16, 48), default=48)
    ap.add_argument("--runtime-recovery", action="store_true")
    ap.add_argument("--crc-recovery", action="store_true")
    args = ap.parse_args()
    if (args.runtime_recovery or args.crc_recovery) and args.mode != "sdr":
        ap.error("--runtime-recovery is SDR only")
    if args.runtime_recovery and args.crc_recovery:
        ap.error("choose one runtime recovery stimulus")
    run, output = args.run_directory.resolve(), args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    result = {"status": "RUNNING", "mode": args.mode, "command": sys.argv,
              "python": sys.executable, "run_directory": str(run), "checks": {},
              "scope": "One complete same-input fixture; electrical/host boundary models explicit; no sustained-rate/board claim",
              "synthesis": "NOT_RUN", "physical": "NOT_RUN", "final_STA": "NOT_RUN", "bitgen": "NOT_RUN", "board": "NOT_RUN",
              "sustained_HDR30_SDR60": "NOT_RUN", "F21_nonidentity_history": "Separate focused image-leaf qualification"}
    names = ("capture_long.hex", "capture_short.hex", "hdr_raw14.hex", "hdr_rgb888.hex", "local_record.bin", "actual_record.bin", "hdr_input_ledger.jsonl") if args.mode == "hdr" else (
        "sdr_isp_0.hex", "sdr_processed_0.hex", "sdr_f22_0.hex", "sdr_f23_0.hex", "local_record_0.bin", "actual_record_0.bin")
    references = [Path(__file__), ROOT / "linux/stream_diag/records.py",
        *[ROOT / "linux/task3_pipeline" / name for name in ("pcie_protocol_v1.py", "record_selection.py", "record_v2.py", "record_v3.py")],
        ROOT / "src_fpga/simulation/jpeg_shared_encoder_reference.py", ROOT / "src_fpga/simulation/shared_wide_isp_reference.py",
        ROOT / "src_fpga/rtl/isp/color/gamma22_10to8.dath", ROOT / "tools/preprocess_ref/preprocess_ref.py",
        ROOT / "tools/jpeg_ref/jpeg_ref.py", ROOT / "tools/jpeg_ref/table_data.json", ROOT / "src_fpga/rtl/jpeg/quant_data/q50_base.json"]
    if args.mode == "hdr":
        references += [ROOT / "docs/pcie_protocol_v1.json",
            ROOT / "src_fpga/stages/r8_stage3/pending/real_hdr_20261018/frontend/backend_recipe.json",
            ROOT / "src_fpga/stages/r8_stage3/pending/hdr_pairbank_20261014/numerical/tone96_reference.py",
            ROOT / "src_fpga/stages/r8_stage3/hdr_pair_source/frozen/tone_reference.py",
            ROOT / "src_fpga/stages/r8_stage3/hdr_pair_source/sources.json",
            ROOT / "guidance/Anlogic_R8_FPGA/tools/generate_coefficients.py"]
    else:
        references += [ROOT / "src_fpga/stages/r8_stage2/simulation/preprocess_multiscale_reference.py",
                       LANE_REFERENCE]
    references += list((EXTENDED/"protocol_reference").rglob("*.py"))
    try:
        # Snapshot numerical authorities before any computation, then verify
        # them again before a PASS; those files are independent of MAIN inputs.
        authority_hashes = {str(path): sha(path) for path in references}
        binding, log = snapshot_binding(run, args.mode, names)
        declared_runtime = read_json(run / "qualification.json").get("runtime_recovery")
        need(declared_runtime == ("crc-full" if args.crc_recovery else "full" if args.runtime_recovery else None),
             "Oracle runtime-recovery option must match the executed full MAIN fixture")
        result["source_binding"] = binding
        (output / "SOURCE_BINDING.json").write_text(json.dumps(binding, indent=2)+"\n")
        print("CURRENT_SOURCE_BINDING PASS", flush=True)
        checks, extra = hdr_checks(run, output, log, hdr_startup_recovery=True) if args.mode == "hdr" else sdr_checks(run, output, args.sdr_mask, runtime_recovery=args.runtime_recovery, crc_recovery=args.crc_recovery)
        result["checks"] = checks
        references = list(dict.fromkeys(references + extra))
        result["oracle_sources"] = [identity(path) for path in references]
        for path, digest in authority_hashes.items():
            need(sha(path) == digest, f"Numerical authority changed during oracle: {path}")
        final_binding, _ = snapshot_binding(run, args.mode, names)
        need(final_binding == binding, "MAIN source/trace identities changed during independent check")
        result["status"] = "PASS"
        print(f"RESULT: PASS independent current-source {args.mode.upper()} RAW/ISP/analysis/protocol/exact JPEG/complete decode", flush=True)
    except Exception as exc:
        result["status"] = "FAIL"
        result["error"] = str(exc)
        print(f"RESULT: FAIL {exc}", flush=True)
    finally:
        result["elapsed_seconds"] = round(time.monotonic()-started, 3)
        result["outputs"] = [identity(path) for path in sorted(output.iterdir()) if path.is_file()]
        (output / "RESULTS.json").write_text(json.dumps(result, indent=2)+"\n")
    return result["status"] != "PASS"


if __name__ == "__main__":
    raise SystemExit(main())
