#!/bin/bash
# Post-create: build emulator, run E2E test, start machine.
# Extensions are baked into the Docker image (see Dockerfile).
set -e

WS="/workspaces/trs80-dev"

echo "=== Building emulator ==="
bash "$WS/.devcontainer/scripts/setup.sh"

echo ""
echo "=== Running end-to-end test ==="
python3 "$WS/.devcontainer/scripts/e2e_test.py" || {
    echo ""
    echo "WARNING: E2E test failed. The debug chain may not work."
    echo "         Re-run: python3 $WS/.devcontainer/scripts/e2e_test.py"
}

echo ""
echo "=== Starting TRS-80 in background ==="
setsid bash "$WS/.devcontainer/scripts/start_trs80.sh" > /tmp/trs80.log 2>&1 &
disown 2>/dev/null || true
sleep 3
if pgrep -f 'Vm1_core.*debug-tcp' > /dev/null; then
    echo "  Machine running. Log: /tmp/trs80.log"
else
    echo "  WARNING: Emulator did not start. Check /tmp/trs80.log"
fi

echo ""
echo "=== Ready — press F5 to debug ==="
