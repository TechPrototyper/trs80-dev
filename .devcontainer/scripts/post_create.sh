#!/bin/bash
# Post-create: install trszog VSIX, then build the emulator.
set -e

WS="/workspaces/trs80-dev"

echo "=== Installing extensions ==="
CODE_BIN="code"
command -v code &>/dev/null || CODE_BIN="/usr/bin/code"

$CODE_BIN --install-extension "$WS/.devcontainer/trszog.vsix" --force 2>&1 || \
    echo "WARNING: trszog.vsix install failed"

$CODE_BIN --install-extension "$WS/.devcontainer/z80asm.vsix" --force 2>&1 || \
    echo "WARNING: z80asm.vsix install failed"

echo ""
echo "=== Building emulator ==="
bash "$WS/.devcontainer/scripts/setup.sh"
