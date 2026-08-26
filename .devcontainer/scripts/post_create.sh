#!/bin/bash
# Post-create: full setup (runs once when codespace is first opened).
# Installs toolchain, builds emulator, installs trszog debugger extension.
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
    echo "[1/5] Installing system packages + Verilator (~5 min)..."
    sudo apt-get update && sudo apt-get install -y --no-install-recommends \
        build-essential git make g++ gcc bison flex libfl-dev cmake \
        python3 python3-pip ca-certificates libsdl2-dev zlib1g-dev unzip nodejs npm
    sudo pip3 install --break-system-packages pyserial

    # Verilator v5.026 (CMake build)
    sudo bash -c '
        set -e
        ulimit -n 65536
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
    echo "[1/5] Verilator already present."
fi

# [2] zmac
if ! command -v zmac &>/dev/null; then
    echo ""
    echo "[2/5] Building zmac..."
    git clone --depth 1 https://github.com/gp48k/zmac.git /tmp/zsrc
    cd /tmp/zsrc/src && make
    sudo cp zmac /usr/local/bin/
    rm -rf /tmp/zsrc
    echo "      zmac ready."
else
    echo "[2/5] zmac already present."
fi

# [3] Clone trs80-rev-z + build emulator
echo ""
echo "[3/5] Cloning trs80-rev-z + building emulator (~3 min)..."
if [ ! -f /opt/trs80-rev-z/sim/emu/build/emu/Vm1_core ]; then
    sudo git clone --depth 1 https://github.com/TechPrototyper/trs80-rev-z.git /opt/trs80-rev-z
    sudo bash -c '
        set -e
        ulimit -n 65536
        cd /opt/trs80-rev-z/sim/emu
        mkdir -p build/emu
        # Verilate
        /usr/local/bin/verilator_bin --cc -Wall +define+TV80_REFRESH \
            -GFONT_HEX="\"/opt/trs80-rev-z/rtl/mcm6670_cg1.hex\"" \
            -O3 --Mdir build/emu --top-module m1_core \
            ../../rtl/m1_core.v ../../rtl/m1_video_timing.v ../../rtl/m1_cpu_clock.v \
            ../../rtl/m1_video_gen.v ../../rtl/m1_vram.v ../../rtl/m1_addr_decode.v \
            ../../rtl/vendor/tv80/tv80.vlt ../../rtl/m1_cpu.v ../../rtl/m1_rom.v \
            ../../rtl/m1_ram.v ../../rtl/m1_ei_ram.v ../../rtl/m1_ei.v \
            ../../rtl/m1_fdc.v ../../rtl/m1_drives.v ../../rtl/m1_debug.v \
            ../../rtl/vendor/tv80/tv80_core.v ../../rtl/vendor/tv80/tv80_alu.v \
            ../../rtl/vendor/tv80/tv80_mcode.v ../../rtl/vendor/tv80/tv80_reg.v \
            ../../rtl/m1_io.v ../../rtl/m1_keyboard.v
        # Compile core
        cd build/emu
        INC="-I/usr/include/SDL2 -I/usr/local/include -I."
        for f in Vm1_core.cpp Vm1_core__Syms.cpp \
                 Vm1_core___024root__DepSet_hc7cc691e__0.cpp \
                 Vm1_core___024root__DepSet_hc7cc691e__0__Slow.cpp \
                 Vm1_core___024root__DepSet_hc7cc691e__1.cpp \
                 Vm1_core___024root__DepSet_hff59c9dd__0.cpp \
                 Vm1_core___024root__DepSet_hff59c9dd__0__Slow.cpp \
                 Vm1_core___024root__Slow.cpp Vm1_core__ConstPool_0.cpp; do
            g++ -O2 -std=c++17 $INC -march=native -flto -c $f -o ${f%.cpp}.o
        done
        # Compile emulator C++
        cd ..
        INC2="-I/usr/include/SDL2 -I/usr/local/include -Ibuild/emu"
        for f in main.cpp emu_disk.cpp emu_cass.cpp emu_audio.cpp emu_keyboard.cpp emu_display.cpp; do
            g++ -O2 -std=c++17 $INC2 -march=native -flto -c $f -o build/emu/${f%.cpp}.o
        done
        # Compile verilated runtime
        g++ -O2 -std=c++17 -I/usr/local/include -c /usr/local/include/verilated.cpp -o /tmp/verilated.o
        g++ -O2 -std=c++17 -I/usr/local/include -c /usr/local/include/verilated_threads.cpp -o /tmp/verilated_threads.o
        # Link
        cd build/emu
        g++ -flto -o Vm1_core *.o /tmp/verilated.o /tmp/verilated_threads.o -lSDL2 -lpthread
        chmod 755 Vm1_core
    '
    echo "      Emulator built: /opt/trs80-rev-z/sim/emu/build/emu/Vm1_core"
else
    echo "      Emulator already built."
fi

# [4] Install trszog extension (download from GitHub Release)
echo ""
echo "[4/5] Installing trszog debugger extension..."
TRZ_EXT="$EXT_DIR/techprototyper.dezog"
if [ ! -f "$TRZ_EXT/out/extension.js" ]; then
    curl -L -o /tmp/trszog.vsix \
        "https://github.com/TechPrototyper/trs80-dev/releases/download/v1/trszog.vsix"
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/trszog.vsix').extractall('/tmp/trz_vsix')"
    mkdir -p "$TRZ_EXT"
    cp -r /tmp/trz_vsix/extension/* "$TRZ_EXT/"
    rm -rf /tmp/trz_vsix /tmp/trszog.vsix
    # CRITICAL: create wrapper so VS Code finds extension.js at root
    echo "module.exports = require('./out/extension.js');" > "$TRZ_EXT/extension.js"
    echo "      trszog installed ($(du -sh "$TRZ_EXT" | cut -f1))."
else
    echo "      trszog already installed."
fi

# Z80 syntax highlighting
if [ ! -f "$EXT_DIR/local.z80asm/package.json" ]; then
    python3 -c "import zipfile; zipfile.ZipFile('$WS/.devcontainer/z80asm.vsix').extractall('/tmp/z80_ext')"
    mkdir -p "$EXT_DIR/local.z80asm"
    cp -r /tmp/z80_ext/extension/* "$EXT_DIR/local.z80asm/"
    rm -rf /tmp/z80_ext
    echo "      z80asm highlighting installed."
fi

# Register extensions in extensions.json
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
exts = [e for e in exts if 'maziac' not in e.get('identifier',{}).get('id','')]
json.dump(exts, open(p, 'w'), indent=2)
print(f'      {len(exts)} extensions registered.')
PYEOF
rm -rf "$EXT_DIR/maziac.dezog" "$EXT_DIR/maziac.dezog-"* 2>/dev/null || true

# [5] Start the machine
echo ""
echo "[5/5] Starting TRS-80 in background..."
setsid bash "$WS/.devcontainer/scripts/start_trs80.sh" > /tmp/trs80.log 2>&1 &
disown 2>/dev/null || true
sleep 5
if pgrep -f 'Vm1_core.*debug-tcp' > /dev/null; then
    echo "      Machine running. Log: /tmp/trs80.log"
else
    echo "      WARNING: check /tmp/trs80.log"
fi

echo ""
echo "=========================================="
echo " READY — press F5 to attach the debugger"
echo "=========================================="
