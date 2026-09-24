# Neon Touge perfection loop: orchestration protocol

The orchestrator (the main Claude session, running `/loop`) follows this file on every wake-up.
Pieces are defined in `pieces.json`. Live state is in `D:\Android_RP4_Game\dist\progress\`, served at
http://localhost:8080/dashboard.html by `tools/serve-dashboard.ps1`.

## Stop rule (user's choice, literal)
A piece is **PASSED** only when, in the same round:
1. the blind judge picks ours in a majority of the matched pairs, **and**
2. the on-device critic reports `wowed: true`.

No fixed number of rounds. Passed pieces are re-checked after every coherence pass and reopen if they regress.

## Roles (each is a fresh sub-agent; none sees another's reasoning)
| Role | Sees | Never sees | Output |
|---|---|---|---|
| Builder (per piece) | piece definition, the critic's gap report + judge reason from the last round | — | commits on `piece/NN` in `D:\RP4wt\pNN` |
| Critic (per piece, device-exclusive) | the APK running on the RP4, reference images | builder summaries, git log/diffs, commit messages, dashboard notes | critique JSON + matched pairs |
| Blind judge (per round) | anonymised `pair_N/A.png`, `B.png`, piece criterion | which side is ours, critic's report | verdict JSON |
| Coherence agent (between waves) | the whole game on the device | builder summaries | commits on `coherence/W` |

## Round for piece NN
1. **Build** — builder in worktree `D:\RP4wt\pNN` (branch `piece/NN`). It merges `main` first and commits when done.
   Status BUILDING → BUILT.
2. **Integrate** — orchestrator merges `piece/NN` into `main` (resolving conflicts). It rebuilds native code if C++ changed
   (`tools/build-native.ps1 -Platform all`) and commits the binaries. It exports the APK
   (`tools/export-android.ps1 -SkipNative`) and copies it to `dist\builds\NeonTougeRP4-<sha>.apk`. Status INTEGRATING.
3. **Critique** — one critic at a time owns the RP4 (the device queue is FIFO). It installs the given APK, runs the
   piece's scenario through `tools/perfection/rp4_capture.ps1`, and looks at every capture. It picks references from
   `dist\progress\refs\NN\` (and fetches more if needed), writes matched `ours_N.png`/`ref_N.*` pairs, and writes
   `critique.json`. Status CRITIQUING.
4. **Blind judge** — orchestrator runs `blind_pair.py make` and gives the judge only the blind directory. Then it runs
   `blind_pair.py unblind`. Status JUDGING.
5. **Decide** — the piece passes if (majority ours) and critic `wowed`. Otherwise it is LOST, and the builder goes back in
   with the critic's single biggest gap plus the judge's reason. The result is recorded with `progress.py piece NN ... --history`.

## Waves
Waves come from `pieces.json`. Every piece in a wave loops independently: its build → device queue → critique → judge
→ build cycle runs in parallel with the others, and only the device is serialised. A wave visit ends when each of its
pieces has passed or completed 3 rounds in this visit. Then the orchestrator runs one **coherence agent**, and the
next wave starts. After wave 4 it cycles back to wave 1, carrying each piece's last gap forward.

## Files
- `dist/progress/state.json`: orchestrator-owned (wave, phase, device status, piece list).
- `dist/progress/pieces/NN.json`: live status per piece (`progress.py piece`).
- `dist/progress/feed.jsonl`: activity feed (`progress.py feed`).
- `dist/progress/refs/NN/`: reference library (refs.json lists the source URL of each image).
- `dist/progress/shots/NN/rR/`: critic captures and `pairs/`, plus `critique.json`.
- `D:\RP4wt\_blind\<token>`: anonymised pairs. `D:\RP4wt\_keys\<token>.json`: answer keys (judges must never read them).
- `D:\RP4wt\ledger.json`: orchestrator ledger (per piece: round, last gap, judge reason, APK, tokens).

## Constraints every builder must respect
- Target: Retroid Pocket 4 Pro (Dimensity 1100, Mali-G77 MC9, 1334x750 at 60 Hz, Vulkan Mobile renderer).
  60 fps locked is non-negotiable; push quality right up to that ceiling.
- Stay inside the piece's `owns` files. Touch other files only with a minimal, additive hook, and say so in the commit.
- Don't commit `godot/native/bin/*`; the orchestrator rebuilds the binaries at integration.
- Don't use the RP4. It is reserved for critics. Verify on the desktop (GTX 1050 Ti runs the same Vulkan Mobile
  renderer): run `godot --headless --path godot --script res://tools/check_scripts.gd`, run the native tests if C++
  changed, and take windowed desktop screenshots.
- Cars are REAL-WORLD JDM models with real names (user decision 2026-09-24; private sideload build, never published).
  Models come from open sources that need no login, and each one's licence and author go in
  `godot/assets/models/cars/CREDITS.md`. Everything else stays original.
- Priority (user, 2026-09-24): car pieces 01/02/03 come first; the other pieces are paused until the cars land.
