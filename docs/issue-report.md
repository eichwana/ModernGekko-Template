# Rebel Strike (GLRP64): compiled module rejected / black screen, interpreter runs at 50 fps — full test report

## Environment

- **Host:** Bazzite (Fedora-based, Wayland), AMD GPU, 3440×1440 display
- **Container:** Ubuntu 22.04 (jammy) distrobox
- **Build toolchain:** GCC 13 (g++-13), CMake/Ninja, `-DCMAKE_BUILD_TYPE=Release`
- **LLVM backend:** LLVM/Clang 20.1.8 from apt.llvm.org (`LLVM_DIR=/usr/lib/llvm-20/lib/cmake/llvm`)
- **Vendored SDL:** 3.4.4 (pin checked in `Externals/SDL/SDL`, tag `release-3.4.4`, dated 2026-04-03)
- **Game:** Star Wars Rogue Squadron III: Rebel Strike, PAL, GLRP64 (legally owned dump)
- **Date:** 2026-11-10, submodules cloned a few days prior

## Bug 1: compiled module rejected at load; interpreter mode works

**Symptom:** Both backends compile successfully end-to-end (~1776 ninja targets), but at launch:

- With compiled module: `initialization failed: native module was rejected` (or a black screen with audio, depending on build/cache state)
- With `--allow-interpreter` and no `--module`: **game runs fine — intro cutscene, menus, full gameplay with working audio**

Repro:

```
make llvm-run ISO=<pal iso>          # builds fine, module rejected at runtime
make run ISO=<pal iso>               # C backend: same runtime rejection
moderngekko-run --game extracted/rebel-strike --allow-interpreter   # works
```

Additional observations:

- Module cache contains multiple entries per DOL hash, one per toolchain identity (switched compilers several times during setup: clang-20/libc++, g++-12, g++-13). The runner picked by mtime among these and behavior differed depending on which was selected — stale/incompatible entries are not obviously distinguishable from the outside.
- Suspect the game's self-modifying-code usage (Factor 5 title) may be a factor, since the interpreter (which re-fetches code each cycle) works while statically translated modules fail.

## Bug 2: Steam Controller 2 (2026) input only works via Steam Input

The vendored SDL is 3.4.4. Native (no-Steam) support for the 2026 Steam Controller landed in SDL 3.4.0, but the controller's post-May-22 firmware (Bluetooth transport change) requires **SDL 3.4.10+**. Result: with the bundled 3.4.4, the controller is only visible when the Steam client is running (Steam Input virtual gamepad); native mode does not work.

Workaround: run with Steam open, bind `Device = SDL/0/Steam Virtual Gamepad` in `GCPadNew.ini`. Works perfectly, including analog triggers.

Suggestion: consider bumping the SDL submodule pin to ≥ 3.4.10.

## Graphics findings

- **Internal resolution works but clamps at init.** `InternalResolution` (GFX.ini `[Settings]`) is honored, but the EFB scale is computed once at startup from the window width (EBF 640 wide, so a 1920-wide window → 3×, 1920×1584 internal). Resizing/maximizing the window afterwards does not recompute (`RecreateEFBFramebuffer` never fires on resize as far as I can tell). Request: a boot-time fullscreen/size option, or resize recompute.
- **PAL 60Hz toggle works** (in-game prompt) — fps goes 50 → 60 in the overlay.
- **Purple/magenta flashes between scene transitions** (title → menu → gameplay). Looks like an uninitialized framebuffer displayed for a few frames during swap. Cosmetic.
- Ultrawide: works pillarboxed/stretched per aspect settings; no crashes either way.

## Performance data (interpreter mode, single-thread bottleneck)

Config under test: `AudioLatency`/`AudioBufferSize` in Dolphin.ini `[Core]`, `Overclock`/`OverclockEnable`, `SyncGpuOverclock`. MangoHud/Steam overlay readings, heavy combat scene (worst case):

| Config | fps floor | Audio |
|---|---|---|
| Defaults (20/80, no OC) | 35 | stutter/crackle under load |
| AudioLatency=80, AudioBufferSize=320 | 33–35 | stutter but buffered (no crackle at shallow dips) |
| OC 1.5× + default buffers | 27 | sound effects duplicate/retrigger |
| OC 2.0× | low | severe duplicated audio |
| SyncGpuOverclock 1.5× | same as no-OC | no change |

Conclusions from testing: emulated-clock overclocking is a net negative for this title under the interpreter (fps and audio both degrade); audio buffer enlargement is a mild win; `DSPThread = True` (already default in the written Dolphin.ini) keeps DSP off the interpreter core. The interpreter is single-thread-bound (~1 core saturated, overall CPU usage low), so headroom fundamentally requires the native module path.

## What works well

For the record — and it's a lot: full boot through menus into gameplay, solid 50 fps (PAL) in most content, working audio, working GameCube controller input via Steam Input, internal EFB scaling, Vulkan backend, PAL 60Hz mode. On an interpreter. This is the furthest Rebel Strike has ever run on a static recompilation to my knowledge. Happy to test patches for the module rejection — I have a reproducible environment set up (jammy distrobox, GCC 13, LLVM 20.1.8) and can iterate quickly.
