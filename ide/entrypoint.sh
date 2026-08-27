#!/bin/bash
# TRS-80 IDE entrypoint: bring up the cycle-true machine, then serve VS Code.
set -u

WS=/home/workspace/trs80-dev

# --- rev-z machine (headless, debug link on :5555) --------------------------
# Reuses the same launcher the codespace task uses; runs in the background and
# logs to /tmp/trs80-machine.log. The IDE works without it too (trs80sim is
# in-process) — a failed machine start must not take the IDE down.
(
    cd "$WS"
    bash .devcontainer/scripts/start_trs80.sh > /tmp/trs80-machine.log 2>&1
) &

# --- VS Code in the browser --------------------------------------------------
# --without-connection-token: this is a single-user localhost container; the
# port mapping is the boundary. Do not expose port 3000 to untrusted networks.
echo "=============================================="
echo " TRS-80 IDE  →  http://localhost:3000"
echo "   default debug target: trs80sim (F5)"
echo "   cycle-true rev-z machine: starting in the"
echo "   background (log: /tmp/trs80-machine.log)"
echo "=============================================="
exec /opt/openvscode-server/bin/openvscode-server \
    --host 0.0.0.0 --port 3000 \
    --without-connection-token \
    --default-folder "$WS"
