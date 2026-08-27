#!/bin/bash
# Post-create: fast + deterministic. All heavy lifting already happened at
# image-build time (Dockerfile): toolchain, Verilator, zmac, the built
# emulator in /opt/trs80-rev-z, and the staged trszog VSIX (/opt/trszog.vsix).
#
# This step only wires workspace files. The trszog extension itself is
# installed by postAttachCommand (`code --install-extension`), because the
# `code` CLI only exists once a VS Code client attaches — NOT here.
set -euo pipefail

WS="$(pwd)"                       # /workspaces/trs80-dev

echo "=========================================="
echo " TRS-80 Dev — wiring up the workspace"
echo "=========================================="

# --- [1] Debug bridge into the workspace (launch.json points here) ---------
mkdir -p "$WS/tools"
cp /opt/trs80-rev-z/tools/trszog_bridge.py "$WS/tools/trszog_bridge.py"
cp /opt/trs80-rev-z/tools/emu_screen_dump.py "$WS/tools/emu_screen_dump.py" 2>/dev/null || true
echo "[1/2] Bridge installed: tools/trszog_bridge.py"

# --- [2] ROM (the workspace copy is authoritative; fall back to /opt) ------
mkdir -p "$WS/roms"
if [ ! -f "$WS/roms/level2.hex" ] && [ -f /opt/trs80-rev-z/roms/level2.hex ]; then
    cp /opt/trs80-rev-z/roms/level2.hex "$WS/roms/level2.hex"
fi
if [ -f "$WS/roms/level2.hex" ]; then
    echo "[2/2] ROM present: roms/level2.hex ($(wc -c < "$WS/roms/level2.hex") bytes)"
else
    echo "[2/2] WARNING: no ROM at roms/level2.hex — the machine will not start."
    echo "      See roms/README.md for provenance."
fi

echo ""
echo "=========================================="
echo " READY"
echo "   • The machine auto-starts on folder open (Task: TRS-80: Start Machine)."
echo "   • Assemble: Terminal → zmac -j space_invaders.asm   (or the Assemble task)."
echo "   • Debug:    press F5 → 'TRS-80 (attach)'."
echo ""
echo " The trszog debugger installs itself when VS Code attaches"
echo " (postAttachCommand). If F5 lists no TRS-80 debugger, run:"
echo "   code --install-extension /opt/trszog.vsix --force"
echo " then reload the window (Ctrl/Cmd-Shift-P → 'Reload Window')."
echo "=========================================="
