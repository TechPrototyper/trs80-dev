#!/bin/bash
# TRS-80 Dev — setup: clone trs80-rev-z, build the headless emulator,
# copy the debug bridge, set up the workspace.
set -e

echo "=== TRS-80 Dev: setting up environment ==="

# --- Clone the RTL + emulator source (read-only reference) ---
if [ ! -d /opt/trs80-rev-z ]; then
    echo "Cloning trs80-rev-z..."
    git clone --depth 1 https://github.com/TechPrototyper/trs80-rev-z.git /opt/trs80-rev-z
fi

# --- Build the headless Verilator emulator ---
echo "Building emulator (Verilator, ~5 min)..."
cd /opt/trs80-rev-z/sim/emu
export CPLUS_INCLUDE_PATH="/usr/local/include:${CPLUS_INCLUDE_PATH}"
export LIBRARY_PATH="/usr/local/lib:${LIBRARY_PATH}"
make clean 2>/dev/null || true
make -j"$(nproc)" 2>&1 | tail -5
echo "Emulator built: $(ls -la build/emu/Vm1_core | awk '{print $5}') bytes"

# --- Copy the debug bridge to the workspace ---
cp /opt/trs80-rev-z/tools/trszog_bridge.py /workspace/tools/ 2>/dev/null || {
    mkdir -p /workspace/tools
    cp /opt/trs80-rev-z/tools/trszog_bridge.py /workspace/tools/
}

# --- ROM: use the one from the repo if present, else prompt ---
if [ ! -f /workspace/roms/level2.hex ]; then
    mkdir -p /workspace/roms
    if [ -f /opt/trs80-rev-z/roms/level2.hex ]; then
        cp /opt/trs80-rev-z/roms/level2.hex /workspace/roms/level2.hex
        echo "ROM copied from trs80-rev-z."
    else
        echo ""
        echo "WARNING: No ROM found. Place your Level II image at:"
        echo "  /workspace/roms/level2.hex"
        echo "(see https://github.com/TechPrototyper/trs80-rev-z/blob/main/roms/README.md)"
    fi
fi

# --- Create a starter project if the workspace is empty ---
if [ ! -f /workspace/hello.asm ]; then
    cat > /workspace/hello.asm << 'ASM'
; TRS-80 Model I — Hello World (Level II BASIC screen)
; Assemble with: zmac -j hello.asm   (produces zout/hello.cmd + zout/hello.bds)

        ORG     5500H

START:  LD      A,0
        OUT     (FFH),A          ; text mode

        LD      DE,MSG
        LD      HL,40H           ; row 0, col 0 (screen base)
PRT:    LD      A,(DE)
        CP      0
        ZR      DONE
        LD      (HL),A
        INC     HL
        INC     DE
        JR      PRT
DONE:   HALT                    ; stop here for debugging

MSG:    DB      "HELLO, TRS-80!",$D,$A,0
        END     START
ASM
    echo "Created starter: hello.asm"
fi

echo ""
echo "=== Setup complete ==="
echo "Workspace: /workspace"
echo "  hello.asm       — starter Z80 program"
echo "  roms/level2.hex — Level II ROM"
echo "  tools/trszog_bridge.py — debug bridge"
echo ""
echo "Next: assemble with zmac, then F5 (launch config: TRS-80 Rev Z)"
