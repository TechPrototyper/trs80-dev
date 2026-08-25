#!/bin/bash
# Post-create: full setup (runs once when codespace is first opened).
# Installs toolchain, builds emulator, installs debugger extension, runs E2E test.
set -eo pipefail

WS="/workspaces/trs80-dev"
EXT_DIR="$HOME/.vscode-remote/extensions"
mkdir -p "$EXT_DIR"

echo "=========================================="
echo " TRS-80 Dev Environment — Initial Setup"
echo "=========================================="

# [1] System packages + Verilator
if ! command -v verilator_bin &>/dev/null; then
    echo ""
    echo "[1/6] Installing system packages + Verilator (~5 min)..."
    sudo apt-get update && sudo apt-get install -y --no-install-recommends \
        build-essential git make g++ gcc bison flex libfl-dev cmake \
        python3-pip ca-certificates libsdl2-dev zlib1g-dev unzip nodejs npm
    sudo pip3 install --break-system-packages pyserial

    # Verilator v5.026
    sudo bash -c '
        set -e
        git clone --depth 1 --branch v5.026 https://github.com/verilator/verilator.git /tmp/vsrc
        cd /tmp/vsrc
        cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local \
            -DFLEX_EXECUTABLE=/usr/bin/flex -DFLEX_INCLUDE_DIR=/usr/include
        cmake --build build -j$(nproc)
        cp build/src/verilator /usr/local/bin/verilator_bin
        chmod +x /usr/local/bin/verilator_bin
        cmake --install build || true
        cp -r include/* /usr/local/include/
        chown -R vscode:vscode /usr/local/include/
        chmod -R a+r /usr/local/include/
        rm -rf /tmp/vsrc
    '
    echo "      Verilator: $(/usr/local/bin/verilator_bin --version 2>&1 | head -1)"
else
    echo "[1/6] Verilator already present."
fi

# [2] zmac
if ! command -v zmac &>/dev/null; then
    echo ""
    echo "[2/6] Building zmac..."
    git clone --depth 1 https://github.com/gp48k/zmac.git /tmp/zsrc
    cd /tmp/zsrc/src && make
    sudo cp zmac /usr/local/bin/
    rm -rf /tmp/zsrc
    echo "      zmac ready."
else
    echo "[2/6] zmac already present."
fi

# [3] Install VS Code extensions (minimal DAP adapter + z80 syntax)
echo ""
echo "[3/6] Installing VS Code extensions..."
# In GitHub Codespaces, the 'code' CLI is NOT available during postCreate.
# We place extensions directly and register them in extensions.json.
# The minimal-dezog extension has ZERO dependencies — it just tells VS Code
# to connect to our DAP bridge on TCP port 49152.

# Minimal DeZog debug adapter (2KB, no deps)
EXT_NAME="techprototyper.dezog"
if [ ! -d "$EXT_DIR/$EXT_NAME" ]; then
    python3 -c "import zipfile; zipfile.ZipFile('$WS/.devcontainer/minimal-dezog.vsix').extractall('/tmp/dz_vsix')"
    mkdir -p "$EXT_DIR/$EXT_NAME"
    cp -r /tmp/dz_vsix/extension/* "$EXT_DIR/$EXT_NAME/"
    rm -rf /tmp/dz_vsix
    echo "      dezog debug adapter installed (minimal, no deps)."
fi

# Z80 syntax highlighting
EXT_NAME2="local.z80asm"
if [ ! -d "$EXT_DIR/$EXT_NAME2" ]; then
    python3 -c "import zipfile; zipfile.ZipFile('$WS/.devcontainer/z80asm.vsix').extractall('/tmp/z80_vsix')"
    mkdir -p "$EXT_DIR/$EXT_NAME2"
    cp -r /tmp/z80_vsix/extension/* "$EXT_DIR/$EXT_NAME2/"
    rm -rf /tmp/z80_vsix
    echo "      z80asm syntax highlighting installed."
fi

# Register both in extensions.json (VS Code reads this on startup)
python3 << 'PYEOF'
import json, os, uuid
ext_dir = os.path.expanduser('~/.vscode-remote/extensions')
p = os.path.join(ext_dir, 'extensions.json')
exts = json.load(open(p)) if os.path.exists(p) else []
existing = {e['identifier']['id'] for e in exts}
for name in ['techprototyper.dezog', 'local.z80asm']:
    if name not in existing:
        exts.append({
            'identifier': {'id': name, 'uuid': str(uuid.uuid4())},
            'version': '1.0.0',
            'location': {'$mid': 1, 'fsPath': os.path.join(ext_dir, name),
                         'external': f'file://{os.path.join(ext_dir, name)}',
                         'path': os.path.join(ext_dir, name), 'scheme': 'file'},
            'relativeLocation': name,
            'metadata': {
                'isApplicationScoped': False, 'isMachineScoped': True,
                'isBuiltin': False, 'installedTimestamp': 1787690564000,
                'source': 'marketplace', 'id': str(uuid.uuid4()),
                'publisherId': 'local', 'publisherDisplayName': name.split('.')[0],
                'targetPlatform': 'undefined', 'updated': False, 'private': False,
                'isPreReleaseVersion': False, 'hasPreReleaseVersion': False
            }
        })
# Remove any stale marketplace maziac.dezog entries
exts = [e for e in exts if 'maziac' not in e.get('identifier',{}).get('id','')]
json.dump(exts, open(p, 'w'), indent=2)
print(f'      {len(exts)} extensions registered in extensions.json')
PYEOF
# Also remove any marketplace copy on disk
rm -rf "$EXT_DIR/maziac.dezog" "$EXT_DIR/maziac.dezog-"* 2>/dev/null || true

# [4] Build the TRS-80 emulator
echo ""
echo "[4/6] Building TRS-80 emulator (~3 min)..."
bash "$WS/.devcontainer/scripts/setup.sh"

# [5] End-to-end test
echo ""
echo "[5/6] Running end-to-end test..."
python3 "$WS/.devcontainer/scripts/e2e_test.py" || {
    echo "WARNING: E2E test failed. Re-run: python3 $WS/.devcontainer/scripts/e2e_test.py"
}

# [6] Start the machine
echo ""
echo "[6/6] Starting TRS-80 in background..."
setsid bash "$WS/.devcontainer/scripts/start_trs80.sh" > /tmp/trs80.log 2>&1 &
disown 2>/dev/null || true
sleep 3
if pgrep -f 'Vm1_core.*debug-tcp' > /dev/null; then
    echo "      Machine running. Log: /tmp/trs80.log"
else
    echo "      WARNING: check /tmp/trs80.log"
fi

echo ""
echo "=========================================="
echo " READY — press F5 to attach the debugger"
echo "=========================================="
