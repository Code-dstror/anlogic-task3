"""Offline path and byte-identity verification for this relocated source bundle."""
from pathlib import Path
import hashlib,json,re

root=Path(__file__).resolve().parents[3]
binding=json.loads((root/'fpga_docs/SOURCE_BINDING.json').read_bytes())
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for row in binding['all_source_copies']:
    assert digest(root/row['destination'])==row['sha256'],row['destination']
for row in binding['production_inputs']:
    assert digest(root/row['destination'])==row['sha256'],row['destination']
    if row.get('active_text_sha256'):
        p=root/row['destination']
        if p.suffix.lower() in ('.vhd','.vhdl'):
            pattern=r'"(?:""|[^"])*"|--[^\r\n]*'
        else:
            pattern=r'"(?:\\.|[^"\\])*"|//[^\r\n]*|/\*[\s\S]*?\*/'
        # Preserve original newline encoding for this digest.
        original_text=p.read_bytes().decode('utf-8')
        active=re.sub(pattern,lambda m:'' if m[0].startswith(('--',) if p.suffix.lower() in ('.vhd','.vhdl') else ('//','/*')) else m[0],original_text)
        assert hashlib.sha256(active.encode()).hexdigest()==row['active_text_sha256'],p
project=root/'fpga_prj/al/rfcamera_raw_r2.al'
assert digest(project)==binding['relocated_native_sha256'],'Native project changed'
body=project.read_text(encoding='utf-8')
assert re.search(r'<Project\b[^>]*\bPath="\."',body)
paths=re.findall(r'<File\b[^>]*\bPath="([^"]+)"',body)+re.findall(r'<Option\s+Name="IncludeDir"\s+Val="([^"]+)"',body)
for rel in paths:
    assert not re.match(r'^[A-Za-z]:|^[/\\]',rel),rel
    resolved=(project.parent/rel).resolve()
    assert resolved.is_relative_to(root) and resolved.exists(),rel
assert digest(root/binding['bit']['path'])==binding['bit']['sha256'],'Bit differs'
print(json.dumps(dict(status='PASS',source_commit=binding['source_commit'],production_inputs=len(binding['production_inputs']),all_source_copies=len(binding['all_source_copies']),native_paths=len(paths),bit_sha256=binding['bit']['sha256']),indent=2))
