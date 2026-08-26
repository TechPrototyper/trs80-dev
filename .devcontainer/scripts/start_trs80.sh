#!/bin/bash
# Start the headless TRS-80 emulator + trszog bridge.
# Emulator → tcp:5555 → trszog_bridge.py → tcp:49152 (VS Code / trszog)
set -e

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

WS="/workspaces/trs80-dev"
EMU="/opt/trs80-rev-z/sim/emu/build/emu/Vm1_core"
BRIDGE="/opt/trs80-rev-z/tools/trszog_bridge.py"

# Kill any previous instances holding ports 5555 or 49152
for port in 5555 49152; do
    if command -v fuser &>/dev/null; then
        fuser -k ${port}/tcp 2>/dev/null || true
    elif command -v lsof &>/dev/null; then
        lsof -ti:${port} | xargs kill 2>/dev/null || true
    fi
done
sleep 1

# Find ROM
ROM=""
for cand in "$WS/roms/level2.hex" /opt/roms/level2.hex; do
    if [ -f "$cand" ]; then ROM="$cand"; break; fi
done

if [ -z "$ROM" ]; then
    echo "ERROR: No ROM found."
    exit 1
fi

# Collect .dmk files
DISKS=""
n=0
for dmk in "$WS"/disks/*.dmk; do
    [ -f "$dmk" ] || continue
    DISKS="$DISKS --disk$n=$dmk"
    n=$((n+1))
done

echo "Starting TRS-80 Rev Z (headless, debug-tcp=5555)..."
echo "ROM:   $ROM"
echo "Disks: ${DISKS:-none}"

# Start emulator
"$EMU" \
    --rom="$ROM" \
    --hidden \
    --volume=0 \
    --no-sound \
    --debug-tcp=5555 \
    --throttle=0.7 \
    $DISKS &
EMU_PID=$!
sleep 3

# Start trszog bridge (speaks trszog JSON-RPC on 49152)
python3 "$BRIDGE" --serial tcp:5555 --baud 460800 --port 49152 &
BRIDGE_PID=$!
sleep 1

echo "Emulator PID: $EMU_PID"
echo "Bridge PID:   $BRIDGE_PID (port 49152)"
echo ""
echo "Press F5 to attach the debugger."
wait $EMU_PID
