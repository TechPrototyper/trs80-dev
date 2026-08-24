#!/bin/bash
# TRS-80 Dev — setup. 4 steps, no surprises.
set -e

echo "=== TRS-80 Dev: setup ==="

# [1] Clone trs80-rev-z (RTL source + emulator)
if [ ! -d /opt/trs80-rev-z ]; then
    echo "[1/4] Cloning trs80-rev-z..."
    git clone --depth 1 https://github.com/TechPrototyper/trs80-rev-z.git /opt/trs80-rev-z
else
    echo "[1/4] trs80-rev-z present."
fi

# [2] Build the headless Verilator emulator
echo "[2/4] Building emulator (~5 min)..."
cd /opt/trs80-rev-z/sim/emu
export CPLUS_INCLUDE_PATH="/usr/local/include:${CPLUS_INCLUDE_PATH}"
export LIBRARY_PATH="/usr/local/lib:${LIBRARY_PATH}"
make clean 2>/dev/null || true
make -j"$(nproc)" 2>&1 | tail -3
test -x build/emu/Vm1_core && echo "      OK"

# [3] Install debug bridge into workspace
echo "[3/4] Installing debug bridge..."
mkdir -p /workspace/tools
cp /opt/trs80-rev-z/tools/trszog_bridge.py /workspace/tools/

# [4] ROM: prefer workspace copy, fall back to image-baked copy
echo "[4/4] Setting up ROM..."
mkdir -p /workspace/roms
if [ -f /workspace/roms/level2.hex ]; then
    echo "      OK: workspace ROM ($(wc -c < /workspace/roms/level2.hex) bytes)"
elif [ -f /opt/roms/level2.hex ]; then
    cp /opt/roms/level2.hex /workspace/roms/level2.hex
    echo "      OK: image ROM copied ($(wc -c < /workspace/roms/level2.hex) bytes)"
else
    echo "      WARNING: No ROM found. Machine will not start."
fi

echo ""
echo "=== Done. Start with: bash .devcontainer/scripts/start_trs80.sh ==="
