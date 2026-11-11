"""Build a credential-free simple-controller update with explicit timestamps."""
from __future__ import annotations

import argparse
import ast
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import time


def bundle(output):
    repo = Path(__file__).resolve().parents[2]
    source = repo / 'server/td/simple'
    output = Path(output).resolve()
    if output.is_relative_to(source):
        raise ValueError('Keep the archive outside the application source directory')
    output.parent.mkdir(parents=True, exist_ok=True)
    model = ast.parse((source / 'common.py').read_text(encoding='utf-8-sig'))
    version = next(ast.literal_eval(item.value) for item in model.body if isinstance(item, ast.Assign)
                   and any(isinstance(target, ast.Name) and target.id == 'VERSION' for target in item.targets))
    paths = sorted([path for path in source.iterdir() if path.is_file() and path.suffix in {'.py', '.sh', '.md', '.json'}]
                   + list((source / 'tools').glob('*.py')))
    files = {}
    for path in paths:
        if path.is_symlink() or path.name in {'network-auth.json', 'config.json'}:
            raise ValueError('Private or linked input in public application source: ' + path.name)
        body = path.read_bytes()
        if path.suffix == '.sh' and b'\r\n' in body:
            raise ValueError('Shell scripts must use LF: ' + path.name)
        if path.suffix == '.py':
            ast.parse(body.decode('utf-8-sig'), filename=str(path))
        files[path.relative_to(repo).as_posix()] = body
    manifest = dict(controller_version=version,
                    base_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
                    source='local working tree; deployment requires the server receipt', credentials_included=False,
                    files=[dict(path=name, bytes=len(body), sha256=hashlib.sha256(body).hexdigest())
                           for name, body in files.items()])
    files['td-simple-update-manifest.json'] = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    stamp = int(time.time())
    with tarfile.open(output, 'x:gz', format=tarfile.PAX_FORMAT) as archive:
        for name, body in files.items():
            member = tarfile.TarInfo(name)
            member.size, member.mtime = len(body), stamp
            member.mode = 0o700 if name.endswith('.sh') else 0o600
            archive.addfile(member, io.BytesIO(body))
    with tarfile.open(output, 'r:gz') as archive:
        if set(archive.getnames()) != set(files):
            raise ValueError('Archive inventory mismatch')
        for member in archive.getmembers():
            if (not member.isfile() or member.mtime != stamp or
                    PurePosixPath(member.name).is_absolute() or '..' in PurePosixPath(member.name).parts or
                    archive.extractfile(member).read() != files[member.name]):
                raise ValueError('Archive verification failed: ' + member.name)
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix + '.sha256').write_bytes((checksum + '  ' + output.name + '\n').encode('ascii'))
    return dict(path=str(output), version=version, members=len(files), bytes=output.stat().st_size,
                sha256=checksum, timestamps_valid=True, payload_verified=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    arguments = parser.parse_args()
    print(json.dumps(bundle(arguments.output), ensure_ascii=False))
