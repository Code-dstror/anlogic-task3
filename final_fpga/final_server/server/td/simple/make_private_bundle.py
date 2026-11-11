"""Build a local-only FinalShell package containing server-local credentials."""
from __future__ import annotations

import argparse
import io
from pathlib import Path
import sys
import tarfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import encoded, read_json
from network import PORTAL


def bundle(credentials, output, source=None):
    credentials = Path(credentials).resolve()
    output = Path(output).resolve()
    source = Path(source or Path(__file__).parent).resolve()
    document = read_json(credentials)
    if (not isinstance(document, dict) or document.get('portal') != PORTAL or
            not all(isinstance(document.get(key), str) and document[key] for key in ('username', 'password')) or
            set(document) - {'portal', 'username', 'password', 'service'}):
        raise ValueError('Invalid private campus authentication configuration')
    if credentials.is_relative_to(source) or output.is_relative_to(source):
        raise ValueError('Private credentials and package must stay outside the versioned program directory')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output, 'x:gz') as archive:
        for path in sorted(source.rglob('*')):
            if (not path.is_file() or path.is_symlink() or '__pycache__' in path.parts or
                    path.suffix not in ('.py', '.sh', '.md', '.json') or path.name == 'network-auth.json'):
                continue
            name = 'private-install/server/td/simple/' + path.relative_to(source).as_posix()
            member = archive.gettarinfo(str(path), arcname=name)
            member.mode = 0o700 if path.suffix == '.sh' else 0o600
            with path.open('rb') as stream:
                archive.addfile(member, stream)
        body = encoded(document)
        member = tarfile.TarInfo('private-install/network-auth.json')
        member.size = len(body)
        member.mode = 0o600
        member.mtime = int(time.time())
        archive.addfile(member, io.BytesIO(body))
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--credentials', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    arguments = parser.parse_args()
    print('Created private FinalShell package: ' + str(bundle(arguments.credentials, arguments.output)))
    print('This package contains credentials. Keep it outside Git and upload only to your own server.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
