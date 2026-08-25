#!/usr/bin/env python3
"""DAP (Debug Adapter Protocol) server for TRS-80 Rev Z emulator.

Speaks standard DAP over TCP (what VS Code expects from a DebugAdapterServer)
and translates to the binary debug protocol v0 on the emulator's --debug-tcp port.

This replaces the need for the full trszog VS Code extension — a minimal
extension just registers the 'dezog' type pointing at this port.

Usage:
  python3 tools/dap_bridge.py --serial tcp:5555 --port 49152
"""

import argparse
import json
import socket
import struct
import sys
import threading
import time


class TcpSerial:
    def __init__(self, port):
        self.sock = socket.create_connection(("127.0.0.1", port))
        self.sock.settimeout(2)
        self.is_open = True

    @property
    def in_waiting(self):
        import select
        r, _, _ = select.select([self.sock], [], [], 0)
        return 1 if r else 0

    def read(self, n=1):
        try:
            return self.sock.recv(n)
        except socket.timeout:
            return b""

    def write(self, data):
        self.sock.sendall(data)
        return len(data)

    def reset_input_buffer(self):
        old = self.sock.gettimeout()
        self.sock.settimeout(0.05)
        try:
            while self.sock.recv(4096):
                pass
        except (socket.timeout, BlockingIOError, OSError):
            pass
        self.sock.settimeout(old)

    def close(self):
        self.is_open = False
        self.sock.close()


# binary protocol v0 commands
C_HALT, C_RUN, C_STEP, C_REGS, C_SETR = 0x01, 0x02, 0x03, 0x04, 0x05
C_RDM, C_WRM, C_SBP, C_STAT, C_SWP = 0x06, 0x07, 0x08, 0x09, 0x0A
C_KEYS = 0x0B
R_ERR, R_EVT = 0xEE, 0x80

REG_IDX = {"AF": 0, "BC": 1, "DE": 2, "HL": 3, "IX": 4, "IY": 5,
           "SP": 6, "PC": 7, "I": 8, "R": 9,
           "AF_": 10, "BC_": 11, "DE_": 12, "HL_": 13}
REG_NAMES = ["AF", "BC", "DE", "HL", "IX", "IY", "SP", "PC", "I", "R",
             "AF_", "BC_", "DE_", "HL_"]


class CoreRefused(Exception):
    pass


