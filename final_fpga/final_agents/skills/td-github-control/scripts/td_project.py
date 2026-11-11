"""Compatibility CLI; maintained implementation lives in server/td/client."""
from pathlib import Path
import runpy

if __name__ == '__main__':
    root = Path(__file__).resolve().parents[4]
    runpy.run_path(str(root/'server/td/client/td_project.py'), run_name='__main__')
