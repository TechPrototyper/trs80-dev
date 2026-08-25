FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git make g++ gcc bison flex libfl-dev cmake \
        python3 python3-pip ca-certificates libsdl2-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages pyserial

# Verilator v5.026 (CMake build)
# NOTE: cmake --install does NOT produce verilator_bin; copy it manually.
RUN git clone --depth 1 --branch v5.026 https://github.com/verilator/verilator.git /opt/vsrc \
    && cd /opt/vsrc \
    && cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DFLEX_EXECUTABLE=/usr/bin/flex \
        -DFLEX_INCLUDE_DIR=/usr/include \
    && cmake --build build -j"$(nproc)" \
    && cp build/src/verilator /usr/local/bin/verilator_bin \
    && chmod +x /usr/local/bin/verilator_bin \
    && cmake --install build \
    && rm -rf /opt/vsrc \
    && ldconfig

# verilated.mk — not installed by CMake, required for --exe builds
RUN printf '%s\n' \
    '# verilated.mk — make fragment for Verilator v5.026 (CMake install)' \
    'VERILATOR_ROOT ?= $(shell dirname $(dirname $(lastword $(MAKEFILE_LIST))))' \
    'VERILATOR_SRC = $(VERILATOR_ROOT)/include' \
    '' \
    'CXX ?= g++' \
    'LINK = $(CXX)' \
    'LDLIBS += -lstdc++ -lm -lz' \
    '' \
    'VK_USER_OBJS = $(VM_USER_CLASSES:.cpp=.o) main.o' \
    '' \
    'VLIB_SRCS = verilated.cpp verilated_dpi.cpp verilated_threads.cpp \' \
    '    verilated_timing.cpp verilated_random.cpp verilated_vcd_c.cpp \' \
    '    verilated_vpi.cpp verilated_fst_c.cpp verilated_save.cpp \' \
    '    verilated_profiler.cpp verilated_cov.cpp' \
    '' \
    'VK_GLOBAL_OBJS =' \
    '' \
    '$(VM_PREFIX)__ALL.a: $(VLIB_SRCS:.cpp=.o)' \
    '\tar cr $@ $^' \
    '' \
    '%.o: $(VERILATOR_SRC)/%.cpp' \
    '\t$(CXX) $(CXXFLAGS) $(OPT_FAST) -I$(VERILATOR_SRC) -I$(VERILATOR_SRC)/vltstd -std=c++20 -c -o $@ $<' \
    > /usr/local/include/verilated.mk

# zmac — Z-80 macro cross-assembler (George Phillips, CC0)
RUN git clone --depth 1 https://github.com/gp48k/zmac.git /opt/zsrc \
    && cd /opt/zsrc/src \
    && make \
    && cp zmac /usr/local/bin/ \
    && rm -rf /opt/zsrc

# trszog debugger extension (baked in so VS Code sees it immediately)
COPY .devcontainer/trszog.vsix /tmp/trszog.vsix
RUN mkdir -p /home/vscode/.vscode-remote/extensions/maziac.dezog \
    && cd /tmp && unzip -o trszog.vsix > /dev/null 2>&1 \
    && cp -r extension/* /home/vscode/.vscode-remote/extensions/maziac.dezog/ \
    && rm -rf /tmp/extension /tmp/trszog.vsix

# Z80 syntax highlighting
COPY .devcontainer/z80asm.vsix /tmp/z80asm.vsix
RUN mkdir -p /home/vscode/.vscode-remote/extensions/local.z80asm \
    && cd /tmp && unzip -o z80asm.vsix > /dev/null 2>&1 \
    && cp -r extension/* /home/vscode/.vscode-remote/extensions/local.z80asm/ \
    && rm -rf /tmp/extension /tmp/z80asm.vsix

COPY roms/level2.hex /opt/roms/level2.hex

WORKDIR /workspace
