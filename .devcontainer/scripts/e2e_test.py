#!/usr/bin/env python3
"""Headless smoke test for the full TRS-80 debug chain.

    emulator (Xvfb) --tcp:5555--> trszog_bridge.py --tcp:49152--> JSON-RPC

Run it any time to confirm the machine, the bridge and the protocol are
healthy without opening VS Code:

    python3 .devcontainer/scripts/e2e_test.py

Exits 0 on success, 1 on any failure.
"""
import json
import os
import signal
import socket
import subprocess
import sys
import time

WS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
EMU = "/opt/trs80-rev-z/sim/emu/build/emu/Vm1_core"
BRIDGE = os.path.join(WS, "tools", "trszog_bridge.py")
ROM = os.path.join(WS, "roms", "level2.hex")
EMU_PORT, BRIDGE_PORT = 5555, 49152


def wait_port(port, timeout=15):
    end = time.time() + timeout
    while time.time() < end:
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1).close()
            return True
        except OSError:
            time.sleep(0.2)
    return False


def rpc(sock, method, params=None, _id=[0]):
    _id[0] += 1
    msg = {"jsonrpc": "2.0", "id": _id[0], "method": method}
    if params is not None:
        msg["params"] = params
    sock.sendall((json.dumps(msg) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError("bridge closed the connection")
        buf += chunk
    return json.loads(buf.split(b"\n", 1)[0])


def main():
    env = dict(os.environ, SDL_AUDIODRIVER="dummy")
    emu = subprocess.Popen(
        ["xvfb-run", "-a", "-s", "-screen 0 1024x768x24", EMU,
         f"--rom={ROM}", "--hidden", "--volume=0", "--no-sound",
         f"--debug-tcp={EMU_PORT}", "--throttle=0.7"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        env=env, preexec_fn=os.setsid)
    bridge = None
    try:
        if not wait_port(EMU_PORT):
            print("FAIL: emulator did not open tcp:5555"); return 1
        print("ok  : emulator listening on tcp:5555")

        bridge = subprocess.Popen(
            [sys.executable, BRIDGE, "--serial", f"tcp:{EMU_PORT}",
             "--baud", "460800", "--port", str(BRIDGE_PORT)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            preexec_fn=os.setsid)
        if not wait_port(BRIDGE_PORT):
            print("FAIL: bridge did not open tcp:49152"); return 1
        print("ok  : bridge listening on tcp:49152")

        s = socket.create_connection(("127.0.0.1", BRIDGE_PORT), timeout=10)
        s.settimeout(10)
        init = rpc(s, "initialize", {"clientName": "e2e"}).get("result", {})
        if "trs80" not in init.get("programName", "").lower():
            print(f"FAIL: unexpected initialize result: {init}"); return 1
        print(f"ok  : initialize -> {init.get('programName')} "
              f"caps={list(init.get('capabilities', {}))}")

        mem = rpc(s, "readMemory", {"address": "0x0000", "length": 16})
        data = mem.get("result", {}).get("data", "")
        if len(data) != 32:
            print(f"FAIL: readMemory returned {data!r}"); return 1
        print(f"ok  : readMemory 0x0000 -> {data}")
        s.close()
        print("\nPASS: full debug chain is healthy.")
        return 0
    finally:
        for p in (bridge, emu):
            if p and p.poll() is None:
                try:
                    os.killpg(os.getpgid(p.pid), signal.SIGTERM)
                except Exception:
                    p.terminate()


if __name__ == "__main__":
    sys.exit(main())
