#!/bin/bash
set -euo pipefail
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "${TD_PYTHON:-python3}" -I -B "$script_directory/install.py" \
    --root "$HOME/td_simple" \
    --projects-root "$HOME/fpga_projects" \
    --td-root "${TD_ROOT:?Set TD_ROOT to the TD installation directory}" \
    --seed-repo "${TD_SEED_REPO:?Set TD_SEED_REPO to the source checkout}" \
    --wait-idle --start "$@"
