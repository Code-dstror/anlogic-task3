"""Read-only observations for a proposed JPEG mono/dual session restart.

Import collect(owner) into the existing owner; this module never opens a device,
writes BAR, issues STOP/RESET/START, releases leases, or starts a polling thread.
The CLI only compares saved JSON. A match is not a board qualification.
"""
from dataclasses import asdict
from pathlib import Path
import argparse
import json
import time


def protocol():
    # Use the delivered generated constants; no independent address table.
    from dual_host import pcie_protocol_v1 as p
    from dual_host import stereo_control_v1 as s
    return p, s


def collect(owner):
    """Call under the existing application's control/receive serialization.

    Read failures propagate. The caller decides where to save the result.
    Sequential BAR reads are not an atomic hardware snapshot.
    """
    p, _ = protocol()
    fields = {
        'control': p.PCIE_REG_CONTROL, 'status': p.PCIE_REG_STATUS,
        'cfg_session': p.PCIE_REG_CFG_SESSION,
        'active_session': p.PCIE_REG_CFG_ACTIVE_SESSION,
        'cfg_status': p.PCIE_REG_CFG_STATUS, 'cfg_error': p.PCIE_REG_CFG_ERROR,
        'epoch': p.PCIE_REG_CFG_MODE_EPOCH,
        'mode': p.PCIE_REG_CFG_ACTIVE_MODE, 'quality': p.PCIE_REG_CFG_ACTIVE_QUALITY,
        'profile': p.PCIE_REG_CFG_COMPILED_PROFILE,
        'cameras': p.PCIE_REG_CFG_CAMERA_PRESENT,
        'stereo_status': p.PCIE_REG_STEREO_STATUS,
        'stereo_error': p.PCIE_REG_STEREO_ERROR,
        'stereo_mode': p.PCIE_REG_STEREO_ACTIVE_MODE,
        'record_version': p.PCIE_REG_RECORD_SELECTED_VERSION,
        'record_header': p.PCIE_REG_RECORD_SELECTED_HEADER_LENGTH,
    }
    guard_keys = ('cfg_session', 'active_session', 'epoch', 'stereo_mode',
                  'record_version', 'record_header')
    before = {k: owner.read32(fields[k]) for k in guard_keys}
    registers = {k: owner.read32(address) for k, address in fields.items()}
    result = dict(schema=1, monotonic_ns=time.monotonic_ns(),
                  owner=asdict(owner.owner_identity()), registers=registers,
                  transport=asdict(owner.snapshot()), leased=owner.leased_count,
                  unread=bool(owner.poll(0)))
    after = {k: owner.read32(fields[k]) for k in guard_keys}
    result['identity_stable'] = before == after == {k: registers[k] for k in guard_keys}
    return result


def evaluate(before, after):
    """Check observed post-reset BOOT, BEFORE selecting topology or v4.

    Cannot prove upstream drain, reset command execution, sensor readiness,
    record contents, or eventual sustained frame rate.
    """
    p, s = protocol()
    r, t = after['registers'], after['transport']
    issues = []
    def require(condition, reason):
        if not condition:
            issues.append(reason)
    require(before['schema'] == after['schema'] == 1, 'snapshot schema mismatch')
    require(before['identity_stable'] and after['identity_stable'], 'identity changed during reads')
    require(before['owner'] == after['owner'], 'owner/PCI identity changed')
    require(before['registers']['cfg_session'] != 0, 'old CFG session unknown')
    require(r['cfg_session'] != 0 and r['cfg_session'] != before['registers']['cfg_session'],
            'new nonzero CFG session not observed')
    require(r['active_session'] == r['cfg_session'], 'ACTIVE session mismatch')
    require(t['running'] == 0 and t['stopped'] == 1 and t['quarantined'] == 0
            and t['submitted'] == t['completed'], 'host transport not drained')
    require(after['leased'] == 0 and not after['unread'], 'leased/unread host results remain')
    busy = (p.PCIE_STATUS_C2H_RUNNING | p.PCIE_STATUS_TX_BUSY |
            p.PCIE_STATUS_SOURCE_BUSY | p.PCIE_STATUS_SESSION_ARMED | p.PCIE_STATUS_FRAME_ERROR)
    ready = p.PCIE_STATUS_LINK_UP | p.PCIE_STATUS_USER_RESET_RELEASED | p.PCIE_STATUS_SESSION_REARM_READY
    require(r['control'] == 0 and r['status'] & busy == 0
            and r['status'] & ready == ready, 'FPGA pre-ARM status not ready')
    require(r['cfg_status'] == p.PCIE_CFG_STATUS_SESSION_READY and r['cfg_error'] == 0,
            'CFG not in idle error-free BOOT')
    require((r['epoch'], r['mode'], r['quality']) == (0, p.PCIE_CFG_MODE_COLOR, p.PCIE_CFG_DEFAULT_QUALITY),
            'CFG not epoch0 COLOR/Q75')
    require(r['stereo_status'] == 0 and r['stereo_error'] == 0
            and r['stereo_mode'] == s.STEREO_MODES_MONO,
            'topology not reset to unlocked idle MONO')
    require((r['profile'], r['cameras']) == (p.PCIE_CFG_PROFILE_MONO1920, 1),
            'MONO capability/presence not restored')
    require((r['record_version'], r['record_header']) == (p.PROTOCOL_VERSION, p.HEADER_LENGTH),
            'record selector not reset to this bitstream v1/64 BOOT')
    return dict(state='BLOCKED' if issues else 'BOOT_OBSERVATIONS_MATCH_NOT_SWITCH_QUALIFIED',
                issues=issues, old_cfg_session=before['registers']['cfg_session'],
                new_cfg_session=r['cfg_session'],
                limitations=['Not an atomic hardware snapshot', 'Does not prove FPGA owners drained',
                             'Does not prove topology selection or first new frame', 'No hardware action performed'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    args = parser.parse_args()
    try:
        result = evaluate(json.loads(args.before.read_text(encoding='utf-8')),
                          json.loads(args.after.read_text(encoding='utf-8')))
    except (KeyError, TypeError, ValueError) as exc:
        print(json.dumps(dict(state='INVALID_INPUT', error=str(exc))))
        return 2
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 1 if result['issues'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
