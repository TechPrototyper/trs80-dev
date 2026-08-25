FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git make g++ gcc bison flex cmake python3 python3-pip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages pyserial

RUN git clone --depth 1 --branch v5.026 https://github.com/verilator/verilator.git /opt/vsrc \
    && cd /opt/vsrc \
    && cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DFLEX_EXECUTABLE=/usr/bin/flex \
        -DFLEX_INCLUDE_DIR=/usr/include \
    && cmake --build build -j"$(nproc)" \
    && cmake --install build \
    && rm -rf /opt/vsrc \
    && ldconfig

RUN mkdir -p /usr/local/include/SDL2 /usr/local/lib

COPY sdl_stub.h /usr/local/include/SDL2/SDL.h

RUN echo 'void _sdl_stub_anchor(void) {}' > /tmp/s.c \
    && gcc -shared -o /usr/local/lib/libSDL2.so /tmp/s.c \
    && rm /tmp/s.c

# zmac — Z-80 macro cross-assembler (George Phillips, CC0)
RUN git clone --depth 1 https://github.com/gp48k/zmac.git /opt/zsrc \
    && cd /opt/zsrc/src \
    && make \
    && cp zmac /usr/local/bin/ \
    && rm -rf /opt/zsrc

COPY roms/level2.hex /opt/roms/level2.hex

WORKDIR /workspace