class Link:
    def __init__(self, dev, on_event):
        self.on_event = on_event
        self.lock = threading.Lock()
        self.ser = None
        self._open(dev)

    def _open(self, dev):
        try:
            if self.ser:
                self.ser.close()
        except Exception:
            pass
        if dev.startswith("tcp:"):
            self.ser = TcpSerial(int(dev[4:]))
            time.sleep(0.05)
            self.ser.reset_input_buffer()
        else:
            import serial
            self.ser = serial.Serial(dev, 460800, timeout=2)
            time.sleep(0.05)
            self.ser.reset_input_buffer()
            self.ser.reset_output_buffer()
            self.ser.timeout = 0.05
            while self.ser.read(256):
                pass
            self.ser.timeout = 2

    def _ensure(self):
        if self.ser is None or not self.ser.is_open:
            self._open(self.dev)

    def _byte(self):
        d = self.ser.read(1)
        if not d:
            raise IOError("serial read timeout")
        return d[0]

    def _resp(self, first_ok, tail_len):
        while True:
            b = self._byte()
            if b == R_EVT:
                ev = [self._byte() for _ in range(3)]
                self.on_event(ev[0], ev[1] | (ev[2] << 8))
                continue
            if b == R_ERR:
                raise CoreRefused("refused")
            if b != first_ok:
                raise IOError(f"framing error: expected {first_ok:02x}, got {b:02x}")
            return bytes(self._byte() for _ in range(tail_len))

    def _txn(self, frame, first_ok, tail_len):
        with self.lock:
            try:
                self._ensure()
                self.ser.write(bytes(frame))
                return self._resp(first_ok, tail_len)
            except CoreRefused:
                raise
            except (OSError, IOError) as e:
                self.ser = None
                raise IOError(f"link lost: {e}")

    def halt(self):
        t = self._txn([C_HALT], C_HALT, 2)
        return t[0] | (t[1] << 8)

    def run(self):
        self._txn([C_RUN], C_RUN, 0)

    def step(self):
        t = self._txn([C_STEP], C_STEP, 2)
        return t[0] | (t[1] << 8)

    def regs(self):
        return self._txn([C_REGS], C_REGS, 30)

    def set_reg(self, idx, val):
        val &= 0xFFFF
        self._txn([C_SETR, idx, val & 0xFF, val >> 8], C_SETR, 2)

    def read_mem(self, addr, n):
        addr &= 0xFFFF
        n = min(n, 0x10000 - addr)
        out = bytearray()
        while n > 0:
            chunk = min(n, 0x8000)
            out += self._txn([C_RDM, addr & 0xFF, addr >> 8,
                              chunk & 0xFF, chunk >> 8], C_RDM, chunk)
            addr = (addr + chunk) & 0xFFFF
            n -= chunk
        return bytes(out)

    def write_mem(self, addr, data):
        addr &= 0xFFFF
        off = 0
        while off < len(data):
            chunk = data[off:off + 0x8000]
            self._txn([C_WRM, addr & 0xFF, addr >> 8,
                       len(chunk) & 0xFF, len(chunk) >> 8]
                      + list(chunk), C_WRM, 0)
            addr = (addr + len(chunk)) & 0xFFFF
            off += len(chunk)

    def set_bp(self, slot, addr, en):
        addr &= 0xFFFF
        self._txn([C_SBP, slot, addr & 0xFF, addr >> 8, 1 if en else 0],
                  C_SBP, 0)

    def status(self):
        t = self._txn([C_STAT], C_STAT, 4)
        return t[0], t[1], t[2] | (t[3] << 8)

    def poll_event(self):
        with self.lock:
            try:
                self._ensure()
                if self.ser.in_waiting < 1:
                    return None
                b = self._byte()
                if b != R_EVT:
                    return None
                ev = [self._byte() for _ in range(3)]
                return ev[0], ev[1] | (ev[2] << 8)
            except (OSError, IOError):
                self.ser = None
                return None


def hx(v, w=4):
    return f"0x{v:0{w}X}"


