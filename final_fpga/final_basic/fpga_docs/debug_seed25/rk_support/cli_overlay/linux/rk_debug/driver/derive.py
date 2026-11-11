"""Exact owned derivative; never modifies the base driver or protocol headers."""
from pathlib import Path
import argparse
import difflib
import hashlib
import json
import re
import struct

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASE = ROOT / 'linux/dma_c2h_candidate/ph1a_c2h.c'
BASE_SHA256 = '210a4b5397f01522e72c224257c58e34b9e196194020990fbd1f9db0103c009b'
DEPENDENCIES = {
    'linux/dma_c2h_candidate/c2h_uapi.h': '163479e9b6832f303da6be288891bf424a48d0435c493c8588162de4b9b670fe',
    'linux/dma_c2h_candidate/c2h_hw_abi.h': 'bef673e83fc67d670e77fd91ea67b0d52ebaca640e8de10f4ac7be40495e6c49',
    'linux/dma_c2h_candidate/c2h_lifecycle.h': '20ba8a963e5942d640ef221b263ee6044901088ed2d42c412350c122c30ced8f',
    'linux/dma_c2h_candidate/c2h_legacy_policy.h': 'a6501a95fa9ea10901a698299f0953d0c6bc01930987df6a11ac9cf53e9a242b',
    'docs/pcie_protocol_v1.h': '0aff1930bfa5e3f32e4a0c4c8d08d29635d4a93bf4146d8898c94b0472e8e341',
}


def derive():
    for path, digest in DEPENDENCIES.items():
        if hashlib.sha256((ROOT/path).read_bytes()).hexdigest() != digest:
            raise ValueError('dependency identity changed: '+path)
    raw = BASE.read_bytes()
    if hashlib.sha256(raw).hexdigest() != BASE_SHA256:
        raise ValueError('base driver identity changed; explicit re-review required')
    original = raw.decode()
    text = original
    def swap(old, new):
        nonlocal text
        if text.count(old) != 1:
            raise ValueError('derived source anchor is not unique')
        text = text.replace(old, new)
    swap('#include "c2h_lifecycle.h"', '#include "c2h_lifecycle.h"\n#include "c2h_debug_uapi.h"\n#include "debug_reset_guard.h"')
    swap('static char *target_bdf;', 'static char *target_bdf;\nstatic bool allow_source_reset;')
    swap('module_param(target_bdf, charp, 0444);', 'module_param(target_bdf, charp, 0444);\nmodule_param(allow_source_reset, bool, 0444);\nMODULE_PARM_DESC(allow_source_reset, "Opt-in operator declaration of reviewed ordered-reset image; not firmware attestation");')
    swap('\tatomic64_t interrupts;\n', '\tatomic64_t interrupts;\n\tstruct rkdbg_state debug_reset;\n')
    swap('static u32 command(struct c2h_dev *d, u32 cmd)', '#include "debug_driver_hooks.h"\n\nstatic u32 command(struct c2h_dev *d, u32 cmd)')
    swap('\tstruct c2h_owner_info owner = {};', '\tstruct c2h_owner_info owner = {};\n\tstruct c2h_debug_cap debug_cap = {};\n\tstruct c2h_debug_reset debug_request;')
    swap('\tif (cmd == C2H_RELEASE && copy_from_user', '\tif (cmd == C2H_SOURCE_RESET && copy_from_user(&debug_request, (void __user *)arg, sizeof(debug_request)))\n\t\treturn -EFAULT;\n\tif (cmd == C2H_RELEASE && copy_from_user')
    swap('\tif (cmd == C2H_GET_OWNER) {', '\tif (cmd == C2H_GET_DEBUG_CAP) {\n\t\tdebug_cap_locked(d, &debug_cap);\n\t\tret = copy_to_user((void __user *)arg, &debug_cap, sizeof(debug_cap)) ? -EFAULT : 0;\n\t\tgoto out;\n\t}\n\tif (cmd == C2H_GET_OWNER) {')
    swap('\tswitch (cmd) {\n\tcase C2H_LEGACY:', '\tswitch (cmd) {\n\tcase C2H_SOURCE_RESET:\n\t\tret = debug_reset_locked(d, &debug_request);\n\t\tbreak;\n\tcase C2H_LEGACY:')
    swap('\t\t\tif (op->write && c2h_legacy_record_write(op->offset)', '\t\t\tif (op->write && d->debug_reset.state == RKDBG_RESET_ISSUED) {\n\t\t\t\tret = -EBUSY;\n\t\t\t\tgoto out;\n\t\t\t}\n\t\t\tif (op->write && c2h_legacy_record_write(op->offset)')
    swap('\tcase C2H_START:\n', '\tcase C2H_START:\n\t\tif (d->debug_reset.state == RKDBG_RESET_ISSUED) {\n\t\t\tret = -EBUSY;\n\t\t\tbreak;\n\t\t}\n')
    text = text.replace('"ph1a_c2h_candidate"', '"ph1a_c2h_debug"')
    swap('"ph1a_c2h_%s"', '"ph1a_c2h_debug_%s"')
    swap('MODULE_DESCRIPTION("Isolated PH1A frame-grant C2H candidate, private ABI v1");',
         'MODULE_DESCRIPTION("PH1A C2H debug derivative; guarded source reset; hardware ABI1/UAPI2 unchanged");')
    patch = ''.join(difflib.unified_diff(original.splitlines(True), text.splitlines(True),
        fromfile='linux/dma_c2h_candidate/ph1a_c2h.c', tofile='linux/rk_debug/driver/ph1a_c2h_debug.c'))
    return text, patch


