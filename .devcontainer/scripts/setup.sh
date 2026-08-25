#!/bin/bash
# TRS-80 Dev — setup. 4 steps, no surprises.
set -e

echo "=== TRS-80 Dev: setup ==="

# [1] Clone trs80-rev-z (RTL source + emulator)
if [ ! -d /opt/trs80-rev-z ]; then
    echo "[1/4] Cloning trs80-rev-z..."
    sudo git clone --depth 1 https://github.com/TechPrototyper/trs80-rev-z.git /opt/trs80-rev-z
    sudo chown -R "$(id -u):$(id -g)" /opt/trs80-rev-z
else
    echo "[1/4] trs80-rev-z present."
fi

# [2] Build the headless Verilator emulator
echo "[2/4] Building emulator (~3 min)..."

# Ensure verilator_bin exists (CMake install may miss it)
if ! command -v verilator_bin &>/dev/null; then
    echo "      Fixing missing verilator_bin..."
    sudo bash -c '
        git clone --depth 1 --branch v5.026 https://github.com/verilator/verilator.git /tmp/vfix
        cd /tmp/vfix
        cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local \
            -DFLEX_EXECUTABLE=/usr/bin/flex -DFLEX_INCLUDE_DIR=/usr/include
        cmake --build build -j$(nproc)
        cp build/src/verilator /usr/local/bin/verilator_bin
        chmod +x /usr/local/bin/verilator_bin
        rm -rf /tmp/vfix
    '
fi

EMU_DIR=/opt/trs80-rev-z/sim/emu
RTL=/opt/trs80-rev-z/rtl
BUILD=$EMU_DIR/build/emu

rm -rf $EMU_DIR/build
mkdir -p $BUILD
cd $BUILD

# Generate Verilated C++ from RTL
verilator --cc -Wall +define+TV80_REFRESH \
    -GFONT_HEX="\"$RTL/mcm6670_cg1.hex\"" -O2 \
    --Mdir . --top-module m1_core \
    $RTL/m1_core.v $RTL/m1_video_timing.v $RTL/m1_cpu_clock.v \
    $RTL/m1_video_gen.v $RTL/m1_vram.v $RTL/m1_addr_decode.v \
    $RTL/vendor/tv80/tv80.vlt $RTL/m1_cpu.v $RTL/m1_rom.v $RTL/m1_ram.v \
    $RTL/m1_ei_ram.v $RTL/m1_ei.v $RTL/m1_fdc.v $RTL/m1_drives.v \
    $RTL/m1_debug.v $RTL/vendor/tv80/tv80_core.v $RTL/vendor/tv80/tv80_alu.v \
    $RTL/vendor/tv80/tv80_mcode.v $RTL/vendor/tv80/tv80_reg.v \
    $RTL/m1_io.v $RTL/m1_keyboard.v \
    -o Vm1_core 2>&1 | tail -3

# Compile Verilator library objects (C++20 for coroutines)
for f in /usr/local/include/verilated.cpp /usr/local/include/verilated_dpi.cpp \
         /usr/local/include/verilated_threads.cpp /usr/local/include/verilated_timing.cpp \
         /usr/local/include/verilated_random.cpp /usr/local/include/verilated_vcd_c.cpp \
         /usr/local/include/verilated_vpi.cpp /usr/local/include/verilated_fst_c.cpp \
         /usr/local/include/verilated_save.cpp /usr/local/include/verilated_profiler.cpp \
         /usr/local/include/verilated_cov.cpp; do
    g++ -O3 -std=c++20 -I/usr/local/include -I/usr/local/include/vltstd \
        -c -o $(basename $f .cpp).o $f
done

# Compile model objects
for f in Vm1_core*.cpp; do
    g++ -O2 -std=c++17 -I. -I/usr/local/include -I/usr/local/include/vltstd \
        -c -o ${f%.cpp}.o $f
done

# Compile user objects (SDL2 display, keyboard, disk, audio)
for f in $EMU_DIR/main.cpp $EMU_DIR/emu_disk.cpp $EMU_DIR/emu_cass.cpp \
         $EMU_DIR/emu_audio.cpp $EMU_DIR/emu_keyboard.cpp $EMU_DIR/emu_display.cpp; do
    g++ -O2 -std=c++17 -I. -I/usr/include/SDL2 \
        -c -o $(basename $f .cpp).o $f
done

# Link
g++ -O2 -o Vm1_core *.o -lSDL2 -lstdc++ -lm -lpthread -lz

test -x $BUILD/Vm1_core && echo "      OK ($(du -h $BUILD/Vm1_core | cut -f1))"

# [3] Install debug bridge into workspace
echo "[3/4] Installing debug bridge..."
mkdir -p /workspaces/trs80-dev/tools
cp /opt/trs80-rev-z/tools/trszog_bridge.py /workspaces/trs80-dev/tools/

# [4] ROM: prefer workspace copy, fall back to image-baked copy
echo "[4/4] Setting up ROM..."
mkdir -p /workspaces/trs80-dev/roms
if [ -f /workspaces/trs80-dev/roms/level2.hex ]; then
    echo "      OK: workspace ROM ($(wc -c < /workspaces/trs80-dev/roms/level2.hex) bytes)"
elif [ -f /opt/roms/level2.hex ]; then
    cp /opt/roms/level2.hex /workspaces/trs80-dev/roms/level2.hex
    echo "      OK: image ROM copied"
else
    echo "      WARNING: No ROM found. Machine will not start."
fi

echo ""
echo "=== Done. Start with: bash .devcontainer/scripts/start_trs80.sh ==="
