"""Independent v4 wire, full ISP raster, JPEG byte/decode and fixed-window checker."""
from pathlib import Path
import argparse
import hashlib
import io
import json
import re
import sys
from PIL import Image, __version__ as pillow_version

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REF = ROOT / 'verification_reference'
sys.path[:0] = [str(HERE.parent / 'merge_integration_20261101/protocol_reference'),
               str(REF), str(REF / 'src_fpga/simulation'), str(HERE)]
from linux.stream_diag.records import parse_record, parse_header
from linux.task3_pipeline import pcie_protocol_v1 as p
import jpeg_shared_encoder_reference as jpeg
from dual_reference import pixels


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def need(ok, why):
    if not ok:
        raise AssertionError(why)


def check(run, out):
    q = json.loads((run / 'qualification.json').read_text())
    sid = json.loads((run / 'source_identity.json').read_text())
    need(q['status'] == 'PASS_DUAL_RATE_MAIN' and not sid['startup_only'] and not sid['compile_only'], 'real complete MAIN required')
    need(q['owned_warning_count'] == 0 and q['source_identity_sha256'] == sha(run / 'source_identity.json'), 'source/warning binding')
    for row in sid['inputs']:
        need(sha(row['path']) == row['sha256'], 'input drift ' + row['path'])
    body = (run / 'run.log').read_text(errors='replace')
    need('RESULT: PASS UNIFIED_DUAL_RATE_MAIN' in body and not re.search(r'\*\* (Error|Fatal):', body), 'actual terminal with no runtime error')
    events = [json.loads(line) for line in (run / 'dual_events.jsonl').read_text().splitlines() if line]
    rate = [json.loads(line) for line in (run / 'throughput_events.jsonl').read_text().splitlines() if line]
    fixture = [e for e in events if e['event'] == 'fixture']
    need(len(fixture) == 1, 'one actual fixture profile')
    cfg = fixture[0]
    need((cfg['width'], cfg['height'], cfg['record_version'], cfg['capture_divisor'], cfg['complete_per_eye'], cfg['quality'], cfg['pattern']) ==
         (1920, 1080, 4, 2, sid['frames_per_eye'], sid['quality'], 'hashed_detail_v1'), 'explicit full-HD v4/N2 high-detail contract')
    applied = [e for e in events if e['event'] == 'cfg_applied']
    sofs = [e for e in events if e['event'] == 'cfg_sof']
    need(len(applied) == 1 and applied[0]['quality'] == sid['quality'] and
         any(e['raw_sequence'] == applied[0]['first_sequence'] and e['time'] <= applied[0]['time'] for e in sofs), 'actual Q CFG APPLIED binds real SOF')
    sources = [e for e in events if e['event'] == 'source']
    count = sid['frames_per_eye']
    need(len(sources) == 2 * count, 'complete selected source count')
    selected_by_eye, source_by_eye = {}, {}
    for eye in (0, 1):
        fs = [e for e in rate if e['event'] == 'trusted_fs' and e['camera'] == eye]
        need(len(fs) == 2 * count and [e['ordinal'] for e in fs] == list(range(2 * count)), 'all true FS ordinals accounted')
        need([e['selected'] for e in fs] == [int(n % 2 == 0) for n in range(2 * count)], 'independent physical FS N2 rule')
        selected_by_eye[eye] = [e['sequence'] for e in fs if e['selected']]
        source_by_eye[eye] = [e['sequence'] for e in sources if e['camera'] == eye]
        need(source_by_eye[eye] == selected_by_eye[eye] and len(set(source_by_eye[eye])) == count, 'selected identities reach processing exactly once and in per-eye order')
        sensors = [e for e in rate if e['event'] == 'sensor_fs' and e['camera'] == eye]
        need(len(sensors) == 2 * count, 'actual electrical source ledger')
        need(all(abs((b['time_ns'] - a['time_ns']) - 16666667) < 0.001 for a, b in zip(sensors, sensors[1:])), 'fixed free-running physical60 deadlines')
    summaries = [e for e in rate if e['event'] == 'summary']
    windows = [e for e in rate if e['event'] == 'fixed_window']
    need(len(summaries) == 1 and len(windows) == 2, 'fixed interval and separate drain evidence')
    summary = summaries[0]
    window_seconds = (summary['input_end_ns'] - summary['origin_ns']) / 1e9
    need(abs(window_seconds - (2 * count * 16666667 + sid['eye_phase_ns']) / 1e9) < 1e-9, 'rate denominator equals original input window')
    for row in windows:
        need(row['writer'] == count and row['safe'] == count, 'complete JPEG and host SAFE rate pass before drain')
    need(all(summary[k] > 0 for k in ['aw_stalls', 'w_stalls', 'ar_stalls', 'r_gaps', 'b_gaps', 'host_axis_stall_checks', 'ack_hold_checks']), 'finite stalls actually observed')
    # The image pattern is constant across source frames, and different per eye.
    # Generate each camera's independent expected JPEG once, then compare every
    # source's complete ISP raster, record bytes and entropy bytes to that image.
    references = {}
    records = []
    for eye in (0, 1):
        image = pixels(eye, 1920, 1080, cfg['pattern'])
        folder = out / ('camera' + str(eye))
        folder.mkdir()
        prior = jpeg.pixels_for
        try:
            jpeg.pixels_for = lambda width, height, pattern: iter(image)
            jpeg.generate_frame(folder, dict(case=0, width=1920, height=1080, quality=sid['quality'], restart=0, pattern='independent_dual_raw'))
        finally:
            jpeg.pixels_for = prior
        expected = (folder / 'case0.expected.jpg').read_bytes()
        expected_rgb = [sum(((r << 16) | (g << 8) | b) << (24 * lane) for lane, (r, g, b) in enumerate(image[n:n + 4]))
                        for n in range(0, len(image), 4)]
        references[eye] = {'jpeg_sha256': hashlib.sha256(expected).hexdigest(), 'jpeg_bytes': len(expected)}
        for source in [e for e in sources if e['camera'] == eye]:
            key = tuple(source[k] for k in ('camera', 'session', 'epoch', 'sequence'))
            stages = [e for e in events if e['event'] not in ('fixture', 'cfg_applied', 'cfg_sof') and
                      tuple(e.get(k) for k in ('camera', 'session', 'epoch', 'sequence')) == key]
            need([e['event'] for e in stages] == ['source', 'writer', 'user_last', 'safe', 'ack', 'retire'], 'complete unique actual lifecycle')
            need(all(a['time'] <= b['time'] for a, b in zip(stages, stages[1:])), 'monotonic actual lifecycle')
            writer = stages[1]
            need(writer['ok'] == 1 and writer['error'] == 0 and writer['jpeg_aw'] == writer['jpeg_b'], 'successful JPEG has all real B responses')
            stem = f"camera{eye}_sequence{source['sequence']}"
            actual = (run / (stem + '.actual.record.bin')).read_bytes()
            local = (run / (stem + '.local.record.bin')).read_bytes()
            need(actual == local, 'native committed wire equals ordered DFI record')
            record = parse_record(actual, expected_version=4)
            header = parse_header(actual[:2112], expected_version=4)
            m = record.metadata
            need((m.source.camera, m.source.session, m.source.epoch, m.source.sequence) == key, 'v4 exact pre-JPEG SOURCE tuple')
            need((record.width, record.height, header['quality']) == (1920, 1080, sid['quality']), 'v4 geometry/Q')
            need(record.timestamp_ns == source['timestamp_ns'], 'actual FS timestamp preserved')
            need((m.jpeg_slot, m.jpeg_generation, m.write_tag) == (writer['slot'], writer['generation'], writer['tag']) and m.jpeg_slot // 3 == eye, 'exact independent JPEG slot/generation/tag')
            need((m.source.kind, m.source.format, m.source.role) == (p.PCIE_RECORD_V2_SOURCE_PHYSICAL, p.PCIE_RECORD_V2_FORMAT_RAW10, p.PCIE_RECORD_V2_ROLE_SINGLE), 'physical independent SDR source semantics')
            need(m.pair_id is None and not m.qualified and m.record_flags == 0 and m.processing_member == 0, 'no invented pair/optical qualification')
            need(m.actual_exposure is None and m.actual_gain is None and m.calibration_id is None, 'unknown optical measurements remain unknown')
            with (run / (stem + '.isp.hex')).open() as stream:
                for n, line in enumerate(stream):
                    need(n < len(expected_rgb) and int(line, 16) == expected_rgb[n], f'{stem} independent full ISP group{n}')
            need(n + 1 == 1920 * 1080 // 4, 'complete ISP raster including final group')
            need(record.jpeg == expected, 'complete JPEG entropy equals independent fixed-point reference')
            with Image.open(io.BytesIO(record.jpeg)) as decoded:
                decoded.load()
                need(decoded.size == (1920, 1080), 'every complete JPEG decodes')
            records.append({'source': source, 'writer': writer, 'record_bytes': len(actual),
                'record_sha256': hashlib.sha256(actual).hexdigest(), 'jpeg_bytes': len(record.jpeg),
                'jpeg_sha256': hashlib.sha256(record.jpeg).hexdigest(), 'complete_decode': 'PASS', 'independent_ISP_and_JPEG_bytes': 'PASS'})
    need(references[0]['jpeg_sha256'] != references[1]['jpeg_sha256'], 'two distinct independent eye images')
    for row in sid['inputs']:
        need(sha(row['path']) == row['sha256'], 'input drift during oracle ' + row['path'])
    result = {'status': 'PASS_BOUNDED_HD_DUAL_RATE_AND_INDEPENDENT_ORACLE', 'records': records,
        'reference_images': references, 'fixed_window_seconds': window_seconds,
        'complete_SAFE_per_eye_per_second': [count / window_seconds, count / window_seconds],
        'frames_per_eye': count, 'source_identity_sha256': sha(run / 'source_identity.json'),
        'pillow_version': pillow_version, 'board': 'NOT_RUN', 'long_term_rate': 'NOT_QUALIFIED_10_MINUTE_BOARD_REQUIRED',
        'physical_sync': 'NOT_QUALIFIED', 'pattern_changes_between_frames': False}
    (out / 'qualification.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'status': result['status'], 'records': len(records), 'fixed_window_seconds': window_seconds}))


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run-directory', type=Path, required=True)
    ap.add_argument('--output-directory', type=Path, required=True)
    args = ap.parse_args()
    args.output_directory.mkdir(parents=True, exist_ok=False)
    try:
        check(args.run_directory.resolve(), args.output_directory.resolve())
    except Exception as exc:
        (args.output_directory / 'qualification.json').write_text(json.dumps({'status': 'FAIL', 'error': str(exc), 'checker_sha256': sha(__file__)}, indent=2) + '\n')
        raise
