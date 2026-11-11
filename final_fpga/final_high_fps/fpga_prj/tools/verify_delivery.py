"""Static delivery verification. Does not invoke TD or simulation."""
from pathlib import Path
import argparse, hashlib, json, re, xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def inside(path):
    path = path.resolve(strict=True)
    if not path.is_relative_to(ROOT): raise ValueError(f'Dependency outside delivery: {path}')
    return path
def load(path): return json.loads((ROOT/path).read_bytes())
def without_comment_text(data, suffix):
    if suffix=='.vhd':
        return re.sub(rb'"(?:""|[^"])*"|--[^\r\n]*',lambda m:b'--COMMENT' if m[0].startswith(b'--') else m[0],data)
    return re.sub(rb'"(?:\\.|[^"\\])*"|//[^\r\n]*|/\*[\s\S]*?\*/',lambda m:b'/*COMMENT*/' if m[0].startswith((b'//',b'/*')) else m[0],data)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path)
    args=parser.parse_args()
    reloc=load('fpga_docs/provenance/RELOCATION.json')
    for f in reloc['files']:
        assert sha(inside(ROOT/f['path'])) == f['sha256'], f['path']
    original=load('fpga_docs/SOURCE_SEAL.json')
    manifest=load('fpga_prj/SOURCE_MANIFEST.json')
    mapped={r['source'].removeprefix('refactor/camera_fusion_r1/'):r for r in reloc['files']}
    assert hashlib.sha256(json.dumps(original['production_inputs'],sort_keys=True).encode()).hexdigest()==original['design_sha256']
    for path, digest in original['production_inputs'].items():
        item=mapped[path]
        assert item['source_sha256']==digest, path
        if item['sha256']!=digest:
            assert item.get('noncomment_sha256'), path
            file=ROOT/item['path']
            assert hashlib.sha256(without_comment_text(file.read_bytes(),file.suffix)).hexdigest()==item['noncomment_sha256'], path
    for item in manifest['files']: assert sha(inside(ROOT/item['path']))==item['sha256'], item['path']
    native=ROOT/'fpga_prj/al/rfcamera_fusion_r1.al'
    raw=native.read_bytes()
    # Only relocation may differ from the fixed original native project.
    old=(ROOT/'fpga_docs/provenance/rfcamera_fusion_r1.al.source.txt').read_bytes()
    assert hashlib.sha256(old).hexdigest()==original['native_project_sha256']
    expected=old.replace(b'../src_fpga/',b'../../fpga_src/').replace(b'Path="../fpga_prj/constraints/',b'Path="../../fpga_src/constraints/').replace(b'Path="constraints/',b'Path="../../fpga_src/constraints/')
    assert raw==expected, 'Native project changed beyond relative paths'
    tree=ET.fromstring(raw.replace(b'UsedInP&R',b'UsedInP&amp;R'))
    assert tree.attrib['Path']=='.'
    config=tree.find("./FileSets/FileSet[@Name='design_1']/Config")
    reg=[inside(native.parent/x.attrib['Path']).relative_to(ROOT).as_posix() for x in tree.findall('Source_Files//File')]
    inc=[inside(native.parent/x.attrib['Val']).relative_to(ROOT).as_posix() for x in config.findall("Option[@Name='IncludeDir']")]
    assert reg==manifest['registrations'] and inc==manifest['include_dirs']
    assert [f"{n.attrib['Name']}={n.attrib['Val']}" for n in config.findall('Define')]==manifest['definitions']
    assert tree.findtext('TOP_MODULE/MODULE')==manifest['top']
    assert tree.findtext('HardWare/Device')+tree.findtext('HardWare/Speed')==manifest['device']
    assert [r.attrib['Name'] for r in tree.findall('Runs/Run')]==['syn_1','phy_1']
    ip_refs=[]
    for f in (ROOT/'fpga_src/ip').rglob('*'):
        if f.suffix not in ('.xml','.ipc'): continue
        tree_ip=ET.parse(f)
        # IP-XACT filesets and IPC MIFs retain their original relative topology.
        refs=tree_ip.findall('.//{*}file/{*}name')+tree_ip.findall('.//init_file')
        for n in refs:
            name=(n.text or '').strip()
            if not name or name.lower() in ('none','null'): continue
            target=inside(f.parent/name)
            assert target.is_file(), str(target)
            ip_refs.append(target.relative_to(ROOT).as_posix())
    bit_info=load('fpga_prj/bit/BITSTREAM.json')
    assert bit_info['source_commit']==reloc['source_commit']
    assert bit_info['source_design_sha256']==original['design_sha256']
    bit=inside(ROOT/bit_info['file'])
    assert sha(bit)==bit_info['sha256'] and bit.stat().st_size==bit_info['bytes']
    assert len(list((ROOT/'fpga_prj/bit').glob('*.bit')))==1
    report_index=load('fpga_docs/server_seed54_20261111/FILE_INDEX.json')
    assert report_index['results_commit']==bit_info['results_commit']
    for f in report_index['files']:
        path=inside(ROOT/f['path'])
        assert sha(path)==f['sha256'] and path.stat().st_size==f['bytes'], f['path']
    inventory=ROOT/'fpga_docs/DELIVERY_FILES.json'
    if inventory.exists():
        for f in json.loads(inventory.read_bytes())['files']:
            assert sha(inside(ROOT/f['path']))==f['sha256'], f['path']
    report=dict(state='PASS',scope='Static relocation, comment equivalence, hashes and native/IP dependency checks',
        source_commit=reloc['source_commit'],source_design_sha256=original['design_sha256'],
        production_inputs=len(original['production_inputs']),frozen_ip_origin_count=original['frozen_ip_count'],
        production_comment_adjustments=sum(bool(f.get('noncomment_sha256')) for f in reloc['files']),
        registered_inputs=len(reg),include_dirs=len(inc),ip_metadata_references=len(ip_refs),
        copied_file_hashes=len(reloc['files']),server_files_verified=len(report_index['files']),bit_sha256=bit_info['sha256'],
        native_settings='Unchanged except source/include/constraint paths',
        local_simulation='NOT_RUN (organization only)',local_TD='NOT_RUN (organization only)')
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__': main()
