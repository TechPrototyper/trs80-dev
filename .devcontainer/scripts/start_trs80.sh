#!/bin/bash
# Start the headless TRS-80 with debug link on TCP 5555.
set -e

ROM="/workspace/roms/level2.hex"
if [ ! -f "$ROM" ]; then
    echo "ERROR: ROM not found at $ROM"
    echo "Place your Level II image there (12288 bytes, \$readmemh hex format)."
    exit 1
fi

# Collect .dmk files from /workspace/disks/ as drives 0-3
DISKS=""
n=0
for dmk in /workspace/disks/*.dmk; do
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
