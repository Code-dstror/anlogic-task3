"""Create and score independent JPEG entropy and encoder fixtures."""

import argparse
import hashlib
import io
import json
import random
import sys
from collections import Counter
from functools import lru_cache
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(ROOT / "tools/jpeg_ref"))
import jpeg_ref as ref


class Scan:
    def __init__(self, interval):
        self.interval = interval
        self.predictors = [0, 0, 0]
        self.output = bytearray()
        self.pending = 0
        self.bit_count = 0
        self.stuffed = 0
        self.restarts = []
        self.dc_diffs = set()
        self.ac_sizes = set()
        self.symbol_phases = set()
        self.zrl = 0

    def bits(self, value, size):
        assert 0 <= value < (1 << size)
        self.pending = (self.pending << size) | value
        self.bit_count += size
        while self.bit_count >= 8:
            self.bit_count -= 8
            value = self.pending >> self.bit_count
            self.pending &= (1 << self.bit_count) - 1
            self.output.append(value)
            if value == 0xFF:
                self.output.append(0)
                self.stuffed += 1

    def symbol(self, table, value):
        self.symbol_phases.add(self.bit_count)
        code, size = ref.CODES[table][value]
        self.bits(code, size)

    def block(self, component, coeffs):
        suffix = "y" if component == 0 else "c"
        diff = coeffs[0] - self.predictors[component]
        self.predictors[component] = coeffs[0]
        self.dc_diffs.add(diff)
        size = abs(diff).bit_length()
        self.symbol("dc_" + suffix, size)
        self.bits(ref.amplitude(diff, size), size)
        zeros = 0
        for coeff in coeffs[1:]:
            if coeff == 0:
                zeros += 1
                continue
            while zeros >= 16:
                self.symbol("ac_" + suffix, 0xF0)
                self.zrl += 1
                zeros -= 16
            size = abs(coeff).bit_length()
            self.ac_sizes.add(size)
            self.symbol("ac_" + suffix, (zeros << 4) | size)
            self.bits(ref.amplitude(coeff, size), size)
            zeros = 0
        if zeros:
            self.symbol("ac_" + suffix, 0)

    def pad(self):
        pad_size = (-self.bit_count) % 8
        self.bits((1 << pad_size) - 1, pad_size)

    def mcu_end(self, completed, total):
        if self.interval and completed % self.interval == 0 and completed < total:
            self.pad()
            code = 0xD0 + len(self.restarts) % 8
            self.restarts.append((len(self.output), code))
            self.output.extend((0xFF, code))
            self.predictors = [0, 0, 0]

    def evidence(self):
        return {
            "length": len(self.output),
            "sha256": sha256(self.output),
            "stuffed_ff": self.stuffed,
            "restarts": self.restarts,
            "dc_diff_extrema": [min(self.dc_diffs), max(self.dc_diffs)],
            "ac_sizes": sorted(self.ac_sizes),
            "symbol_phases": sorted(self.symbol_phases),
            "zrl_count": self.zrl,
            "last_bytes": self.output[-8:].hex(),
        }


def sha256(data):
    return hashlib.sha256(data).hexdigest()


COMPONENT = (0, 0, 1, 2)
ZERO_AC = (0,) * 63


def dense(dc, seed):
    rng = random.Random(seed)
    sizes = (1023, 1023, 1, 2, 3, 7, 17, 35, 89, 150, 271, 710, 0)
    return (dc, 1023, -1023, *(rng.choice(sizes) * rng.choice((-1, 1)) for _ in range(61)))


def sparse(dc, values):
    block = [dc, *ZERO_AC]
    for position, value in values:
        block[position] = value
    return tuple(block)


