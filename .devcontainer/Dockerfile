FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# ---------------------------------------------------------------------------
# TRS-80 Dev — everything the codespace needs, baked at image-build time.
#
# Fast path: a PREBUILT Verilator (oss-cad-suite) instead of compiling it from
# source (~20 min on a 2-core codespace). Pinned so every build is identical.
# ---------------------------------------------------------------------------
# trs80-rev-z @ 9b19604 (exp/codespace): carries the scoped SYNCASYNCNET
#   waiver (ADR-0010) so the RTL verilates cleanly under Verilator 5.05x.
#   (rev-z ships NO ROM/disk by policy — trs80-dev provides those itself.)
ARG REVZ_REF=9b19604aed669455e91265a506254f26a5ba93b7
# oss-cad-suite release that ships Verilator 5.051 (prebuilt, linux-x64).
ARG OSS_CAD=https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-08-26/oss-cad-suite-linux-x64-20260826.tgz

# --- [1] Toolchain + real SDL2 + a headless display ------------------------
#   The emulator unconditionally creates an ACCELERATED SDL renderer even in
#   --hidden mode, so it needs a real display with a GL backend. Xvfb + Mesa's
#   llvmpipe (software GL) provide exactly that with no GPU.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git make g++ flex bison python3 python3-pip ca-certificates unzip \
        libsdl2-dev xvfb libgl1-mesa-dri libglx-mesa0 xauth \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install --break-system-packages pyserial

# --- [2] Prebuilt Verilator 5.051 via oss-cad-suite (no compilation) --------
RUN cd /opt \
    && python3 -c "import urllib.request; urllib.request.urlretrieve('${OSS_CAD}', '/tmp/oss.tgz')" \
    && tar xzf /tmp/oss.tgz && rm /tmp/oss.tgz \
    && /opt/oss-cad-suite/bin/verilator --version

# --- [3] zmac — Z-80 macro cross-assembler (George Phillips, CC0) -----------
RUN git clone --depth 1 https://github.com/gp48k/zmac.git /opt/zmac-src \
    && cd /opt/zmac-src/src && make \
    && cp zmac /usr/local/bin/ \
    && rm -rf /opt/zmac-src

# --- [4] trs80-rev-z (pinned to the waiver commit) + build the emulator -----
#   via its own Makefile. Plain `make` (no -j): the outer make must not pass a
#   jobserver to Verilator's own `--build -j 0`, or oss-cad-suite's make aborts
#   with "write jobserver: Bad file descriptor". Verilator parallelizes itself.
RUN git clone https://github.com/TechPrototyper/trs80-rev-z.git /opt/trs80-rev-z \
    && cd /opt/trs80-rev-z && git checkout ${REVZ_REF} \
    && cd sim/emu \
    && bash -c 'source /opt/oss-cad-suite/environment && make' \
    && test -x build/emu/Vm1_core \
    && echo "Emulator built OK (Verilator 5.051, prebuilt)"

# --- [5] trszog debugger extension — staged in the image; postAttach -------
#   installs it via `code --install-extension`. (Not on the VS Code
#   Marketplace or OpenVSX, so it must be side-loaded.)
#
#   trszog.vsix is the whole trszog (DeZog fork) with every TRS-80 remote —
#   trs80gp, trs80sim, and revz (FPGA / Verilator). The `revz` remote lives on
#   trszog's pr-trs80-support branch; the v3.7.4-rc1-trs80.1 release VSIX is
#   built from main and lacks revz ("Remote type 'revz' does not exist").
#   v3.7.4-rc1-trs80.2 is the verified build from pr-trs80-support (2192fe8f),
#   pinned here by SHA-256.
ARG TRSZOG_VSIX=https://github.com/TechPrototyper/trszog/releases/download/v3.7.4-rc1-trs80.2/trszog.vsix
ARG TRSZOG_SHA256=9f7904dd6c338934e521888b301bbc78502e0653eb32d47758aad37fbe007f7f
RUN python3 -c "import urllib.request; urllib.request.urlretrieve('${TRSZOG_VSIX}', '/opt/trszog.vsix')" \
    && echo "${TRSZOG_SHA256}  /opt/trszog.vsix" | sha256sum -c - \
    && python3 -c "import zipfile, sys; \
d = zipfile.ZipFile('/opt/trszog.vsix').read('extension/out/extension.js'); \
sys.exit(0 if b'case\"revz\"' in d else 1)" \
    && echo "trszog revz build verified"

WORKDIR /workspace
