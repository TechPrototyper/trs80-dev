#!/bin/bash
# TRS-80 Dev — setup: build the headless emulator from trs80-rev-z,
# copy the debug bridge. Clean, minimal, no surprises.
set -e

echo "=== TRS-80 Dev: setting up environment ==="

# --- Clone trs80-rev-z (the RTL source + emulator) ---
if [ ! -d /opt/trs80-rev-z ]; then
    echo "[1/4] Cloning trs80-rev-z..."
    git clone --depth 1 https://github.com/TechPrototyper/trs80-rev-z.git /opt/trs80-rev-z
else
    echo "[1/4] trs80-rev-z already present."
fi

# --- Build the headless Verilator emulator ---
echo "[2/4] Building emulator (Verilator, ~5 min)..."
cd /opt/trs80-rev-z/sim/emu
export CPLUS_INCLUDE_PATH="/usr/local/include:${CPLUS_INCLUDE_PATH}"
export LIBRARY_PATH="/usr/local/lib:${LIBRARY_PATH}"
make clean 2>/dev/null || true
make -j"$(nproc)" 2>&1 | tail -3
test -x build/emu/Vm1_core && echo "      OK: $(du -h build/emu/Vm1_core | cut -f1)"

# --- Copy the debug bridge into the workspace ---
echo "[3/4] Installing debug bridge..."
mkdir -p /workspace/tools
cp /opt/trs80-rev-z/tools/trszog_bridge.py /workspace/tools/

# --- ROM check (must be in the user's repo at roms/level2.hex) ---
echo "[4/4] Checking ROM..."
if [ -f /workspace/roms/level2.hex ]; then
    echo "      OK: roms/level2.hex ($(wc -c < /workspace/roms/level2.hex) bytes)"
else
    echo ""
    echo "  WARNING: No ROM found at /workspace/roms/level2.hex"
    echo "  The machine will not start until you provide one."
    echo "  See: https://github.com/TechPrototyper/trs80-rev-z/blob/main/roms/README.md"
    echo ""
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "  Machine binary : /opt/trs80-rev-z/sim/emu/build/emu/Vm1_core"
echo "  Debug bridge   : /workspace/tools/trszog_bridge.py"
echo "  Start command  : bash .devcontainer/scripts/start_trs80.sh"
echo ""
