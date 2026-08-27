# TRS-80 Dev — Z80 Assembly with a Cycle-True Model 1

A full TRS-80 Model 1 development environment — in a GitHub Codespace or in a
local dev container. Two debug targets, one debugger (**trszog**, a DeZog
fork), one keystroke (**F5**):

| Target | What it is | Speed | Best for |
|---|---|---|---|
| **trs80sim** | Lawrence Kesteloot's TypeScript emulator, in-process, screen in a webview panel | fast everywhere | writing & debugging code — the default |
| **rev-z** | the cycle-true `m1_core` RTL under Verilator, headless — behaves like the physical FPGA hardware | ~0.3× in a Codespace, ~0.95× native Apple Silicon | verifying timing-critical code against the real machine |

The honest performance story: full-RTL simulation at the 10.6445 MHz dot
clock is CPU-bound on a single core. Cloud vCPUs top out around **0.3×
realtime** (after ADR-0011 clock gating + PGO); a native Apple-Silicon build
reaches **~0.95×**. That is fine for its job — at breakpoints and while
single-stepping, simulation speed is irrelevant — but for interactive runs
use trs80sim, and for full-speed cycle-true work run the container locally.

## How it works

```
VS Code
  trszog extension ──── trs80sim: in-process, screen as webview panel
       │
       └─JSON-RPC──► tools/trszog_bridge.py ──binary v0──► rev-z emulator
            tcp :49152                          tcp :5555    (Vm1_core, headless
        (trszog starts this on F5)                           under Xvfb)
```

Everything heavy (Verilator, zmac, the PGO-built emulator, the trszog VSIX)
is baked into a **multi-arch image** (`ghcr.io/techprototyper/trs80-dev`,
linux/amd64 + linux/arm64), published by the *devcontainer image* workflow
whenever `.devcontainer/` changes on `main`.

## Quick start — Codespace

1. **Open in a Codespace.** The prebuilt image is pulled, `post_create` wires
   up the workspace, and on attach the trszog debugger installs itself
   (`postAttachCommand`). The rev-z machine does **not** auto-start —
   it costs a full core; start it on demand (task *TRS-80: Start Machine*)
   when you want the cycle-true target.
2. **Assemble** the demo: open `space_invaders.asm` → `Ctrl/Cmd-Shift-B`
   (*zmac: Assemble Current File*) → `zout/space_invaders.cmd` + `.bds`.
3. **Debug:** press **F5** →
   - *TRS-80 sim (fast, with symbols)* — the default; screen opens as a panel.
   - *TRS-80 rev-z cycle-true (attach / with symbols)* — the real machine.

## Quick start — local (full speed)

Same repo, same configs, native performance. Requires Docker Desktop or
Podman — or, on macOS 26 “Tahoe” and later, Apple's native `container`
runtime; the image is standard multi-arch OCI, all three just work.

- **VS Code Desktop:** install the *Dev Containers* extension, open this
  repo, “Reopen in Container”. Everything else happens automatically.
- **Browser IDE without VS Code installed:** see `ide/` (image
  `ghcr.io/techprototyper/trs80-ide`) — `docker compose up` (or
  `container run …` on Tahoe) and open `http://localhost:3000`.

For the absolute maximum (~0.95× realtime measured on Apple Silicon), build
the emulator natively from [trs80-rev-z] with `make MARCH=native` + PGO
(`PROF=` knobs, see `sim/emu/Makefile` there) — no container in between.

## Tasks

| Task | What it does |
|------|--------------|
| **TRS-80: Start Machine** | rev-z emulator headless on `--debug-tcp=5555` (on demand — uses a full core) |
| **TRS-80: Stop Machine** | Kill the rev-z emulator process |
| **TRS-80: Screen Dump** | Text-mode VRAM snapshot of the rev-z machine |
| **zmac: Assemble Current File** | Build the `.asm` you have open → `zout/` |

## Disk images

Drop `.dmk` files into `disks/` — they mount as drives 0–3 on the next
*Start Machine* (rev-z target).

## Self-check (no VS Code needed)

```bash
python3 .devcontainer/scripts/e2e_test.py
```

Starts the rev-z emulator + bridge, does a JSON-RPC `initialize` and a memory
read, and prints `PASS` if the whole chain is healthy.

## Troubleshooting

- **F5 shows no TRS-80 debugger.** The trszog extension is side-loaded on
  attach. If the window opened before the install finished, run once in the
  terminal and reload the window:
  ```bash
  code --install-extension /opt/trszog.vsix --force
  ```
- **"No ROM found" (rev-z).** Place your Level II ROM (12 KiB, `$readmemh`
  hex format) at `roms/level2.hex` — see `roms/README.md` for provenance.
- **rev-z machine not running.** Re-run task *TRS-80: Start Machine*.
- **Codespace won't create / image pull fails.** Check the *devcontainer
  image* workflow on `main`; re-run it (`workflow_dispatch`) if needed.

## Changing the dev environment

The Dockerfile lives in `.devcontainer/` — it is built by CI, not by
Codespaces. Edit it, push to `main`, wait for the *devcontainer image*
workflow (builds amd64 and arm64 natively, merges a manifest), then
rebuild/recreate the container.

## What's pinned

- trs80-rev-z RTL + emulator: `main` @ `ea8bca2` (gated CPU clock ADR-0011,
  graceful shutdown, MARCH/PROF build knobs) — the `REVZ_REF` arg in
  `.devcontainer/Dockerfile`. Built with PGO at image build time.
- Verilator `5.051`, **prebuilt** via oss-cad-suite `2026-08-26`
  (linux-x64 and linux-arm64).
- trszog: release **`v3.7.4-rc1-trs80.3`** of TechPrototyper/trszog (built
  from `pr-trs80-support` @ `2192fe8f`, includes the `revz` remote and the
  runtime node_modules; internal extension version reads `3.7.4-rc1-trs80.1`).
  Downloaded at image build, pinned by SHA-256.

[trs80-rev-z]: https://github.com/TechPrototyper/trs80-rev-z
