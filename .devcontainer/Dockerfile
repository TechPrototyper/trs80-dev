FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# ---------------------------------------------------------------------------
# TRS-80 Dev — everything the codespace needs, baked at image-build time.
#
# Fast path: a PREBUILT Verilator (oss-cad-suite) instead of compiling it from
# source (~20 min on a 2-core codespace). Pinned so every build is identical.
# ---------------------------------------------------------------------------
# trs80-rev-z @ a5ff689 (exp/codespace): carries the scoped SYNCASYNCNET
#   waiver (ADR-0010) so the RTL verilates cleanly under Verilator 5.05x.
ARG REVZ_REF=a5ff6894fbaa32ecde196bea51a78a153794502b
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

# --- [5] trszog debugger extension — staged in the image; postCreate -------
#   installs it into the user's codespace profile. (Not on the VS Code
#   Marketplace or OpenVSX, so it must be side-loaded.)
#
#   The `revz` remote lives on trszog's pr-trs80-support branch; the GitHub
#   *release* VSIX is built from main and lacks revz ("Remote type 'revz'
#   does not exist"). So we ship the verified revz build in-repo.
#   Source: TechPrototyper/trszog @ pr-trs80-support (2192fe8f).
COPY trszog-revz.vsix /opt/trszog.vsix
RUN mkdir -p /opt/trszog-ext \
    && python3 -c "import zipfile; zipfile.ZipFile('/opt/trszog.vsix').extractall('/opt/trszog-ext')" \
    && test -f /opt/trszog-ext/extension/package.json \
    && grep -q 'case"revz"' /opt/trszog-ext/extension/out/extension.js \
    && echo "trszog revz build verified"

WORKDIR /workspace
