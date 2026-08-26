# TRS-80 Dev — Z80 Assembly with a Cycle-True Model 1

A full TRS-80 Model 1 development environment in a GitHub Codespace: the
cycle-true `m1_core` RTL runs headless under Verilator, and the **trszog**
debugger (a DeZog fork) attaches to it over a localhost debug link — exactly
as if it were physical FPGA hardware. Write Z80 assembly, assemble it with
**zmac**, press **F5**, and single-step the real machine.

## How it works

```
VS Code (browser)
  trszog extension ──JSON-RPC──► tools/trszog_bridge.py ──binary v0──► emulator
     (F5, step,          tcp :49152                        tcp :5555     (Vm1_core,
      breakpoints)   (trszog starts this on F5)                          headless
                                                                         under Xvfb)
```

Everything heavy (Verilator, zmac, the built emulator, the trszog extension)
is baked into the dev-container image, so opening the Codespace is fast.

## Quick start

1. **Open in a Codespace.** The image builds once (Verilator from source),
   then `post_create` wires up the workspace. The machine **auto-starts** on
   folder open (task *TRS-80: Start Machine*).
2. **Assemble** the demo: open `space_invaders.asm` → run the build task
   *zmac: Assemble Current File* (`Ctrl/Cmd-Shift-B`). It writes
   `zout/space_invaders.cmd` (loadable) and `zout/space_invaders.bds` (symbols).
3. **Debug:** press **F5** →
   - *TRS-80 (attach)* — halt/step/break the live machine, no symbols.
   - *TRS-80 (space_invaders, with symbols)* — source-level, after step 2.

trszog starts the debug bridge itself (`transport.autoStart`), so you only
need the machine running (it is, from step 1).

## Tasks

| Task | What it does |
|------|--------------|
| **TRS-80: Start Machine** | Emulator headless on `--debug-tcp=5555` (auto-runs on open; re-run after Stop) |
| **TRS-80: Stop Machine** | Kill the emulator process |
| **TRS-80: Screen Dump** | Text-mode VRAM snapshot in the terminal |
| **zmac: Assemble Current File** | Build the `.asm` you have open → `zout/` |

## Disk images

Drop `.dmk` files into `disks/` — they mount as drives 0–3 on the next
*Start Machine*.

## Self-check (no VS Code needed)

```bash
python3 .devcontainer/scripts/e2e_test.py
```

Starts the emulator + bridge, does a JSON-RPC `initialize` and a memory read,
and prints `PASS` if the whole chain is healthy.

## Troubleshooting

- **F5 shows no TRS-80 debugger.** The trszog extension is side-loaded (it is
  not on the VS Code Marketplace / OpenVSX). If the profile install did not
  take, run once in the terminal and reload the window:
  ```bash
  code --install-extension /opt/trszog.vsix
  ```
- **"No ROM found".** Place your Level II ROM (12 KiB, `$readmemh` hex format)
  at `roms/level2.hex` — see `roms/README.md` for provenance.
- **Machine not running.** Re-run task *TRS-80: Start Machine*.

## What's pinned

- trs80-rev-z RTL + emulator: commit `f298549` (see the `REVZ_REF` arg in
  `.devcontainer/Dockerfile`).
- Verilator `v5.040` (must be ≥ 5.04x — earlier releases mis-generate the
  emulator's build makefile).
- trszog `v3.7.4-rc1-trs80.1`.
