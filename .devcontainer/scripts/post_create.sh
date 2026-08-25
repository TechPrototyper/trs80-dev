#!/bin/bash
# Post-create: install extensions (VSIX), then build the emulator.
set -e

WS="/workspaces/trs80-dev"
EXT_DIR="$HOME/.vscode-remote/extensions"
mkdir -p "$EXT_DIR"

echo "=== Installing trszog (DeZog fork for TRS-80) ==="
install_vsix() {
    local vsix="$1"
    local id="$2"
    local target="$EXT_DIR/$id"
    rm -rf "$target"
    mkdir -p /tmp/vsx_extract
    (cd /tmp/vsx_extract && unzip -o "$vsix" > /dev/null 2>&1)
    cp -r /tmp/vsx_extract/extension "$target"
    rm -rf /tmp/vsx_extract
    echo "  installed: $id"
}

if [ -f "$WS/.devcontainer/trszog.vsix" ]; then
    install_vsix "$WS/.devcontainer/trszog.vsix" "maziac.dezog"
else
    echo "ERROR: trszog.vsix not found"
fi

echo "=== Installing Z80 Assembly highlighting ==="
if [ -f "$WS/.devcontainer/z80asm.vsix" ]; then
    install_vsix "$WS/.devcontainer/z80asm.vsix" "local.z80asm"
fi

echo ""
echo "=== Building emulator ==="
bash "$WS/.devcontainer/scripts/setup.sh"

echo ""
echo "=== Running end-to-end test ==="
python3 "$WS/.devcontainer/scripts/e2e_test.py" || {
    echo ""
    echo "WARNING: E2E test failed. The debug chain may not work."
    echo "         You can re-run manually: python3 $WS/.devcontainer/scripts/e2e_test.py"
}

echo ""
echo "=== Setup complete ==="
echo "  Start the machine: bash $WS/.devcontainer/scripts/start_trs80.sh"
echo "  Then press F5 in VS Code to attach the debugger."
