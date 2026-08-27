# TRS-80 IDE — the full dev environment as a self-contained browser IDE.
#
#   docker compose up            (or: docker run -p 3000:3000 ghcr.io/techprototyper/trs80-ide)
#   container run -p 3000:3000 ghcr.io/techprototyper/trs80-ide   (Apple `container`, macOS 26+)
#
# then open http://localhost:3000 — VS Code (openvscode-server) with trszog
# preinstalled, the workspace ready, and the cycle-true rev-z machine running.
# Nothing touches the user's local VS Code installation or profile.
#
# BASE is injected by CI as the arch-specific digest of the trs80-dev image.
ARG BASE=ghcr.io/techprototyper/trs80-dev:latest
FROM ${BASE}

ARG TARGETARCH
ARG OVS_VERSION=1.109.5

# --- openvscode-server (Gitpod's open VS Code web build) --------------------
RUN OVS_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo x64) \
    && URL="https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v${OVS_VERSION}/openvscode-server-v${OVS_VERSION}-linux-${OVS_ARCH}.tar.gz" \
    && python3 -c "import urllib.request, sys; urllib.request.urlretrieve(sys.argv[1], '/tmp/ovs.tgz')" "$URL" \
    && tar xzf /tmp/ovs.tgz -C /opt && rm /tmp/ovs.tgz \
    && mv /opt/openvscode-server-v${OVS_VERSION}-linux-${OVS_ARCH} /opt/openvscode-server \
    && chown -R vscode:vscode /opt/openvscode-server

# --- Workspace: this repo, ready to use -------------------------------------
COPY --chown=vscode:vscode . /home/workspace/trs80-dev
RUN cp /opt/trs80-rev-z/tools/trszog_bridge.py /home/workspace/trs80-dev/tools/trszog_bridge.py \
    && { cp /opt/trs80-rev-z/tools/emu_screen_dump.py /home/workspace/trs80-dev/tools/emu_screen_dump.py 2>/dev/null || true; } \
    && chown vscode:vscode /home/workspace/trs80-dev/tools/*

# --- trszog preinstalled into the server's extension profile ----------------
USER vscode
RUN /opt/openvscode-server/bin/openvscode-server --install-extension /opt/trszog.vsix \
    && /opt/openvscode-server/bin/openvscode-server --install-extension /opt/trs80ext.vsix \
    && /opt/openvscode-server/bin/openvscode-server --list-extensions | grep -qi dezog \
    && /opt/openvscode-server/bin/openvscode-server --list-extensions | grep -qi "techprototyper.trs80$"

USER root
COPY ide/entrypoint.sh /usr/local/bin/trs80-ide
RUN chmod +x /usr/local/bin/trs80-ide

USER vscode
WORKDIR /home/workspace/trs80-dev
EXPOSE 3000
CMD ["trs80-ide"]