class DAPBridge:
    """Translates DAP (Debug Adapter Protocol) to TRS-80 binary debug protocol."""

    BP_SLOTS = range(0, 7)

    def __init__(self, link):
        self.link = link
        self.sock = None
        self.running = False
        self.breakpoints = {}
        self.next_var_ref = 100
        self.var_refs = {}
        self.halted_pc = 0
        self.initialized = False

    def on_event(self, cause, pc):
        self.running = False
        reasons = {0: "paused", 1: "breakpoint", 2: "step", 3: "watchpoint", 4: "restart"}
        reason = reasons.get(cause, "paused")
        self.halted_pc = pc
        self.send_event("stopped", {
            "reason": reason,
            "description": reason,
            "threadId": 1,
            "allThreadsStopped": True,
            "text": f"stopped at PC={hx(pc)}"
        })

    def send_response(self, seq, command, success=True, message=None, body=None):
        msg = {
            "seq": seq,
            "type": "response",
            "request_seq": self._last_req_seq,
            "command": command,
            "success": success,
        }
        if message:
            msg["message"] = message
        if body:
            msg["body"] = body
        self._send(msg)

    def send_event(self, event, body=None):
        msg = {
            "seq": self._next_seq(),
            "type": "event",
            "event": event,
        }
        if body:
            msg["body"] = body
        self._send(msg)

    def _send(self, msg):
        if self.sock:
            data = json.dumps(msg).encode() + b"\n"
            try:
                self.sock.sendall(data)
            except (OSError, BrokenPipeError):
                pass

    def _next_seq(self):
        self._seq = getattr(self, '_seq', 100) + 1
        return self._seq

    def _last_req_seq(self):
        return getattr(self, '_req_seq', 0)

    # ---- DAP command handlers ----

    def handle_dap(self, msg):
        cmd = msg.get("command")
        args = msg.get("arguments", {})
        self._req_seq = msg.get("seq", 0)

        if cmd == "initialize":
            return self.cmd_initialize(args)
        elif cmd == "launch":
            return self.cmd_launch(args)
        elif cmd == "attach":
            return self.cmd_attach(args)
        elif cmd == "setBreakPoints":
            return self.cmd_set_breakpoints(args)
        elif cmd == "configurationDone":
            return self.cmd_configuration_done(args)
        elif cmd == "continue":
            return self.cmd_continue(args)
        elif cmd == "next":
            return self.cmd_next(args)
        elif cmd == "stepIn":
            return self.cmd_step_in(args)
        elif cmd == "stepOut":
            return self.cmd_step_out(args)
        elif cmd == "pause":
            return self.cmd_pause(args)
        elif cmd == "stackTrace":
            return self.cmd_stack_trace(args)
        elif cmd == "scopes":
            return self.cmd_scopes(args)
        elif cmd == "variables":
            return self.cmd_variables(args)
        elif cmd == "evaluate":
            return self.cmd_evaluate(args)
        elif cmd == "threads":
            return self.cmd_threads(args)
        elif cmd == "disconnect":
            return self.cmd_disconnect(args)
        elif cmd == "readMemory":
            return self.cmd_read_memory(args)
        elif cmd == "data":
            return self.cmd_data(args)
        else:
            return None  # unknown: let it fail gracefully

    def cmd_initialize(self, args):
        self.initialized = True
        return {
            "supportsConfigurationDoneRequest": True,
            "supportsReadMemoryRequest": True,
            "supportsStepBack": False,
            "supportsConditionalBreakpoints": False,
            "supportsHitConditionalBreakpoints": False,
            "supportsSetVariableObject": False,
            "supportsRestart": False,
            "supportsExceptionInfoRequest": False,
            "supportsTerminateThreadsRequest": False,
            "supportsDataBreakpoints": False,
            "supportsFunctionBreakpoints": False,
            "supportsTerminateThreadsRequest": False,
            "supportsGotoTargetsRequest": False,
            "supportsStepInTargetsRequest": False,
            "supportsSetExpressionValues": False,
            "supportsExceptionOptions": False,
            "supportsLoadedSourcesRequest": False,
            "supportsCompletedEvent": False,
            "supportsLogPointBreakpoints": False,
            "supportsInstructionBreakpoints": True,
            "supportsMemoryReferences": True,
            "supportsClearingConditions": False,
        }

    def cmd_launch(self, args):
        # We don't launch — the machine is already running.
        # Just confirm we're attached.
        return {}

    def cmd_attach(self, args):
        return {}

    def cmd_set_breakpoints(self, args):
        source = args.get("source", {})
        bps = args.get("breakpoints", [])
        lines = args.get("lines", [])

        addrs = []
        for bp in bps:
            line = bp.get("line", 1)
            col = bp.get("column", 1)
            # For Z80, "line" IS the address (we'll map it)
            # Convention: line = address directly
            addr = line if line > 0xFF else 0
            addrs.append(addr)

        for i, slot in enumerate(self.BP_SLOTS):
            if i < len(addrs):
                self.link.set_bp(slot, addrs[i], True)
            else:
                self.link.set_bp(slot, 0, False)

        verified = []
        for a in addrs:
            verified.append({
                "verified": True,
                "line": a,
                "instructionReference": f"{a:08x}",
            })
        return {"breakpoints": verified}

    def cmd_configuration_done(self, args):
        return {}

    def cmd_continue(self, args):
        self.link.run()
        self.running = True
        threading.Thread(target=self._wait_stop, daemon=True).start()
        return {"allThreadsContinued": True}

    def cmd_next(self, args):
        pc = self.link.step()
        self.halted_pc = pc
        self.send_event("stopped", {
            "reason": "step", "threadId": 1,
            "allThreadsStopped": True, "text": f"stepped to {hx(pc)}"
        })
        return {}

    def cmd_step_in(self, args):
        pc = self.link.step()
        self.halted_pc = pc
        self.send_event("stopped", {
            "reason": "step", "threadId": 1,
            "allThreadsStopped": True, "text": f"stepped to {hx(pc)}"
        })
        return {}

    def cmd_step_out(self, args):
        # No call stack tracking — just step
        pc = self.link.step()
        self.halted_pc = pc
        self.send_event("stopped", {
            "reason": "step", "threadId": 1,
            "allThreadsStopped": True, "text": f"stepped to {hx(pc)}"
        })
        return {}

    def cmd_pause(self, args):
        pc = self.link.halt()
        self.halted_pc = pc
        self.running = False
        self.send_event("stopped", {
            "reason": "pause", "threadId": 1,
            "allThreadsStopped": True, "text": f"paused at {hx(pc)}"
        })
        return {}

    def cmd_stack_trace(self, args):
        # Single frame: PC
        return {
            "stackFrames": [{
                "id": 1,
                "name": f"PC = {hx(self.halted_pc)}",
                "source": {"name": "z80"},
                "line": self.halted_pc,
                "instructionPointer": f"{self.halted_pc:08x}",
            }],
            "totalFrames": 1,
        }

    def cmd_scopes(self, args):
        return {
            "scopes": [
                {"name": "Registers", "variablesReference": 1, "expensive": False},
                {"name": "Memory", "variablesReference": 2, "expensive": True},
            ]
        }

    def cmd_variables(self, args):
        ref = args.get("variablesReference", 0)
        if ref == 1:
            # Registers
            try:
                r = self.link.regs()
                (a, f, b, c, d, e, h, l, ixh, ixl, iyh, iyl,
                 i_reg, _fi, r_reg, _fr,
                 a2, f2, b2, c2, d2, e2, h2, l2,
                 sp_lo, sp_hi, pc_lo, pc_hi, im, iff) = r
                regs = [
                    ("AF", (a << 8) | f), ("BC", (b << 8) | c),
                    ("DE", (d << 8) | e), ("HL", (h << 8) | l),
                    ("IX", (ixh << 8) | ixl), ("IY", (iyh << 8) | iyl),
                    ("SP", (sp_hi << 8) | sp_lo), ("PC", (pc_hi << 8) | pc_lo),
                    ("I", i_reg), ("R", r_reg),
                    ("AF'", (a2 << 8) | f2), ("BC'", (b2 << 8) | c2),
                    ("DE'", (d2 << 8) | e2), ("HL'", (h2 << 8) | l2),
                    ("IM", im), ("IFF", iff),
                ]
                variables = []
                for name, val in regs:
                    variables.append({
                        "name": name,
                        "value": f"0x{val:04X}" if val > 0xFF else f"0x{val:02X}",
                        "type": "uint16" if val > 0xFF else "uint8",
                        "variablesReference": 0,
                    })
                return {"variables": variables}
            except Exception as ex:
                return {"variables": [{"name": "error", "value": str(ex), "variablesReference": 0}]}
        elif ref == 2:
            # Memory view: show screen RAM
            try:
                data = self.link.read_mem(0x3C00, 64)
                text = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data)
                return {"variables": [
                    {"name": "Screen (0x3C00)", "value": text, "variablesReference": 0},
                    {"name": "PC", "value": hx(self.halted_pc), "variablesReference": 0},
                ]}
            except Exception as ex:
                return {"variables": [{"name": "error", "value": str(ex), "variablesReference": 0}]}
        return {"variables": []}

    def cmd_evaluate(self, args):
        expr = args.get("expression", "")
        try:
            # Allow reading memory: "mem:0x3C00:16"
            if expr.startswith("mem:"):
                parts = expr.split(":")
                addr = int(parts[1].replace("0x", ""), 16) if parts[1].startswith("0x") else int(parts[1])
                length = int(parts[2]) if len(parts) > 2 else 16
                data = self.link.read_mem(addr, length)
                return {"result": data.hex(), "type": "memory"}
            # Allow reading register: "reg:PC"
            if expr.startswith("reg:"):
                rname = expr[4:].upper()
                r = self.link.regs()
                mapping = {
                    "PC": (r[28] | (r[29] << 8)),
                    "SP": (r[26] | (r[27] << 8)),
                    "AF": (r[0] << 8) | r[1],
                    "BC": (r[2] << 8) | r[3],
                    "DE": (r[4] << 8) | r[5],
                    "HL": (r[6] << 8) | r[7],
                }
                val = mapping.get(rname, 0)
                return {"result": f"0x{val:04X}", "type": "register"}
            return {"result": "unsupported expression", "type": "string"}
        except Exception as ex:
            return {"result": f"error: {ex}", "type": "string"}

    def cmd_threads(self, args):
        return {"threads": [{"id": 1, "name": "Z80"}]}

    def cmd_disconnect(self, args):
        self.running = False
        # Leave machine running
        try:
            self.link.run()
        except Exception:
            pass
        return {}

    def cmd_read_memory(self, args):
        addr = args.get("memoryReference", "0x0000")
        if isinstance(addr, str) and addr.startswith("0x"):
            addr_val = int(addr, 16)
        else:
            addr_val = int(addr)
        count = args.get("count", 256)
        try:
            data = self.link.read_mem(addr_val, count)
            return {
                "address": f"{addr_val:08x}",
                "unauthorizedMemory": False,
                "data": data.hex(),
                "count": len(data),
            }
        except Exception as ex:
            return {"unauthorizedMemory": True, "message": str(ex)}

    def cmd_data(self, args):
        return {"data": ""}

    def _wait_stop(self):
        while self.running:
            ev = self.link.poll_event()
            if ev:
                self.on_event(ev[0], ev[1])
                return
            time.sleep(0.02)

    def serve(self, port):
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", port))
        srv.listen(1)
        print(f"dap_bridge: listening on 127.0.0.1:{port}", flush=True)
        while True:
            self.sock, peer = srv.accept()
            print(f"dap_bridge: VS Code connected from {peer}", flush=True)
            buf = b""
            try:
                while True:
                    chunk = self.sock.recv(4096)
                    if not chunk:
                        break
                    buf += chunk
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        if not line.strip():
                            continue
                        try:
                            msg = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        self._handle_message(msg)
            finally:
                print("dap_bridge: disconnected", flush=True)
                self.sock = None

    def _handle_message(self, msg):
        cmd = msg.get("command")
        seq = msg.get("seq", 0)
        self._req_seq = seq

        # DAP uses Content-Length header for some messages, but VS Code
        # DebugAdapterServer uses newline-delimited JSON (like our original bridge)
        result = self.handle_dap(msg)

        if result is not None:
            resp = {
                "seq": self._next_seq(),
                "type": "response",
                "request_seq": seq,
                "command": cmd,
                "success": True,
            }
            if result:
                resp["body"] = result
            self._send(resp)
        else:
            resp = {
                "seq": self._next_seq(),
                "type": "response",
                "request_seq": seq,
                "command": cmd,
                "success": False,
                "message": f"Unsupported command: {cmd}",
            }
            self._send(resp)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serial", required=True, help="tcp:PORT or /dev/tty...")
    ap.add_argument("--port", type=int, default=49152)
    args = ap.parse_args()

    bridge = DAPBridge(None)
    bridge.link = Link(args.serial, bridge.on_event)
    bridge.serve(args.port)


if __name__ == "__main__":
    main()
