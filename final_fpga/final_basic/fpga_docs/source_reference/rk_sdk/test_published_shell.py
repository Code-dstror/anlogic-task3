"""Run the mode controls with a clean copy of an extracted seed1 RK peer Python package."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--peer',type=Path,required=True)
    args = parser.parse_args()
    sdk = Path(__file__).resolve().parent
    repository = sdk.parents[2]
    peer = args.peer.resolve(strict=True)
    if not (peer/'linux/dma_c2h_candidate/receiver.py').is_file():
        parser.error('supply the published runtime/peer directory')
    with tempfile.TemporaryDirectory() as tmp:
        staged = Path(tmp)/'peer'
        # Only Python imports are needed by this device-free ioctl fixture.
        for source in peer.rglob('*.py'):
            target = staged/source.relative_to(peer)
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,target)
        for filename in ('cli.py','consumers.py','controls.py','products.py'):
            shutil.copyfile(repository/'linux/rk_debug'/filename,staged/'linux/rk_debug'/filename)
        # Test fixtures only. Deployed modules are imported solely from SDK + peer.
        env = dict(os.environ, PYTHONPATH=os.pathsep.join(map(str,(sdk,staged,repository/'tests'))))
        subprocess.run([sys.executable,'-B','-c',
            "from linux.rk_debug import cli; from linux.dma_c2h_candidate import receiver;"
            "from linux.task3_pipeline import mono_config_v2; from dual_host import debug_modes;"
            "print(cli.__file__,receiver.__file__,mono_config_v2.__file__,debug_modes.__file__,sep='\\n')"],
            env=env,cwd=tmp,check=True)
        subprocess.run([sys.executable,'-B','-m','unittest','-v','test_mode_shell','test_shared_stereo'],
                       env=env,cwd=tmp,check=True)


if __name__=='__main__':
    main()
