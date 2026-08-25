#!/bin/bash
# Start the headless TRS-80 with DAP debug bridge.
# Emulator → tcp:5555 → dap_bridge.py → tcp:49152 (VS Code)
set -e

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

# Kill any previous instances
for port in 5555 49152; do
    if command -v fuser &>/dev/null; then
        fuser -k ${port}/tcp 2>/dev/null || true
    elif command -v lsof &>/dev/null; then
        lsof -ti:${port} | xargs kill 2>/dev/null || true
    fi
done
sleep 0.5

# Find ROM: workspace first, then image-baked copy
ROM=""
for cand in /workspaces/trs80-dev/roms/level2.hex /opt/roms/level2.hex; do
    if [ -f "$cand" ]; then ROM="$cand"; break; fi
done

if [ -z "$ROM" ]; then
    echo "ERROR: No ROM found."
    echo "Looked in: /workspaces/trs80-dev/roms/level2.hex, /opt/roms/level2.hex"
    exit 1
fi

# Collect .dmk files from workspace/disks/ as drives 0-3
DISKS=""
n=0
for dmk in /workspaces/trs80-dev/disks/*.dmk; do
    [ -f "$dmk" ] || continue
    DISKS="$DISKS --disk$n=$dmk"
    n=$((n+1))
done

echo "Starting TRS-80 Rev Z (headless, DAP bridge on :49152)..."
echo "ROM:   $ROM"
echo "Disks: ${DISKS:-none}"

# Start the emulator in background
/opt/trs80-rev-z/sim/emu/build/emu/Vm1_core \
    --rom="$ROM" \
    --hidden \
    --volume=0 \
    --no-sound \
    --debug-tcp=5555 \
    --throttle=0.7 \
    $DISKS &
EMU_PID=$!
sleep 2

# Start the DAP bridge (translates VS Code DAP → binary debug protocol)
DAP_BRIDGE="/workspaces/trs80-dev/tools/dap_bridge.py"
if [ ! -f "$DAP_BRIDGE" ]; then
    DAP_BRIDGE="/opt/trs80-rev-z/tools/dap_bridge.py"
fi
python3 "$DAP_BRIDGE" --serial tcp:5555 --port 49152 &
DAP_PID=$!
sleep 1

echo "Emulator PID: $EMU_PID"
echo "DAP bridge PID: $DAP_PID (port 49152)"
echo "Press F5 to attach the debugger."

# Wait for either process
wait $EMU_PID