def python_constants():
    constants = (HERE / 'debug_constants.h').read_text()
    uapi = (HERE / 'c2h_debug_uapi.h').read_text()
    base_uapi = (BASE.parent / 'c2h_uapi.h').read_text()
    occupied = {int(x, 16) for x in re.findall(r"_IO(?:R|W|WR)?\('H', (0x[0-9a-fA-F]+),?", base_uapi)}
    lines = ['"""Generated from debug_constants.h and c2h_debug_uapi.h; host-only."""']
    for name, value in re.findall(r'^#define (RKDBG_\w+) (\d+)$', constants, re.M):
        lines.append(f'{name} = {value}')
    for name, direction, number, typename in re.findall(r"#define (C2H_\w+) _IO([RW])\('H', (0x[0-9a-fA-F]+), struct (\w+)\)", uapi):
        number = int(number, 16)
        if number in occupied or number < 0x46:
            raise ValueError('debug ioctl number collision')
        body = re.search(r'struct '+typename+r'\s*\{([^}]+)\}', uapi)[1]
        fields = []
        for declarations in re.findall(r'__u32\s+([^;]+);', body):
            fields.extend(x.strip() for x in declarations.split(','))
        fmt = '=' + str(len(fields)) + 'I'
        code = ((2 if direction == 'R' else 1) << 30) | (struct.calcsize(fmt) << 16) | (ord('H') << 8) | number
        lines.extend((f'{name} = 0x{code:08x}', f'{name}_FORMAT = {fmt!r}', f'{name}_FIELDS = {tuple(fields)!r}'))
    return '\n'.join(lines)+'\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source, patch = derive()
    outputs = {'ph1a_c2h_debug.c': source, 'ph1a_c2h_debug.patch': patch, 'debug_abi.py': python_constants()}
    manifest = dict(format='rk-debug-driver-derivation-v1',
        base_path=BASE.relative_to(ROOT).as_posix(), base_sha256=BASE_SHA256,
        dependencies=DEPENDENCIES,
        generated={name: hashlib.sha256(value.encode()).hexdigest() for name,value in outputs.items()},
        owned_headers={name: hashlib.sha256((HERE/name).read_bytes()).hexdigest() for name in
                       ('c2h_debug_uapi.h','debug_constants.h','debug_reset_guard.h','debug_driver_hooks.h')},
        source_reset_default='DISABLED_OPERATOR_OPT_IN_NOT_FIRMWARE_ATTESTATION',
        kernel_build='BLOCKED_MATCHING_KDIR_REQUIRED', module_load='NOT_RUN', board='NOT_RUN')
    outputs['DERIVATION.json'] = json.dumps(manifest, indent=2, sort_keys=True)+'\n'
    for name, text in outputs.items():
        path = HERE/name
        if args.check:
            if not path.exists() or path.read_text() != text:
                raise SystemExit('STALE: '+name)
        else:
            path.write_text(text, encoding='utf-8', newline='\n')
    print('PASS exact base-derived source/patch and additive host UAPI constants' if args.check else 'Generated isolated debug derivative')


if __name__ == '__main__': main()
