# Rebel Strike on ModernGekko — Complete Setup Guide

**Context:** Full walkthrough of getting Star Wars Rogue Squadron III: Rebel Strike (PAL, GLRP64) running via the ModernGekko-Template / DolRecomp static recompilation stack, inside an Ubuntu 22.04 distrobox on Bazzite, as of Nov 2026. Includes the toolchain odyssey, working configs, known bugs, and performance tuning results.

---

## Part 1 — Distrobox & toolchain setup

> **2026-11 update:** `bootstrap.sh` in this branch now automates the distrobox +
> toolchain + build steps below. This document remains as the manual reference
> and explains each step in detail.
> A single ./bootstrap.sh that takes a fresh clone to a launchable game. What it does:
>
>    Creates the distrobox (skippable with --no-box)
>    Installs the toolchain inside it — apt.llvm.org repo for jammy-20, the pin file (both hard-won fixes from this chat), all the LLVM 20 packages, and GCC 13 from the toolchain PPA
>    Clean build with the exact working env vars (skippable with --no-build)
>    Runs setup-configs.sh for configs + shims
>    Exports the host launcher


### The container
- `decomp-env`: Ubuntu 22.04 (jammy) distrobox on Bazzite. Recreate/reenter with `distrobox enter decomp-env`.
- Builds must run inside the box; everything else (editing, launching) works from the host too (shared $HOME).

### LLVM 20 (jammy has no LLVM 19/20 in its own archive)
- Repo: `apt.llvm.org/jammy` (llvm.sh installer or manual sources).
- **Key gotcha #1 — unversioned meta-packages conflict:** don't install `libc++1`, `libc++abi1`, `libomp5`; install versioned: `libc++-20-dev`, `libc++abi-20-dev`, `libomp-20-dev`, etc.
- **Key gotcha #2 — mixed llvm suites:** if both `llvm-toolchain-jammy-20` and `-22` repos are active, `libc++-20-dev` fails on exact-version deps. Fix with apt pinning: `/etc/apt/preferences.d/llvm-20` → `Package: *` / `Pin: release n=llvm-toolchain-jammy-20` / `Pin-Priority: 1100`.
- **Key gotcha #3 — unversioned command names:** `llvm-config` may point at distro LLVM 15. Fix with `update-alternatives --install` for clang/clang++/llvm-config → -20 variants.
- Installed: clang-20, llvm-20-dev, lld-20, lldb-20, clangd-20, clang-format-20, clang-tidy-20, clang-tools-20, libclang-20-dev, libomp-20-dev, libc++-20-dev, libc++abi-20-dev, python3-clang-20.

### Compiler choice (IMPORTANT — this exact pairing)
- **Clang 20 + apt.llvm.org LLVM libs = broken link** (`std::__1::optional` symbol clashes): the LLVM libs are built against libstdc++; do NOT use `-stdlib=libc++`.
- **GCC 11 (jammy default) fails Dolphin's version check** ("Requires GCC 12...").
- **GCC 12 hits C++23 gaps** (`std::ranges::contains` needs GCC 13).
- **GCC 14 headers have `bits/unicode.h` (`++this`) that Clang rejects.**
- **Final answer: g++-13** (from `ppa:ubuntu-toolchain-r/test`) building the project; LLVM 20.1.8 as the recompilation backend. These are independent roles — the compiler builds the code, LLVM provides the JIT/IR backend.

```bash
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt-get install g++-13
```

---

## Part 2 — Building & the launch pipeline

### Build
```bash
cd ~/Games/GC/ModernGekko-Template
# env vars that must be set for configure:
CC=gcc-13 CXX=g++-13 \
LLVM_ROOT=/usr/lib/llvm-20 CMAKE_PREFIX_PATH=/usr/lib/llvm-20 \
  make llvm-run ISO=~/Games/GC/iso/rebel_strike.iso
```
- CMake caches the first configure — **after any compiler/flag change, delete the real build dirs:** `rm -rf lib/ModernGekko/build vendor/dolphin/DolRecomp/build` (NOT `./build` — the build lives under `lib/ModernGekko/`).
- Module builds are cached by DOL hash + toolchain identity: multiple cache entries accumulate under `build/modules/GLRP64/<dolhash>-<toolchainhash>/`.
- One source patch was needed for GCC 12 era: `lib/ModernGekko/tools/netplay_session.cpp:456` used `std::ranges::contains` — irrelevant now with GCC 13, kept for reference.

