"""Opaque compiler/ROM input preparation; no stimulus, oracle or pass criteria."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def prepare(run: Path, td_root: Path):
    run = Path(run).resolve()
    info = json.loads((ROOT/'verification_reference/jpeg_rate_public/compile.json').read_bytes())
    rom = run/'rom_init'
    rom.mkdir(parents=True, exist_ok=True)
    inputs = {}
    for name, relative in info['rom_initializers'].items():
        source = ROOT/relative
        body = source.read_text()
        depth = int(re.search(r'DEPTH\s*=\s*(\d+)', body).group(1))
        values = {int(a,16):b for a,b in re.findall(r'(?m)^\s*([0-9a-fA-F]+)\s*:\s*([0-9a-fA-F]+)\s*;', body)}
        if set(values) != set(range(depth)):
            raise ValueError('Incomplete ROM initializer: '+relative)
        target = rom/name
        target.write_text(''.join(values[i]+'\n' for i in range(depth)))
        inputs[str(source)] = hashlib.sha256(source.read_bytes()).hexdigest()
        inputs[str(target)] = hashlib.sha256(target.read_bytes()).hexdigest()
    models=[Path(td_root)/p for p in info['models']]
    sources=[ROOT/p for p in info['sources']]+[Path(td_root)/'sim_release/ph1/ph1_phy_gsr.v']
    for source in [*models,*sources]:
        inputs[str(source)]=hashlib.sha256(source.read_bytes()).hexdigest()
    includes=[ROOT/p for p in info['includes']]
    for inc in includes:
        for header in sorted(inc.glob('*.vh')):
            inputs[str(header)]=hashlib.sha256(header.read_bytes()).hexdigest()
    return dict(models=[str(p) for p in models],sources=[str(p) for p in sources],
        includes=[str(p) for p in includes],defines=info['defines'],rom_root=rom.as_posix(),
        rom_suffix='.mif.dath',inputs_sha256=inputs)