def scan_blocks(blocks, restart, close=True):
    scan = Scan(restart)
    for n, block in enumerate(blocks):
        scan.block(COMPONENT[n % 4], block)
        if n % 4 == 3:
            scan.mcu_end(n // 4 + 1, len(blocks) // 4)
    if close:
        scan.pad()
    return scan


def stuffed_tail_blocks():
    # Select an independently computed frame whose scan tail is a stuffing byte.
    for value in range(-127, 128):
        blocks = [sparse(value, ()), sparse(-value, ()), sparse(16, ()),
                  sparse(0, ((63, 1023),))]
        scan = scan_blocks(blocks, 0)
        if scan.output.endswith(b"\xff\x00"):
            return blocks
    raise AssertionError("could not construct a stuffed final byte")


def pack_header(capture, session, epoch, camera, quality, x, y, block, last):
    return (capture | (epoch << 32) | (session << 64) | (x << 96) | (y << 105)
            | (COMPONENT[block] << 114) | (block << 116) | (last << 118)
            | (quality << 119) | (camera << 126) | (1 << 129))


def write_entropy(run):
    extrema = []
    for mcu in range(21):
        y0 = 2047 if mcu % 2 == 0 else -2047
        chroma = 2047 if (mcu // 2) % 2 == 0 else -2047
        extrema.extend((
            dense(y0, 58000 + mcu),
            sparse(0, ((17, -1023), (50, 1023))),
            sparse(-chroma, ((49, -1023),)),
            dense(chroma, 59000 + mcu) if mcu % 3 == 0 else sparse(chroma, ()),
        ))
    stuffed = stuffed_tail_blocks()
    recovery = [sparse(dc, ((3, ac),)) for dc, ac in ((12, 5), (-19, -8), (7, 1), (-1, -3))]
    prefix = [dense(5, 621), sparse(1, ()), sparse(6, ()), sparse(-5, ())]
    frames = [
        ("extrema", "ok", extrema, 2),
        ("dc_pos_invalid", "dc", [dense(-1024, 39), sparse(1024, ())], 0),
        ("recover_pos", "ok", stuffed, 0),
        ("dc_neg_invalid", "dc", [dense(1024, 43), sparse(-1024, ())], 0),
        ("recover_neg", "ok", recovery, 0),
        ("identity_invalid", "identity", prefix, 0),
        ("recover_identity", "ok", stuffed, 0),
        ("cancel", "abort", [dense(18, 7004)], 0),
        ("recover_cancel", "ok", recovery, 0),
        ("reset", "reset", [dense(-35, 7309)], 0),
        ("recover_reset", "ok", stuffed, 0),
    ]
    metadata = []
    with (run / "entropy.config").open("w", encoding="ascii", newline="\n") as config:
        for n, (name, kind, blocks, restart) in enumerate(frames):
            capture = 0x80010020 + n
            epoch = 0x10203040 + 5 * n
            session = 0x60901001 if n < 10 else 0x70901001
            tokens = []
            for i, coeffs in enumerate(blocks):
                block = i % 4
                mcu = i // 4
                last = kind == "ok" and i == len(blocks) - 1
                tokens.append(pack_header(capture, session, epoch, n % 2, 75,
                                          mcu % 7, mcu // 7, block, last))
                for batch in range(8):
                    beat = sum((coeffs[8 * batch + lane] & 0xFFFF) << (16 * lane)
                               for lane in range(8))
                    tokens.append(beat | ((batch == 7) << 128))
            if kind == "identity":
                tokens.append(pack_header(capture ^ 0x10, session, epoch, n % 2, 75, 1, 0, 0, False))

            good = kind == "ok"
            valid_blocks = blocks[:-1] if kind == "dc" else blocks
            scan = scan_blocks(valid_blocks, restart, close=good)
            if name == "extrema":
                assert {-2047, 2047} <= scan.dc_diffs
                assert 10 in scan.ac_sizes and scan.zrl and scan.stuffed
                assert scan.symbol_phases == set(range(8))
                assert [code for _, code in scan.restarts] == [0xD0 + i % 8 for i in range(10)]
            if good:
                (run / f"entropy_{n}.scan").write_bytes(scan.output)

            # Stall at the first octet, at the first restart code (if present), and at LAST.
            # In cancel/reset cases hold the fourth offer while asserting the control.
            restart_code = scan.restarts[0][0] + 1 if scan.restarts else -1
            last = len(scan.output) - 1 if good else -1
            control = {"ok": 0, "dc": 2, "identity": 4, "abort": 8, "reset": 9}[kind]
            config.write(f"{capture:08x} {restart} {len(tokens)} {control} {restart_code} {last}\n")
            (run / f"entropy_{n}.tokens").write_text(
                "".join(f"{token:033x}\n" for token in tokens), encoding="ascii", newline="\n")
            metadata.append({
                "index": n, "name": name, "kind": kind, "capture": capture,
                "epoch": epoch, "session": session, "camera": n % 2, "quality": 75,
                "token_count": len(tokens), "restart_interval": restart,
                "reference": scan.evidence(), "expected_error_code": control if control in (2, 4) else 0,
            })
    return metadata


@lru_cache(maxsize=128)
def quantized(tile, component):
    dct = ref.dct_q14([sample - 128 for sample in tile])
    natural = ref.quant_q75(dct, "Y" if component == 0 else "C")
    return tuple(natural[i] for i in ref.ZIGZAG)


def texture_tiles(seed):
    rng = random.Random(seed)
    return [tuple(rng.randrange(256) for _ in range(64)) for _ in range(32)]


def tile_for(frame, bx, by, bank):
    if frame == 0:
        return (46,) * 64
    if frame == 3:
        return tuple(22 + (11 * bx + 59 * by + 13 * (p % 8)) % 206 for p in range(64))
    return bank[(17 * bx + 7 * by + (bx // 19)) % len(bank)]


def encoder_fixture(n, width, height, restart, seed):
    bank = texture_tiles(seed)
    scan = Scan(restart)
    y_plane = bytearray(width * height)
    tile_grid = [[tile_for(n, x, y, bank) for x in range(width // 8)]
                 for y in range(height // 8)]
    neutral = quantized((128,) * 64, 1)
    for my, row in enumerate(tile_grid):
        for mx in range(width // 16):
            for i in (0, 1):
                tile = row[2 * mx + i]
                scan.block(0, quantized(tile, 0))
                for r in range(8):
                    pos = (8 * my + r) * width + 16 * mx + 8 * i
                    y_plane[pos:pos + 8] = tile[8 * r:8 * r + 8]
            scan.block(1, neutral)
            scan.block(2, neutral)
            scan.mcu_end(my * (width // 16) + mx + 1, (width // 16) * (height // 8))
    scan.pad()
    headers = ref.headers(width, height)
    if restart:
        sos = headers.index(b"\xff\xda")
        headers = headers[:sos] + ref.marker(0xDD, restart.to_bytes(2, "big")) + headers[sos:]
    return y_plane, headers + bytes(scan.output) + b"\xff\xd9", scan.evidence()


def write_encoder(run):
    frames = [
        ("low_flat_status_after_tail", 1920, 16, 0, 0, True),
        ("high_texture_status_before_tail", 3840, 32, 17, 18218026, True),
        ("low_source_reject", 1920, 16, 5, 31895012, False),
        ("low_ramp_recovery", 1920, 16, 0, 0, True),
    ]
    metadata = []
    with (run / "encoder.config").open("w", encoding="ascii", newline="\n") as config:
        for n, (name, width, height, restart, seed, good) in enumerate(frames):
            capture = 0xA00E0011 + 3 * n
            epoch = 0x10032100 + 17 * n
            session = 0x701BC23A + 5 * n
            y_plane, jpeg, scan = encoder_fixture(n, width, height, restart, seed)
            config.write(f"{capture:08x} {epoch:08x} {session:08x} {n % 2} "
                         f"{width} {height} {restart} {int(good)}\n")
            with (run / f"encoder_{n}.pixels").open("w", encoding="ascii", newline="\n") as out:
                for p in range(0, len(y_plane), 4):
                    group = y_plane[p:p + 4]
                    out.write(group[::-1].hex() + b"".join(bytes((y, y, y)) for y in reversed(group)).hex() + "\n")
            if good:
                (run / f"encoder_{n}.expected.jpg").write_bytes(jpeg)
                (run / f"encoder_{n}.y").write_bytes(y_plane)
            metadata.append({
                "index": n, "name": name, "capture": capture, "epoch": epoch,
                "session": session, "camera": n % 2, "quality": 75,
                "width": width, "height": height, "restart_interval": restart,
                "seed": seed, "good": good, "reference_scan": scan,
                "golden_jpeg_length": len(jpeg), "golden_jpeg_sha256": sha256(jpeg),
            })
    return metadata


def generate(run):
    manifest = {"entropy": write_entropy(run), "encoder": write_encoder(run)}
    manifest["inputs_sha256"] = {
        item.name: sha256(item.read_bytes())
        for item in sorted(run.iterdir())
        if item.suffix in (".config", ".scan", ".tokens", ".pixels", ".jpg", ".y")
    }
    write_json(run / "fixtures.json", manifest)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8", newline="\n")


def traces(path):
    result = {}
    for line in path.read_text(encoding="ascii").splitlines():
        event, n, *args = line.split()
        result.setdefault(int(n), {}).setdefault(event, []).append(args)
    return result


def frame_header(data):
    """Return SOF, restart interval, and raw scan independently of JPEG decoder."""
    assert data[:2] == b"\xff\xd8" and data[-2:] == b"\xff\xd9", "SOI/EOI"
    sof = None
    restart = 0
    segments = []
    p = 2
    while p < len(data) - 2:
        assert data[p] == 0xFF and p + 4 <= len(data)
        marker = data[p + 1]
        length = int.from_bytes(data[p + 2:p + 4], "big")
        q = p + 2 + length
        assert 2 <= length and q <= len(data) - 2
        contents = data[p + 4:q]
        segments.append((marker, length, sha256(contents)))
        if marker == 0xC0:
            sof = (int.from_bytes(contents[3:5], "big"),
                   int.from_bytes(contents[1:3], "big"),
                   contents[0], contents[5], contents[7:14:3].hex())
        elif marker == 0xDD:
            assert length == 4
            restart = int.from_bytes(contents, "big")
        elif marker == 0xDA:
            assert sof is not None
            return sof, restart, segments, data[q:-2]
        p = q
    raise AssertionError("missing SOS")


def same_bytes(actual, expected, name):
    if actual != expected:
        offset = next((i for i, (a, b) in enumerate(zip(actual, expected)) if a != b),
                      min(len(actual), len(expected)))
        raise AssertionError(f"{name}: first byte mismatch at {offset}, "
                             f"got {actual[offset:offset + 8].hex()}, expected "
                             f"{expected[offset:offset + 8].hex()}, lengths {len(actual)}/{len(expected)}")


def inspect_entropy(run, manifest, raw):
    summaries = []
    for frame in manifest["entropy"]:
        n, kind = frame["index"], frame["kind"]
        events = raw[n]
        start, = events["F"]
        finish, = events["N"]
        data = bytes(int(byte, 16) for _, byte, _ in events.get("B", []))
        done = events.get("D", [])
        errors = events.get("E", [])
        beats = events.get("B", [])
        stalls = Counter(beat for _, beat in events.get("H", []))
        last = [int(cycle) for cycle, _, flag in beats if int(flag)]
        assert len(events["I"]) == frame["token_count"]
        (run / f"entropy_{n}.observed.scan").write_bytes(data)
        if kind == "ok":
            same_bytes(data, (run / f"entropy_{n}.scan").read_bytes(), frame["name"])
            assert not errors and last == [int(beats[-1][0])] and len(done) == 1
            assert int(done[0][0]) > last[0]
            assert int(stalls[str(len(data) - 1)]) >= 6
            for offset, _ in frame["reference"]["restarts"][:1]:
                assert stalls[str(offset + 1)] >= 6
        elif kind in ("dc", "identity"):
            assert not done and len(errors) == 1 and not last
            _, code, identity = errors[0]
            assert int(code, 16) == frame["expected_error_code"] and int(identity, 16) == frame["capture"]
        else:
            assert not errors and not done and not last and stalls["3"] >= 5
            assert len(events["C"]) == 1
            if kind == "abort":
                assert len(data) == 4
            else:
                assert len(data) == 3
        summaries.append({
            "name": frame["name"], "start_cycle": int(start[0]), "idle_cycle": int(finish[0]),
            "tokens": len(events["I"]), "bytes": len(data), "sha256": sha256(data),
            "first_input": int(events["I"][0][0]), "last_input": int(events["I"][-1][0]),
            "first_byte": int(beats[0][0]) if beats else None, "last_byte": last,
            "done": done, "errors": errors, "held_cycles": sum(stalls.values()),
            "held_ordinals": dict(stalls),
        })
    return summaries


def inspect_encoder(run, manifest, raw):
    from PIL import Image
    summaries = []
    for frame in manifest["encoder"]:
        n, good = frame["index"], frame["good"]
        events = raw[n]
        start, = events["F"]
        finish, = events["N"]
        expected_size = (frame["width"], frame["height"])
        assert len(events["I"]) == expected_size[0] * expected_size[1] // 4
        data = bytearray()
        last_cycles = []
        for cycle, keep, last, word in events.get("B", []):
            mask = int(keep, 16)
            assert mask and (mask & (mask + 1)) == 0
            assert int(last) or mask == 0xFFFF
            data.extend(int(word, 16).to_bytes(16, "little")[:mask.bit_count()])
            if int(last):
                last_cycles.append(int(cycle))
        st, st_id, st_ok = events["S"][0]
        rt, rt_id, rt_ok, rt_err, rt_len, rt_qual, rt_epoch = events["R"][0]
        result_offer, = events["P"]
        assert len(events["S"]) == len(events["R"]) == 1
        assert int(st_id, 16) == int(rt_id, 16) == frame["capture"]
        assert int(rt_epoch, 16) == frame["epoch"] and int(rt_qual) == 75
        assert int(st_ok) == int(rt_ok) == good
        assert int(rt_err, 16) == (0 if good else 1)
        assert int(result_offer[0]) > int(st) and int(rt) - int(result_offer[0]) >= 8
        assert int(st) > int(events["I"][-1][0])
        assert int(events["B"][-1][0]) < int(result_offer[0])
        stalls = events.get("H", [])
        held_tail = [int(cycle) for cycle, _, last in stalls if int(last)]
        report = {
            "name": frame["name"], "start_cycle": int(start[0]), "idle_cycle": int(finish[0]),
            "input_beats": len(events["I"]), "first_input": int(events["I"][0][0]),
            "last_input": int(events["I"][-1][0]), "first_axis": int(events["B"][0][0]),
            "last_axis": int(events["B"][-1][0]), "axis_beats": len(events["B"]),
            "axis_last_cycles": last_cycles, "held_axis_cycles": len(stalls),
            "held_last_cycles": held_tail, "status_cycle": int(st), "result_offer_cycle": int(result_offer[0]),
            "result_cycle": int(rt), "result_code": int(rt_err, 16), "result_ok": bool(int(rt_ok)),
            "result_length": int(rt_len), "observed_bytes": len(data), "observed_sha256": sha256(data),
        }
        if good:
            (run / f"encoder_{n}.observed.jpg").write_bytes(data)
            assert len(last_cycles) == 1 and int(rt_len) == len(data)
            assert last_cycles[0] == int(events["B"][-1][0])
            assert int(result_offer[0]) > last_cycles[0]
            if n == 0:
                assert last_cycles[0] < int(st)
            if n == 1:
                assert len(held_tail) >= 8 and int(st) < last_cycles[0]
            with Image.open(io.BytesIO(data)) as actual:
                actual.load()
                assert actual.format == "JPEG" and actual.size == expected_size and actual.mode == "RGB"
                pixels = actual.tobytes()
            sof, restart, segments, scan = frame_header(data)
            assert sof == (*expected_size, 8, 3, "211111") and restart == frame["restart_interval"]
            expected = (run / f"encoder_{n}.expected.jpg").read_bytes()
            _, _, ref_segments, ref_scan = frame_header(expected)
            same_bytes(scan, ref_scan, f"{frame['name']} scan")
            assert segments == ref_segments, f"{frame['name']}: header segments differ {segments}/{ref_segments}"
            same_bytes(data, expected, f"{frame['name']} full JPEG")
            with Image.open(io.BytesIO(expected)) as golden:
                golden.load()
                same_bytes(pixels, golden.tobytes(), f"{frame['name']} fully decoded pixels")
            y_plane = (run / f"encoder_{n}.y").read_bytes()
            report["decoded_rgb_sha256"] = sha256(pixels)
            report["decoded_luma_mean_abs_error"] = sum(abs(a - b) for a, b in zip(pixels[::3], y_plane)) / len(y_plane)
            report["sof"] = sof
            report["restart_interval"] = restart
        else:
            (run / f"encoder_{n}.discarded_prefix").write_bytes(data)
            assert int(rt_len) == 0 and data
            assert int(st) in [int(cycle) for cycle, _, _ in stalls]
        summaries.append(report)
    return summaries


def score(run, target):
    manifest = json.loads((run / "fixtures.json").read_text(encoding="utf-8"))
    for name, expected in manifest["inputs_sha256"].items():
        assert sha256((run / name).read_bytes()) == expected, f"modified fixture {name}"
    raw = traces(run / f"{target}.trace")
    if target == "entropy":
        result = inspect_entropy(run, manifest, raw)
    else:
        result = inspect_encoder(run, manifest, raw)
    write_json(run / f"{target}.score.json", result)
    print(f"PASS: independent {target} oracle, {len(result)} transactions")


def compare(baseline, candidate):
    manifest_a = json.loads((baseline / "fixtures.json").read_text(encoding="utf-8"))
    manifest_b = json.loads((candidate / "fixtures.json").read_text(encoding="utf-8"))
    assert manifest_a == manifest_b, "A/B fixture identity"
    differences = {}
    for target in ("entropy", "encoder"):
        for run in (baseline, candidate):
            assert (run / f"{target}.score.json").exists(), f"{target} not scored: {run}"
        events_a = traces(baseline / f"{target}.trace")
        events_b = traces(candidate / f"{target}.trace")
        for spec in manifest_a[target]:
            n = spec["index"]
            a, b = events_a[n], events_b[n]
            same_prefix = target == "entropy" or spec["good"]
            if same_prefix:
                assert [event[1:] for event in a.get("B", [])] == [event[1:] for event in b.get("B", [])], (
                    f"A/B accepted data, KEEP or LAST differs: {spec['name']}")
            origin_a, origin_b = int(a["F"][0][0]), int(b["F"][0][0])
            frame = {}
            for event in ("I", "B", "D", "E", "S", "P", "R", "N"):
                cycles_a = [int(fields[0]) - origin_a for fields in a.get(event, [])]
                cycles_b = [int(fields[0]) - origin_b for fields in b.get(event, [])]
                if cycles_a != cycles_b:
                    frame[event] = {"counts": [len(cycles_a), len(cycles_b)],
                                    "first": [cycles_a[0] if cycles_a else None, cycles_b[0] if cycles_b else None],
                                    "last": [cycles_a[-1] if cycles_a else None, cycles_b[-1] if cycles_b else None]}
            if frame:
                differences[spec["name"]] = frame
    write_json(candidate / "comparison.json", {"acceptance_cycle_differences": differences})
    print(f"PASS: A/B accepted data and sidebands, {len(differences)} frames with cycle differences")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    generation = actions.add_parser("generate")
    generation.add_argument("run", type=Path)
    scoring = actions.add_parser("score")
    scoring.add_argument("run", type=Path)
    scoring.add_argument("target", choices=("entropy", "encoder"))
    comparison = actions.add_parser("compare")
    comparison.add_argument("baseline", type=Path)
    comparison.add_argument("candidate", type=Path)
    args = parser.parse_args()
    if args.action == "generate":
        generate(args.run)
    elif args.action == "score":
        score(args.run, args.target)
    else:
        compare(args.baseline, args.candidate)


if __name__ == "__main__":
    main()
