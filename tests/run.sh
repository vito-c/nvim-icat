#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

nvim --headless \
    -u NONE \
    --cmd 'set shadafile=NONE' \
    --cmd 'set directory=/tmp' \
    --cmd 'set noswapfile' \
    -l tests/nvim-icat_spec.lua
