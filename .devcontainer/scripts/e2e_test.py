#!/usr/bin/env python3
"""End-to-end test: Verilator emulator → Python bridge → JSON-RPC.

Verifies the full debug chain works headless:
  1. Emulator starts and listens on --debug-tcp port
  2. Bridge spawns and connects to the emulator
  3. JSON-RPC initialize returns capabilities
  4. Memory read returns valid data
  5. Screenshot/display data is available

Usage: python3 e2e_test.py [--emu-binary PATH] [--rom PATH] [--disk PATH]
"""
import argparse
import json
import os
import select
import signal
import socket
import subprocess
import sys
import time


def wait_port(host, port, timeout=10):
    """Wait until a TCP port is accepting connections."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(1)
            s.connect((host, port))
            s.close()
            return True
        except (ConnectionRefusedError, OSError):
            time.sleep(0.2)
    return False


def dap_request(sock, method, params=None, req_id=1):
    """Send a JSON-RPC request and read the response."""
    msg = {"jsonrpc": "2.0", "id": req_id, "method": method}
    if params is not None:
        msg["params"] = params
    payload = (json.dumps(msg) + "\n").encode()
    sock.sendall(payload)

    # Read response line
    buf = b""
    while b"\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError("connection closed while reading response")
        buf += chunk
    line, _ = buf.split(b"\n", 1)
    return json.loads(line)


def run_e2e(emu_binary, rom, disk, emu_port=5555, bridge_port=49152):
    results = []
    emu_proc = None
    bridge_proc = None

    def report(name, ok, detail=""):
        status = "PASS" if ok else "FAIL"
        results.append((name, ok))
        print(f"  [{status}] {name}" + (f" — {detail}" if detail else ""))

    try:
        # --- Step 1: Start emulator ---
        print("[1/5] Starting emulator...")
        cmd = [emu_binary, f"--rom={rom}", "--hidden", "--no-sound",
               f"--debug-tcp={emu_port}"]
        if disk:
            cmd.append(f"--disk0={disk}")

        env = os.environ.copy()
        env["XDG_RUNTIME_DIR"] = "/tmp/runtime-e2e"
        os.makedirs("/tmp/runtime-e2e", exist_ok=True)

        emu_proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, env=env)
        time.sleep(2)

        if emu_proc.poll() is not None:
            out = emu_proc.stdout.read().decode(errors="replace")
            report("emulator starts", False, out[:200])
            return False

        port_ok = wait_port("127.0.0.1", emu_port, timeout=5)
        report("emulator listening on tcp:" + str(emu_port), port_ok)
        if not port_ok:
            return False

        # --- Step 2: Start bridge ---
        print("[2/5] Starting bridge...")
        bridge_script = os.path.join(os.path.dirname(__file__), "..", "tools", "trzog_bridge.py")
        bridge_script = os.path.normpath(bridge_script)
        if not os.path.exists(bridge_script):
            # Fallback: look in /opt
            bridge_script = "/opt/trs80-rev-z/tools/trszog_bridge.py"

        bridge_proc = subprocess.Popen(
            [sys.executable, bridge_script, "--serial", f"tcp:{emu_port}",
             "--port", str(bridge_port)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        time.sleep(2)

        if bridge_proc.poll() is not None:
            out = bridge_proc.stdout.read().decode(errors="replace")
            report("bridge starts", False, out[:200])
            return False

        bridge_ok = wait_port("127.0.0.1", bridge_port, timeout=5)
        report("bridge listening on tcp:" + str(bridge_port), bridge_ok)
        if not bridge_ok:
            return False

        # --- Step 3: JSON-RPC initialize ---
        print("[3/5] Testing JSON-RPC initialize...")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(10)
        sock.connect(("127.0.0.1", bridge_port))
        time.sleep(0.5)

        try:
            resp = dap_request(sock, "initialize",
                               {"clientName": "e2e-test", "version": "1.0"}, 1)
            result = resp.get("result", {})
            prog = result.get("programName", "")
            ver = result.get("version", "")
            caps = result.get("capabilities", {})
            ok = "trs80" in prog.lower() or "rev-z" in prog.lower()
            report("initialize handshake", ok,
                   f"program={prog!r} version={ver!r}")
            if not ok:
                return False

            # --- Step 4: Memory read ---
            print("[4/5] Testing memory read...")
            resp = dap_request(sock, "readMemory",
                               {"address": "0x0000", "length": 16}, 2)
            mem_data = resp.get("result", {}).get("data", "")
            ok = len(mem_data) == 32  # 16 bytes hex = 32 chars
            report("memory read (16 bytes @ 0x0000)", ok,
                   f"data={mem_data[:16]}...")
            if not ok:
                print(f"    raw response: {resp}")

            # --- Step 5: Display (screen RAM @ 0x3C00) ---
            print("[5/5] Testing display (screen RAM @ 0x3C00)...")
            resp = dap_request(sock, "readMemory",
                               {"address": "0x3C00", "length": 16}, 3)
            scr_data = resp.get("result", {}).get("data", "")
            ok = len(scr_data) == 32
            non_zero = any(scr_data[i:i+2] != "00"
                           for i in range(0, len(scr_data), 2))
            report("display RAM readable (0x3C00)", ok,
                   f"first 16 bytes: {scr_data[:32]}")
            if ok and non_zero:
                report("display has content (non-blank)", True)

        finally:
            sock.close()

        # Summary
        passed = sum(1 for _, ok in results if ok)
        total = len(results)
        print(f"\n{'='*50}")
        print(f"E2E RESULT: {passed}/{total} tests passed")
        if passed == total:
            print("ALL TESTS PASSED ✓")
        else:
            failed = [n for n, ok in results if not ok]
            print(f"FAILED: {', '.join(failed)}")
        return passed == total

    finally:
        # Cleanup
        for proc in (bridge_proc, emu_proc):
            if proc and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()


def main():
    ap = argparse.ArgumentParser(description="TRS-80 Rev Z E2E test")
    ap.add_argument("--emu-binary", default="/opt/trs80-rev-z/sim/emu/build/emu/Vm1_core")
    ap.add_argument("--rom", default="/workspaces/trs80-dev/roms/level2.hex")
    ap.add_argument("--disk", default="/workspaces/trs80-dev/disks/boot.dmk")
    ap.add_argument("--emu-port", type=int, default=5555)
    ap.add_argument("--bridge-port", type=int, default=49152)
    args = ap.parse_args()

    print("=" * 50)
    print("TRS-80 Rev Z — End-to-End Debug Chain Test")
    print("=" * 50)
    print(f"  Emulator: {args.emu_binary}")
    print(f"  ROM:      {args.rom}")
    print(f"  Disk:     {args.disk}")
    print(f"  Ports:    emu={args.emu_port} bridge={args.bridge_port}")
    print("=" * 50)

    ok = run_e2e(args.emu_binary, args.rom, args.disk,
                 args.emu_port, args.bridge_port)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
