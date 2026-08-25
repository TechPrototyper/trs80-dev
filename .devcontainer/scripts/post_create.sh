#!/bin/bash
# Post-create: full setup (runs once when codespace is first opened).
# Installs toolchain, builds emulator, installs debugger extension, runs E2E test.
set -e

WS="/workspaces/trs80-dev"
EXT_DIR="$HOME/.vscode-remote/extensions"
mkdir -p "$EXT_DIR"

echo "=========================================="
echo " TRS-80 Dev Environment — Initial Setup"
echo "=========================================="

# [1] System packages
if ! command -v verilator &>/dev/null; then
    echo ""
    echo "[1/6] Installing system packages + Verilator (~5 min)..."
    sudo apt-get update && sudo apt-get install -y --no-install-recommends \
        build-essential git make g++ gcc bison flex libfl-dev cmake \
        python3-pip ca-certificates libsdl2-dev zlib1g-dev unzip
    sudo pip3 install --break-system-packages pyserial

    # Verilator v5.026
    git clone --depth 1 --branch v5.026 https://github.com/verilator/verilator.git /tmp/vsrc
    cd /tmp/vsrc
    cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DFLEX_EXECUTABLE=/usr/bin/flex -DFLEX_INCLUDE_DIR=/usr/include
    cmake --build build -j"$(nproc)"
    sudo cp build/src/verilator /usr/local/bin/verilator_bin
    sudo chmod +x /usr/local/bin/verilator_bin
    cmake --install build
    rm -rf /tmp/vsrc
    sudo ldconfig
    echo "      Verilator $(verilator --version | head -1)"
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

# [3] trszog debugger extension
if [ ! -f "$EXT_DIR/maziac.dezog/package.json" ]; then
    echo ""
    echo "[3/6] Installing trszog debugger extension..."
    python3 -c "import urllib.request; urllib.request.urlretrieve('https://github.com/TechPrototyper/trszog/releases/download/v3.7.4-rc1-trs80.1/dezog-3.7.4-rc1-trs80.1.vsix', '/tmp/trz.vsix')"
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/trz.vsix').extractall('/tmp/trz_ext')"
    mkdir -p "$EXT_DIR/maziac.dezog"
    cp -r /tmp/trz_ext/extension/* "$EXT_DIR/maziac.dezog/"
    rm -rf /tmp/trz_ext /tmp/trz.vsix
    echo "      trszog installed."
else
    echo "[3/6] trszog extension already present."
fi

# Z80 syntax highlighting
if [ ! -f "$EXT_DIR/local.z80asm/package.json" ]; then
    python3 -c "import zipfile; zipfile.ZipFile('$WS/.devcontainer/z80asm.vsix').extractall('/tmp/z80_ext')"
    mkdir -p "$EXT_DIR/local.z80asm"
    cp -r /tmp/z80_ext/extension/* "$EXT_DIR/local.z80asm/"
    rm -rf /tmp/z80_ext
    echo "      z80asm highlighting installed."
fi

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
