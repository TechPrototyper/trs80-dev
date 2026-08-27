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

Everything heavy (Verilator, zmac, the built emulator, the trszog VSIX) is
baked into a **prebuilt image** (`ghcr.io/techprototyper/trs80-dev`), published
by the *devcontainer image* GitHub Actions workflow whenever `.devcontainer/`
changes on `main`. Opening a Codespace just pulls it — no Dockerfile build.

## Quick start

1. **Open in a Codespace.** The prebuilt image is pulled, `post_create` wires
   up the workspace, and on attach the trszog debugger installs itself
   (`postAttachCommand`). The machine **auto-starts** on folder open
   (task *TRS-80: Start Machine*).
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

- **F5 shows no TRS-80 debugger.** The trszog extension is side-loaded on
  attach (it is not on the VS Code Marketplace / OpenVSX). If the window
  opened before the install finished, or the install failed, run once in the
  terminal and reload the window:
  ```bash
  code --install-extension /opt/trszog.vsix --force
  ```
- **"No ROM found".** Place your Level II ROM (12 KiB, `$readmemh` hex format)
  at `roms/level2.hex` — see `roms/README.md` for provenance.
- **Machine not running.** Re-run task *TRS-80: Start Machine*.
- **Codespace won't create / image pull fails.** The image comes from the
  *devcontainer image* workflow. Check its latest run on `main`; re-run it
  (`workflow_dispatch`) if needed.

## Changing the dev environment

The Dockerfile still lives in `.devcontainer/` — it is just no longer built by
Codespaces. Edit it, push to `main`, wait for the *devcontainer image*
workflow to publish a fresh `:latest`, then rebuild/recreate the Codespace.

## What's pinned

- trs80-rev-z RTL + emulator: commit `9b19604` (branch `exp/codespace`; the
  `REVZ_REF` arg in `.devcontainer/Dockerfile`).
- Verilator `5.051`, **prebuilt** via oss-cad-suite `2026-08-26` (no source
  build; must be ≥ 5.04x — earlier releases mis-generate the emulator's
  build makefile).
- trszog: release **`v3.7.4-rc1-trs80.3`** of TechPrototyper/trszog (built
  from `pr-trs80-support` @ `2192fe8f`, includes the `revz` remote; internal
  extension version reads `3.7.4-rc1-trs80.1`). Downloaded at image build,
  pinned by SHA-256.
