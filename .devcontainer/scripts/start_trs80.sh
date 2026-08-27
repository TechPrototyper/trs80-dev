#!/bin/bash
# Start the headless TRS-80 emulator with the debug link on TCP 5555.
#
#   emulator  --debug-tcp=5555 ──(binary v0)──►  [trszog starts the bridge on F5]
#
# The bridge is NOT started here: with transport.autoStart in launch.json,
# trszog spawns tools/trszog_bridge.py itself when you press F5 and connects
# to this emulator's debug link. Starting a second bridge here would just
# fight over port 49152.
set -e

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

# Headless container: no audio device (the emulator runs --no-sound anyway).
# Video is provided by Xvfb below — do NOT force the dummy video driver, or
# SDL can't create the accelerated renderer the emulator asks for.
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-dummy}"

WS="$(cd "$(dirname "$0")/../.." && pwd)"     # /workspaces/trs80-dev
EMU="/opt/trs80-rev-z/sim/emu/build/emu/Vm1_core"

# Free the debug port from any previous run.
if command -v fuser &>/dev/null; then fuser -k 5555/tcp 2>/dev/null || true; fi
sleep 1

# ROM (workspace copy is authoritative; fall back to the image-baked one).
ROM=""
for cand in "$WS/roms/level2.hex" /opt/trs80-rev-z/roms/level2.hex; do
    [ -f "$cand" ] && { ROM="$cand"; break; }
done
if [ -z "$ROM" ]; then
    echo "ERROR: No ROM found. Place your Level II ROM at roms/level2.hex (see roms/README.md)."
    exit 1
fi

# Any .dmk in disks/ becomes --disk0..3 (drives 0-3 only).
DISKS=""; n=0
for dmk in "$WS"/disks/*.dmk; do
    [ -f "$dmk" ] || continue
    [ "$n" -gt 3 ] && break
    DISKS="$DISKS --disk$n=$dmk"; n=$((n+1))
done

echo "Starting TRS-80 Rev Z (headless, debug-tcp=5555)..."
echo "ROM:   $ROM"
echo "Disks: ${DISKS:-none}"

# Run under a virtual X display (Xvfb) so SDL can create its renderer with
# no GPU/display server. xvfb-run picks a free display and tears it down on exit.
exec xvfb-run -a -s "-screen 0 1024x768x24" \
    "$EMU" \
    --rom="$ROM" \
    --hidden \
    --volume=0 \
    --no-sound \
    --debug-tcp=5555 \
    --throttle=1.0 \
    $DISKS