### The launcher (~/Games/GC/ModernGekko-Template/launch-rebel-strike.sh)
- Parses `--hud` (MangoHud if installed in box), `--scale <mode>` (gamescope), forwards other args to runner.
- **Current working invocation is interpreter mode WITHOUT --module** (compiled modules get rejected — see Bugs). Exec line:
```bash
exec "${SCALE_CMD[@]}" "${HUD_CMD[@]}" \
  ./lib/ModernGekko/build/moderngekko-run \
    --game extracted/rebel-strike \
    --allow-interpreter \
    "${RUN_ARGS[@]}" \
    >> >(tee -a "$LOG_FILE")
```
- Scale modes in the case block: `1080p`, `1440p`, `2160p`, plus manual additions `ultra` (3440×1440 native panel) and `fhd` (2560×1440 pillarboxed for 4× internal res).
- Logs to `rebel-strike.log` in project root.

### Host integration
- Inner shim `~/bin/moderngekko-rebel-strike` (in box): `exec .../launch-rebel-strike.sh "$@"`
- Export once: `distrobox-export --bin ~/bin/moderngekko-rebel-strike --export-path ~/.local/bin` (re-export only when the shim itself changes; script edits propagate automatically).
- Host shim delegates into the box. Added to Steam as non-Steam game → launches from Game mode.
- Runner must be started with correct cwd (script does `cd "$PROJECT_DIR"`).

---

## Part 3 — Configuration files (~/.local/share/moderngekko/Config/)

Shared $HOME: editable from host or box, same files.

