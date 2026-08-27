#!/bin/bash
# Start the headless TRS-80 Rev Z machine, configured by trs80revz.json.
#
#   emulator  --debug-tcp=<port> ──(binary v0)──►  [trszog starts the bridge on F5]
#
# Machine features (memory/EI config, Percom doubler, disks, cassette, sound,
# debug dongle, throttle) come from trs80revz.json in the workspace root —
# JSON with comments. Without the file, sensible defaults apply (48K machine,
# any disks/*.dmk mounted, debug link on :5555, throttle 1.0).
#
# The bridge is NOT started here: with transport.autoStart in launch.json,
# trszog spawns tools/trszog_bridge.py itself when you press F5.
set -e

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

# Headless container: no audio device. Video is provided by Xvfb below — do
# NOT force the dummy video driver, or SDL can't create its renderer.
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-dummy}"

WS="$(cd "$(dirname "$0")/../.." && pwd)"     # /workspaces/trs80-dev
EMU="/opt/trs80-rev-z/sim/emu/build/emu/Vm1_core"

# ROM (workspace copy is authoritative; fall back to the image-baked one).
ROM=""
for cand in "$WS/roms/level2.hex" /opt/trs80-rev-z/roms/level2.hex; do
    [ -f "$cand" ] && { ROM="$cand"; break; }
done
if [ -z "$ROM" ]; then
    echo "ERROR: No ROM found. Place your Level II ROM at roms/level2.hex (see roms/README.md)."
    exit 1
fi

# --- Build the argument list from trs80revz.json (JSONC) --------------------
ARGS=$(python3 - "$WS" <<'PYEOF'
import json, sys, os, glob

ws = sys.argv[1]
cfgfile = os.path.join(ws, "trs80revz.json")

def load_jsonc(path):
    s = open(path, encoding="utf-8").read()
    # strip // and /* */ comments outside of strings
    out, i, n, instr = [], 0, len(s), False
    while i < n:
        c = s[i]
        if instr:
            out.append(c)
            if c == "\\" and i + 1 < n: out.append(s[i+1]); i += 1
            elif c == '"': instr = False
        elif c == '"': instr = True; out.append(c)
        elif c == "/" and i + 1 < n and s[i+1] == "/":
            while i < n and s[i] != "\n": i += 1
            continue
        elif c == "/" and i + 1 < n and s[i+1] == "*":
            i += 2
            while i + 1 < n and not (s[i] == "*" and s[i+1] == "/"): i += 1
            i += 1
        else: out.append(c)
        i += 1
    return json.loads("".join(out))

cfg = {}
if os.path.exists(cfgfile):
    try:
        cfg = load_jsonc(cfgfile)
        print("config: trs80revz.json", file=sys.stderr)
    except Exception as e:
        print(f"ERROR: trs80revz.json is not valid JSONC: {e}", file=sys.stderr)
        sys.exit(1)
else:
    print("config: defaults (no trs80revz.json)", file=sys.stderr)

def get(path, default):
    node = cfg
    for k in path.split("."):
        if not isinstance(node, dict) or k not in node: return default
        node = node[k]
    return node if node is not None else default

args = []

mem = str(get("machine.memory", "48k")).lower()
if   mem == "16k": args.append("--no-ei")
elif mem == "32k": args.append("--ei16")
elif mem == "48k": args.append("--ei32")
else:
    print(f"ERROR: machine.memory must be 16k/32k/48k, not '{mem}'", file=sys.stderr)
    sys.exit(1)

if not get("machine.percomDoubler", True):
    args.append("--no-percom")

disks = get("media.disks", None)
wp    = get("media.writeProtect", [False]*4)
if disks is None:                      # default: mount whatever is in disks/
    disks = sorted(glob.glob(os.path.join(ws, "disks", "*.dmk")))[:4]
for i, d in enumerate((disks or [])[:4]):
    if not d: continue
    p = d if os.path.isabs(d) else os.path.join(ws, d)
    if not os.path.exists(p):
        print(f"ERROR: disk image not found: {d}", file=sys.stderr)
        sys.exit(1)
    args.append(f"--disk{i}={p}")
    if i < len(wp) and wp[i]: args.append(f"--wp{i}")

cas = get("media.cassette", None)
if cas:
    p = cas if os.path.isabs(cas) else os.path.join(ws, cas)
    if not os.path.exists(p):
        print(f"ERROR: cassette image not found: {cas}", file=sys.stderr)
        sys.exit(1)
    args.append(f"--cas={p}")
    args.append(f"--cas-baud={int(get('media.cassetteBaud', 500))}")

if get("sound.enabled", False):
    args.append(f"--volume={int(get('sound.volume', 60))}")
else:
    args += ["--no-sound", "--volume=0"]

if get("debugDongle.enabled", True):
    args.append(f"--debug-tcp={int(get('debugDongle.port', 5555))}")
else:
    print("note: debugDongle.enabled=false - machine starts WITHOUT a debug "
          "link; rev-z debug targets will refuse to attach.", file=sys.stderr)

args.append(f"--throttle={float(get('throttle', 1.0))}")
print(" ".join(args))
PYEOF
) || { echo "Machine NOT started — fix trs80revz.json first."; exit 1; }

# Free the debug port from any previous run.
PORT=$(printf '%s\n' $ARGS | sed -n 's/--debug-tcp=//p')
if [ -n "$PORT" ] && command -v fuser &>/dev/null; then
    fuser -k "$PORT/tcp" 2>/dev/null || true
    sleep 1
fi

echo "Starting TRS-80 Rev Z (headless)..."
echo "ROM:  $ROM"
echo "Args: $ARGS"

# Run under a virtual X display (Xvfb) so SDL can create its renderer with
# no GPU/display server. xvfb-run picks a free display and tears it down.
exec xvfb-run -a -s "-screen 0 1024x768x24" \
    "$EMU" --rom="$ROM" --hidden $ARGS
