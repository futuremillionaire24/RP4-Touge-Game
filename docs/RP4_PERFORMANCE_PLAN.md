# RP4 Performance & Immersion Plan

Revision of the Antigravity draft "RP4 Performance Profiling, Memory Optimization & Immersion
Hardening" (2026-09-24). Target: **Retroid Pocket 4 Pro** (Dimensity 1100, Mali-G77 MC9, 1334x750,
60 Hz panel), Godot 4.7.2 Mobile renderer, holding 60 fps in free roam and races, day and night.

## What changed from the draft

Merged in the meantime (PR #1, `10a71cd` / `a72a976`), so dropped from this plan:

* Shadow cascades follow the graphics setting (low 2 x 160 m, high 4 x 220 m, ultra 4 x 280 m),
  default / High tier = low; **no sun shadow pass at night**.
* Streaming rings on High tier `[1,2,3,5]` (121 chunks, was 225); only the nearest ring casts
  shadows; ring LODs drop kerbs/posts and merge surfaces.
* Far prop meshes (~200 tris) for trees and yachts; prop shadows only in the nearest ring.
* Measured on desktop at La Condamine: day 1310 -> 593 draws, night 1415 -> 431 draws;
  3.1 M -> 0.94 M primitives.

Corrected targets: the draft's "<= 75 draw calls" is not achievable for a streamed open city and
is not what limits a Mali-G77 (Vulkan command cost is low; fragment load and bandwidth are what
matter). Budgets below are per frame on the RP4.

## Budgets (RP4, 1334x750, MSAA 2x+)

| Metric | Day | Night |
|---|---|---|
| Average fps | 60 | 60 |
| 1% low | >= 50 fps | >= 50 fps |
| GPU time | <= 15 ms | <= 15 ms |
| CPU (process + render thread) | <= 12 ms | <= 12 ms |
| Draw calls | <= 650 | <= 650 |
| Primitives | <= 1.2 M | <= 1.2 M |
| Video memory | <= 1.2 GB | <= 1.2 GB |

The adaptive governor (`Perf`) may drop render scale to 0.8 before touching MSAA; the audit
records the governor tier and scale so "60 fps at tier 3" is visible as a miss, not a pass.

## Work items

1. **Measurement (new).**
   * `godot/qa/perf_audit.gd` (scene `perf_audit`): loads free roam at a fixed spot and runs the
     scenarios Day stationary, Day driving (AI autodrive), Night stationary, Night driving. Per
     scenario: fps avg / 1 % low, CPU and GPU frame time (viewport measured), draw calls,
     primitives, objects, video and static memory, governor tier / scale, thermal headroom.
     Results as one `PERFJSON {...}` line each (logcat on device) plus `user://perf_report.json`.
   * `tools/profile_device.ps1`: desktop baseline, then installs the APK, launches the audit on
     the RP4 through the `command_line_params` intent extra, collects the `PERFJSON` lines from
     logcat, writes `build/qa/perf/report.md` (side-by-side table).
2. **Android build.** Rebuild `libneontouge` arm64 (debug + release) from the committed source and
   export the APK (`tools/export-android.ps1`).
3. **Optimise from the data.** Candidates, applied only where the audit shows the cost:
   * facade: skip shop-interior parallax / shelves and railing bars once the pixel footprint is
     large (distant walls);
   * water: capillary ripples and rain rings only within ~120 m;
   * street furniture visibility ranges on mobile tiers (bins, bollards, hydrants 50-60 m,
     benches 70 m);
   * `LightPool` 4 lights below High tier, 10 Hz reassignment when the camera barely moves;
   * memory: `WorldMaterials.clear_cache()` / `PropLibrary.clear_cache()` and streamer teardown
     when leaving free roam, so returning to the festival frees the world's textures and meshes.
4. **Verify.** `scene=check` (all scripts compile), native test suite, audit on desktop and RP4
   against the budgets above; results recorded below.

## Results

### Desktop baseline (2026-09-25, Ryzen 7 1700X, 75 Hz vsync, La Condamine, Golf GTI)

| Scenario | fps avg | 1% low | GPU ms | CPU ms | draws (+shadow) | prims | VRAM MB | tier / scale |
|---|---|---|---|---|---|---|---|---|
| day_parked | 75.7 | 60.4 | 6.25 | 1.49 | 139 (+19) | 640k | 477 | 0 / 0.95 |
| day_driving | 76.7 | 60.9 | 6.23 | 1.49 | 128 (+23) | 719k | 479 | 0 / 1.0 |
| night_parked | 76.1 | 53.1 | 6.12 | 1.35 | 139 (+0) | 639k | 479 | 0 / 1.0 |
| night_driving | 76.6 | 53.4 | 5.28 | 1.34 | 129 (+0) | 726k | 479 | 0 / 1.0 |

Night has no sun shadow pass (0 shadow draws). The night 1% lows come from occasional 20-50 ms
frames (streaming / shader compiles), not from sustained load.

### RP4

Pending: the APK (v0.5.0, code 3) is installed, but the device has a secure lock screen, so the
audit can only run once it is unlocked (a locked device pauses the game). Run
`tools\profile_device.ps1 -NoInstall` with the RP4 unlocked; it keeps the screen on while
profiling.
