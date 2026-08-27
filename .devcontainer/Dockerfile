FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# ---------------------------------------------------------------------------
# TRS-80 Dev — everything the codespace / local dev container needs, baked at
# image-build time. Multi-arch: linux/amd64 and linux/arm64 (Apple Silicon —
# Docker Desktop, Podman, or Apple's native `container` on macOS 26+).
#
# Fast path: a PREBUILT Verilator (oss-cad-suite) instead of compiling it from
# source. The emulator is built with PGO (train on a ROM boot, rebuild with
# the profile): +20-27 % wall clock, measured on EPYC and Apple M.
# ---------------------------------------------------------------------------
# trs80-rev-z @ main ea8bca2: gated CPU clock (ADR-0011), graceful SIGINT
#   shutdown (needed for PGO training), MARCH/PROF build knobs, 5.05x-ready
#   test suite. (rev-z ships NO ROM/disk by policy — trs80-dev provides them.)
ARG REVZ_REF=ea8bca2509407d8d483c779265980100ff876701
ARG OSS_CAD_TAG=2026-08-26
ARG OSS_CAD_STAMP=20260826
# amd64 | arm64 — set automatically by buildx.
ARG TARGETARCH

# --- [1] Toolchain + real SDL2 + a headless display ------------------------
#   The emulator unconditionally creates an ACCELERATED SDL renderer even in
#   --hidden mode, so it needs a real display with a GL backend. Xvfb + Mesa's
#   llvmpipe (software GL) provide exactly that with no GPU.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git make g++ flex bison python3 python3-pip ca-certificates unzip \
        libsdl2-dev xvfb libgl1-mesa-dri libglx-mesa0 xauth \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install --break-system-packages pyserial

# --- [2] Prebuilt Verilator via oss-cad-suite (no compilation) --------------
RUN OSS_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo linux-arm64 || echo linux-x64) \
    && cd /opt \
    && python3 -c "import urllib.request; urllib.request.urlretrieve('https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${OSS_CAD_TAG}/oss-cad-suite-${OSS_ARCH}-${OSS_CAD_STAMP}.tgz', '/tmp/oss.tgz')" \
    && tar xzf /tmp/oss.tgz && rm /tmp/oss.tgz \
    && /opt/oss-cad-suite/bin/verilator --version

# --- [3] zmac — Z-80 macro cross-assembler (George Phillips, CC0) -----------
RUN git clone --depth 1 https://github.com/gp48k/zmac.git /opt/zmac-src \
    && cd /opt/zmac-src/src && make \
    && cp zmac /usr/local/bin/ \
    && rm -rf /opt/zmac-src

# --- [4] trs80-rev-z + PGO-built emulator -----------------------------------
#   The ROM comes from THIS repo (trs80-dev may carry it; rev-z never does)
#   and stays in the image: it is the PGO training workload and the runtime
#   fallback post_create already looks for.
#   Plain `make` (no -j): the outer make must not pass a jobserver to
#   Verilator's own `--build -j 0`, or oss-cad-suite's make aborts.
COPY roms/level2.hex /tmp/level2.hex
RUN MARCH=$([ "$TARGETARCH" = "arm64" ] && echo armv8-a || echo x86-64-v3) \
    && git clone https://github.com/TechPrototyper/trs80-rev-z.git /opt/trs80-rev-z \
    && cd /opt/trs80-rev-z && git checkout ${REVZ_REF} \
    && mkdir -p roms && cp /tmp/level2.hex roms/level2.hex \
    && cd sim/emu \
    && bash -c "source /opt/oss-cad-suite/environment && make MARCH=$MARCH PROF='-fprofile-generate=/tmp/pgo'" \
    && (timeout -s INT 45 xvfb-run -a -s "-screen 0 1024x768x24" \
          env SDL_AUDIODRIVER=dummy ./build/emu/Vm1_core \
          --rom=/opt/trs80-rev-z/roms/level2.hex --hidden --no-sound --volume=0 \
          > /tmp/train.log 2>&1 || true) \
    && grep -q "^emu:" /tmp/train.log \
    && test -n "$(ls /tmp/pgo 2>/dev/null)" \
    && rm -rf build \
    && bash -c "source /opt/oss-cad-suite/environment && make MARCH=$MARCH PROF='-fprofile-use=/tmp/pgo -fprofile-correction'" \
    && rm -rf /tmp/pgo /tmp/train.log \
    && test -x build/emu/Vm1_core \
    && echo "Emulator built OK (PGO, MARCH=$MARCH)"

# --- [5] trszog debugger extension — staged in the image; postAttach -------
#   installs it via `code --install-extension`. (Not on the VS Code
#   Marketplace or OpenVSX, so it must be side-loaded.)
#
#   trszog.vsix is the whole trszog (DeZog fork) with every TRS-80 remote —
#   trs80gp, trs80sim, and revz (FPGA / Verilator). v3.7.4-rc1-trs80.3 is the
#   verified build from pr-trs80-support (2192fe8f) INCLUDING the runtime
#   node_modules earlier VSIXes were missing. Pinned by SHA-256.
ARG TRSZOG_VSIX=https://github.com/TechPrototyper/trszog/releases/download/v3.7.4-rc1-trs80.3/trszog.vsix
ARG TRSZOG_SHA256=8b5df3efd62ed6f1a126501fc3f021a86743e23b85bb93046215ba2c2b2ee153
RUN python3 -c "import urllib.request; urllib.request.urlretrieve('${TRSZOG_VSIX}', '/opt/trszog.vsix')" \
    && echo "${TRSZOG_SHA256}  /opt/trszog.vsix" | sha256sum -c - \
    && python3 -c "import zipfile, sys; \
d = zipfile.ZipFile('/opt/trszog.vsix').read('extension/out/extension.js'); \
sys.exit(0 if b'case\"revz\"' in d else 1)" \
    && echo "trszog revz build verified"

# --- [6] trs80 companion extension (assemble/build, DeZog target switcher) --
ARG TRS80EXT_VSIX=https://github.com/TechPrototyper/trs80-vscode/releases/download/v0.1.0/trs80-0.1.0.vsix
ARG TRS80EXT_SHA256=c6f5dc293c391ff469079818ede205396d34b25ec6175816571690adf13d18fa
RUN python3 -c "import urllib.request; urllib.request.urlretrieve('${TRS80EXT_VSIX}', '/opt/trs80ext.vsix')" \
    && echo "${TRS80EXT_SHA256}  /opt/trs80ext.vsix" | sha256sum -c -

WORKDIR /workspace