### GCPadNew.ini (controls — via Steam Input)
```
[GCPad1]
Device = SDL/0/Steam Virtual Gamepad
Buttons/A = Button 0     Buttons/B = Button 1
Buttons/X = Button 2     Buttons/Y = Button 3
Buttons/Z = Button 10    Buttons/Start = Button 6
D-Pad/Up = Button 11  Down = 12  Left = 13  Right = 14
Main Stick/Up = Axis 1-  Down = Axis 1+  Left = Axis 0-  Right = Axis 0+
C-Stick/Up = Axis 3-  Down = Axis 3+  Left = Axis 2-  Right = Axis 2+
Triggers/L = Axis 4+     Triggers/R = Axis 5+
Rumble/Motor = Strong
```
- SC2 (2026) needs Steam client OPEN (Steam Input virtual gamepad) because vendored SDL is 3.4.4; native needs ≥3.4.10 (post-May-22 firmware).
- Reliable method: configure in Dolphin (Flatpak) GUI, copy profile, change header to `[GCPad1]`.
- Keyboard fallback via OR-bindings: e.g. `Buttons/A = Button 0 || `Keyboard A`` (verify exact keyboard device string in Dolphin's dialog).

### GFX.ini (graphics — verified key names from GraphicsSettings.cpp!)
```
[Settings]
DumpTextures = False
InternalResolution = 3        # THIS fork's real key (not EFBScale!); default 1; MaxInternalResolution = 12
ShaderCache = True
ShaderCompilationMode = 2
WaitForShadersBeforeStarting = True
```
- Scale clamps to window width at INIT (640-wide EFB × multiplier). 1920-wide window → 3× = 1920×1584. No live recompute on resize. Bigger window/fullscreen at boot → higher multiplier (2560 window → 4×, 3440 → 5×).
- `ShowInternalResolution = True` gives an on-screen numeric readout.
- Widescreen: `AspectRatio = 1`, `WideScreenHack = True`, optional `CustomAspectRatioWidth/Height` (tried, not fully validated).

### Dolphin.ini (performance tuning — final recommended state)
```
[Core]
CPUCore = 6
GFXBackend = Vulkan
AudioLatency = 80          # default 20; 4x helps shallow dips
AudioBufferSize = 320      # default 80
OverclockEnable = False    # tested: NET NEGATIVE (see perf results)

[DSP]
Backend = Pulse
DSPThread = True
```

---

## Part 4 — Bugs & findings (mirrors the GH issue filed)

1. **Compiled module rejected:** `initialization failed: native module was rejected` (or black screen) with both C and LLVM backends. Interpreter mode (`--allow-interpreter`, no `--module`) runs everything: intro, menus, full gameplay, audio. Suspect Factor 5 SMC (self-modifying code, intentionally unhandled by DolRecomp) or module validation bug. Multiple toolchain-identity cache entries complicate module selection.
2. **SC2/SDL pin:** native input requires SDL ≥3.4.10; pin is 3.4.4 → Steam Input workaround.
3. **Purple framebuffer flashes** between scene transitions — uninitialized buffer shown briefly, cosmetic.
4. **Internal res clamps at init,** no resize recompute.
5. **PAL 60Hz in-game toggle works** (50→60 fps).
6. GH issue drafted: see "Rebel Strike Issue Report" artifact / posted on ExpansionPak tracker.

### Performance results (heavy combat worst-case, Steam overlay readings)
| Config | fps floor | Audio |
|---|---|---|
| Defaults (lat 20 / buf 80, no OC) | 35 | stutter/crackle |
| AudioLatency=80, AudioBufferSize=320 | 33–35 | buffered, no crackle at shallow dips |
| OC 1.5× + default buffers | 27 | effects duplicate/retrigger |
| OC 2.0× | low | severe duplication |
| SyncGpuOverclock 1.5× | same as none | no change |

Conclusion: interpreter is single-thread-bound; clock overclocking hurts both fps and audio; buffer enlargement is a mild win; DSPThread=True (already default in written ini). Best config = buffers up, OC off, 50Hz mode.

---

## Part 5 — Rebuild-from-scratch cheat sheet

```bash
# 1. Container
distrobox enter decomp-env

# 2. Toolchain (once per box)
sudo apt-get install g++-13          # + LLVM 20 pkgs from apt.llvm.org (see Part 1)

# 3. Build from clean
cd ~/Games/GC/ModernGekko-Template
rm -rf lib/ModernGekko/build vendor/dolphin/DolRecomp/build
CC=gcc-13 CXX=g++-13 \
LLVM_ROOT=/usr/lib/llvm-20 CMAKE_PREFIX_PATH=/usr/lib/llvm-20 \
  make run ISO=~/Games/GC/iso/rebel_strike.iso        # builds C module + launches
# (interpreter launch happens via script below; module currently unused)

# 4. Launch (any time)
~/Games/GC/ModernGekko-Template/launch-rebel-strike.sh          # from box or host
# or via host shim:
moderngekko-rebel-strike                                        # or --scale fhd
# or via Steam (non-Steam-game entry pointing at the shim)

# 5. Update project
git pull && git submodule update --init --recursive
# then repeat step 3 clean build

# 6. Backup (saves + tuned configs)
cp -r ~/.local/share/moderngekko ~/backups/moderngekko-$(date +%F)
```

**Wishlist status:** ✅ Steam launch without distrobox friction · ✅ Controls (Steam Input path) · ✅ Upscaling (internal 3–5×, window-clamped) · 🔲 True widescreen (partial) · 🔲 Compiled-module fix (upstream) · 🔲 >60Hz (engine-locked; upstream feature request).

**Key lesson bank:** CMake caches → nuke real build dir on toolchain change · config key names come from GraphicsSettings.cpp/MainSettings.cpp, not stock Dolphin docs · apt.llvm.org needs pinning with mixed suites · GCC13-compiles + LLVM20-backend is the working pairing · interpreter needs no module at all.
