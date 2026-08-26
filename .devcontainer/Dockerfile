FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# ---------------------------------------------------------------------------
# TRS-80 Dev — everything the codespace needs, baked at image-build time.
#
# Design goal: reliability. All the slow, stable pieces live here (cached
# layers). The per-codespace postCreate step is then trivial and fast.
#
# Pinned so every build is identical.
# ---------------------------------------------------------------------------
ARG REVZ_REF=f2985497792d85db17e40e966c2e2d838ff6e898
# NOTE: kept byte-identical to the previous image build ONLY so the Docker
# layer cache for the expensive Verilator step below survives a rebuild.
# It is intentionally unused now — the trszog VSIX is COPYed in at step [6],
# not downloaded (the release build lacks the revz remote).
ARG TRSZOG_VSIX=https://github.com/TechPrototyper/trszog/releases/download/v3.7.4-rc1-trs80.1/dezog-3.7.4-rc1-trs80.1.vsix

# --- [1] Toolchain (Verilator autotools deps + build essentials) -----------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git make g++ autoconf flex bison libfl-dev \
        help2man perl python3 python3-pip ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install --break-system-packages pyserial

# --- [2] Verilator v5.040 (autotools install: installs verilated.mk +  -----
#         the full include tree, so `make` in sim/emu just works). ------------
#         Must be >= 5.04x: earlier releases don't emit `VPATH += $(VM_USER_DIR)`
#         in the generated model makefile, so the emulator's own .cpp files
#         aren't found from build/emu and the build fails.
RUN git clone --depth 1 --branch v5.040 \
        https://github.com/verilator/verilator.git /opt/verilator-src \
    && cd /opt/verilator-src \
    && autoconf \
    && ./configure --prefix=/usr/local \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /opt/verilator-src \
    && ldconfig

# --- [3] zmac — Z-80 macro cross-assembler (George Phillips, CC0) -----------
RUN git clone --depth 1 https://github.com/gp48k/zmac.git /opt/zmac-src \
    && cd /opt/zmac-src/src && make \
    && cp zmac /usr/local/bin/ \
    && rm -rf /opt/zmac-src

# --- [4] Real SDL2 + a headless display. The emulator unconditionally ------
#         creates an ACCELERATED SDL renderer even in --hidden mode, so a
#         hand-written SDL stub (or the dummy video driver) is not enough —
#         it needs a real display with a GL backend. Xvfb + Mesa's llvmpipe
#         (software GL) provides exactly that with no GPU. Linking against
#         the complete real SDL2 is also far more robust than a stub.
#         Placed after Verilator so that heavy layer stays cached.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libsdl2-dev xvfb libgl1-mesa-dri libglx-mesa0 xauth \
    && rm -rf /var/lib/apt/lists/*

# --- [5] trs80-rev-z (pinned) + build the headless emulator via its --------
#         own Makefile. Verilator's --exe --build drives the C++ compile,
#         so there are no hand-listed generated filenames to drift.
RUN git clone https://github.com/TechPrototyper/trs80-rev-z.git /opt/trs80-rev-z \
    && cd /opt/trs80-rev-z && git checkout ${REVZ_REF} \
    && cd sim/emu \
    && make -j"$(nproc)" \
    && test -x build/emu/Vm1_core \
    && echo "Emulator built OK"

# --- [6] trszog debugger extension — staged in the image; postCreate -------
#         installs it into the user's codespace profile. (Not on the VS Code
#         Marketplace or OpenVSX, so it cannot be auto-installed via the
#         devcontainer `extensions` list — it must be side-loaded.)
#
#   IMPORTANT: the `revz` remote (this whole workflow) lives on trszog's
#   pr-trs80-support branch. The GitHub *release* VSIX is built from main and
#   does NOT contain revz ("Remote type 'revz' does not exist"). So we ship
#   the verified revz build in-repo instead of downloading the release.
#   Source: TechPrototyper/trszog @ pr-trs80-support (2192fe8f).
COPY trszog-revz.vsix /opt/trszog.vsix
RUN mkdir -p /opt/trszog-ext \
    && python3 -c "import zipfile; zipfile.ZipFile('/opt/trszog.vsix').extractall('/opt/trszog-ext')" \
    && test -f /opt/trszog-ext/extension/package.json \
    && grep -q 'case"revz"' /opt/trszog-ext/extension/out/extension.js \
    && echo "trszog revz build verified"

WORKDIR /workspace
