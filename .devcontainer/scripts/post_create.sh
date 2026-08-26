#!/bin/bash
# Post-create: fast + deterministic. All heavy lifting already happened at
# image-build time (Dockerfile): toolchain, Verilator, zmac, the built
# emulator in /opt/trs80-rev-z, and the staged trszog extension.
#
# This step only wires those into the workspace + user profile.
set -euo pipefail

WS="$(pwd)"                       # /workspaces/trs80-dev
EXT_DIR="$HOME/.vscode-remote/extensions"

echo "=========================================="
echo " TRS-80 Dev — wiring up the workspace"
echo "=========================================="

# --- [1] Debug bridge into the workspace (launch.json points here) ---------
mkdir -p "$WS/tools"
cp /opt/trs80-rev-z/tools/trszog_bridge.py "$WS/tools/trszog_bridge.py"
cp /opt/trs80-rev-z/tools/emu_screen_dump.py "$WS/tools/emu_screen_dump.py" 2>/dev/null || true
echo "[1/3] Bridge installed: tools/trszog_bridge.py"

# --- [2] ROM (the workspace copy is authoritative; fall back to /opt) ------
mkdir -p "$WS/roms"
if [ ! -f "$WS/roms/level2.hex" ] && [ -f /opt/trs80-rev-z/roms/level2.hex ]; then
    cp /opt/trs80-rev-z/roms/level2.hex "$WS/roms/level2.hex"
fi
if [ -f "$WS/roms/level2.hex" ]; then
    echo "[2/3] ROM present: roms/level2.hex ($(wc -c < "$WS/roms/level2.hex") bytes)"
else
    echo "[2/3] WARNING: no ROM at roms/level2.hex — the machine will not start."
    echo "      See roms/README.md for provenance."
fi

# --- [3] trszog extension into the codespace profile -----------------------
# Not on the Marketplace/OpenVSX, so it must be side-loaded. We extract the
# staged copy into the profile and record it in extensions.json (the file the
# VS Code server reads to know which extensions are installed).
mkdir -p "$EXT_DIR"
DEST="$EXT_DIR/techprototyper.dezog-3.7.4-rc1-trs80.1"
# Always overwrite. Codespaces persists ~/.vscode-remote across rebuilds, and
# the trszog version string does not change between builds — so a stale copy
# (e.g. an older build without the revz remote) would otherwise survive forever.
rm -rf "$EXT_DIR/techprototyper.dezog"* "$EXT_DIR/maziac.dezog"* 2>/dev/null || true
mkdir -p "$DEST"
cp -r /opt/trszog-ext/extension/* "$DEST/"
# Sanity: the installed build must actually wire the revz remote.
if grep -q 'case"revz"' "$DEST/out/extension.js" 2>/dev/null; then
    echo "      trszog build includes the revz remote."
else
    echo "      WARNING: installed trszog does NOT contain revz — stale image?"
fi

python3 - "$EXT_DIR" "$DEST" << 'PYEOF'
import json, os, sys, uuid
ext_dir, dest = sys.argv[1], sys.argv[2]
p = os.path.join(ext_dir, "extensions.json")
try:
    exts = json.load(open(p))
except Exception:
    exts = []
exts = [e for e in exts if "dezog" not in e.get("identifier", {}).get("id", "").lower()]
exts.append({
    "identifier": {"id": "techprototyper.dezog", "uuid": str(uuid.uuid4())},
    "version": "3.7.4-rc1-trs80.1",
    "location": {"$mid": 1, "path": dest, "scheme": "file",
                 "fsPath": dest, "external": "file://" + dest},
    "relativeLocation": os.path.basename(dest),
    "metadata": {"isApplicationScoped": False, "isMachineScoped": True,
                 "isBuiltin": False, "installedTimestamp": 1787690564000,
                 "source": "vsix", "pinned": True, "id": str(uuid.uuid4()),
                 "publisherId": "TechPrototyper", "publisherDisplayName": "TechPrototyper",
                 "targetPlatform": "undefined", "updated": False, "private": False,
                 "isPreReleaseVersion": False, "hasPreReleaseVersion": False},
})
json.dump(exts, open(p, "w"), indent=2)
print(f"[3/3] trszog registered ({len(exts)} extension(s) in profile).")
PYEOF

echo ""
echo "=========================================="
echo " READY"
echo "   • The machine auto-starts on folder open (Task: TRS-80: Start Machine)."
echo "   • Assemble: Terminal → zmac -j space_invaders.asm   (or the Assemble task)."
echo "   • Debug:    press F5 → 'TRS-80 (attach)'."
echo ""
echo " If F5 does not list a TRS-80 debugger, the extension side-load did not"
echo " take. Recover in one line:  code --install-extension /opt/trszog.vsix"
echo " then reload the window (Ctrl/Cmd-Shift-P → 'Reload Window')."
echo "=========================================="
