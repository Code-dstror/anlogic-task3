"""Read-only inventory of the exact FPGA-related names supplied by the user."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import process_identity, read_json
from service import legacy_workers


KEEP = {'TD_Release_2026.2_NL', 'fpga-source', 'td_simple', 'fpga_projects', 'opt'}
OLD_CONTROL = {'td_operator', 'td_farm', 'td_runs', 'td_control', 'td_security_v2_dynamic',
               'td_automation_repair_20261013', 'td_automation_rollback_repair_20261013',
               'td_runtime_recovery_20261014', 'td_git18_hotfix', 'vcs_pilot'}
INSTALL_ONLY = {'TD_Release_2026.2_NL.zip', 'install_python312.sh',
                'td-simple-private-20261022.tar.gz',
                'cpython-3.12.9+20250212-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz',
                'cpython-3.12.9+20250212-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz.sha256',
                'ha_cache_recovery_v2.py', 'ha_cache_recovery_v3.py', 'ha_cache_repair_20261020.py'}
REVIEW = {'license_for_website', 'license_for_website.zip', 'Project', 'da'}


def artifact_counts(path):
    counts = {'bitstreams': 0, 'databases': 0, 'reports_logs': 0, 'samples': []}
    for directory, subdirectories, files in os.walk(path, followlinks=False):
        subdirectories[:] = [name for name in subdirectories if name not in ('.git', 'objects', 'node_modules', '__pycache__')
                             and not (Path(directory) / name).is_symlink()]
        for name in files:
            candidate = Path(directory) / name
            if candidate.is_symlink():
                continue
            category = ('bitstreams' if candidate.suffix.lower() == '.bit' else
                        'databases' if candidate.suffix.lower() == '.db' else
                        'reports_logs' if candidate.suffix.lower() in ('.log', '.timing', '.area', '.rpt') else None)
            if category:
                counts[category] += 1
                if len(counts['samples']) < 12:
                    counts['samples'].append(str(candidate))
    return counts


def inventory(home):
    home = Path(home).resolve()
    root = home / 'td_simple'
    config = read_json(root / 'config.json', {})
    status = read_json(root / 'status.json', {})
    retirement = read_json(root / 'legacy-retirement.json', {})
    current_process = process_identity(status.get('controller_pid'))
    current = bool(current_process and time.time() - status.get('generated_at', 0) < 120)
    active_legacy = legacy_workers(home / 'td_farm')
    entries = []
    for name in sorted(KEEP | OLD_CONTROL | INSTALL_ONLY | REVIEW):
        path = home / name
        if not path.exists() and not path.is_symlink():
            continue
        category = ('KEEP' if name in KEEP else 'INSTALLER_ONLY_AFTER_NEW_SERVICE_WORKS' if name in INSTALL_ONLY
                    else 'PRESERVE_ARTIFACTS_AND_CHECK_DEPENDENCIES' if name in OLD_CONTROL else 'UNKNOWN_KEEP_FOR_NOW')
        entry = dict(path=str(path), category=category, symlink=path.is_symlink())
        if name in OLD_CONTROL and path.is_dir() and not path.is_symlink():
            entry['artifacts'] = artifact_counts(path)
        entries.append(entry)
    cron = subprocess.run(['crontab', '-l'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    references = [line for line in cron.stdout.decode(errors='replace').splitlines()
                  if any(str(home / name) in line for name in KEEP | OLD_CONTROL)]
    return dict(read_only=True, new_controller_alive=current, legacy_retirement=retirement.get('state', 'NOT_RUN'),
                active_legacy_workers=active_legacy, active_paths={name: config.get(name) for name in
                    ('td_root', 'jobs_root', 'seed_repo', 'legacy_farm')},
                license_environment=config.get('environment', {}), cron_references=references, entries=entries,
                deletion_approved=False,
                note='Names alone do not prove old directories are disposable. Keep unique bits, DBs, reports and keys.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', type=Path, default=Path.home())
    arguments = parser.parse_args()
    print(json.dumps(inventory(arguments.home), ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
