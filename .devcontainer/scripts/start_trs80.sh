#!/bin/bash
# Start the headless TRS-80 with debug link on TCP 5555.
set -e

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

# Kill any previous instance holding port 5555
if command -v fuser &>/dev/null; then
    fuser -k 5555/tcp 2>/dev/null || true
elif command -v lsof &>/dev/null; then
    lsof -ti:5555 | xargs kill 2>/dev/null || true
else
    # Fallback: find and kill via /proc
    for pid in $(ls /proc/*/fd 2>/dev/null | grep -c socket || true); do :; done
fi
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

echo "Starting TRS-80 Rev Z (headless, debug-tcp=5555)..."
echo "ROM:   $ROM"
echo "Disks: ${DISKS:-none}"

exec /opt/trs80-rev-z/sim/emu/build/emu/Vm1_core \
    --rom="$ROM" \
    --hidden \
    --volume=0 \
    --no-sound \
    --debug-tcp=5555 \
    --throttle=0.7 \
    $DISKS
