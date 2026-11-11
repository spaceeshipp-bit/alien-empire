# Builder handoff

Updated 2026-11-11. Read this first, then `docs/ENGINEERING.md` (the standing rules and quality bar), `docs/milestones/M0.md`, `docs/DECISIONS.md` and the "Working rules for the AI builder" in `docs/BUILD_PROMPT.md`. This file is the current plan only: replace each step as it lands. Commits are named by subject, because cherry-picks give them new IDs on the milestone branch.

## Where things stand

- **M0 is built and green in CI** on `m0-foundations`. `docs/milestones/M0.md` names the newest green run.
- **M0 is not done.** It's done when the owner's phone shows **Sim tests: ALL CHECKS PASS** and every Plugin Lab check passes (`docs/PLUGINS.md`). Nothing merges into `main` before that. Don't start M1 code on `m0-foundations`.
- **The sim is C++ in a GDExtension** (D-026). GDScript parses and checks inputs and wraps the core. The build prompt's "pure GDScript" line waits on the owner's doc (see Owner actions).
- **What the phone checks now:**
  - 35 unit tests;
  - 4 hand-written goldens;
  - 40 generated battles whose results come from an independent reference model (D-028), with 912 checkpoints.

  The screen names its build ("build 2601 · abc1234"), so a screenshot ties to a commit. It also shows the sim's speed in ns per alien-tick, which fills M0's last empty speed row.
- **Reviews done.** The handoff's step 1 review ran: one reviewer for the code fixes and the CI `core` job, one for the docs and this plan. Each finding was then checked by reproducing it.
  - Every confirmed problem is fixed. See the commits "Sim tests: fail a test file that doesn't compile", "Sim loader: refuse decimal notation in JSON", "sync_sim: say when there's no library; test sync() itself", "Client: catch a library from another build; show the build and speed" and the docs corrections.
  - The fixes were checked against Godot 4.7.2 itself, using CI's built library locally. One suggested fix wouldn't have worked: Godot reports a failed compile only on the script with the error, not on scripts that depend on it.
  - The handoff's step 2 (harden M0 while waiting for the phone) is done: D-028's model and fuzz, the `core-agree` job, the version-skew guard, the missing-library note, the phone speed line and `docs/LICENSES.md`.

## Plan

### Step 1. The owner's phone check (now)

Tell the owner the APK to install is the newest green CI run on `m0-foundations` (its number is in M0.md). Steps 1 to 8 of the walkthrough in `docs/PLUGINS.md`; screenshots come back.

When they arrive:
1. Check the build line on the Sim tests screenshot matches the newest commit on `m0-foundations`. If it's older, ask for Sim tests again on the newest build. Only the build that merges counts.
2. If a check fails, fix it on `m0-foundations`, with a test that would have caught it where one can exist, and send a new APK. Don't work around a failing check.

### Step 2. Finish M0 when the phone passes

1. In `docs/milestones/M0.md`, record:
   - the Sim tests result: unit tests, the 4 goldens and the 40 generated battles;
   - the phone's ns per alien-tick, in the speed table;
   - each Plugin Lab check.
2. Tick the last boxes. Write the close-out the working rules ask for: what changed, how to try it, open issues.
3. Run the review protocol over everything since the last review (`docs/ENGINEERING.md`). Fix what survives.
4. Ask the owner to confirm. Then merge `m0-foundations` into `main` with a merge commit, and branch `m1-pve-slice` from `main`.

### Step 3. M1 PvE slice

The build prompt's M1: "one map, 3 towers, 3 aliens, 10 waves, field towers, placeholder art". Done when it holds 60 fps on a low-end phone and wave pressure is within target.

Before any code, post the plan the working rules require (systems, files, tests) and get the owner's answers. They need:
- Q1 to Q3 in `docs/DECISIONS.md`: Hive Carrier leak lives, starting lives, spawn jitter;
- which 3 towers and 3 aliens make the slice. `config/balance/` has all six of each;
- whether M1's field towers include upgrades and selling. The rules are in the build prompt's field tower upgrade line; how to read them is Q4, due by M2 by default. If they're in M1, Q4 moves to M1.
- which phone counts as low-end, and whether the owner has one.

Use a default only where the owner says so.

Build in this order, each with the full quality bar:

1. **Battle state in the core, data-oriented.**
   - Towers, hits and aliens live as flat arrays in ID order.
   - Extend the state hash for every new field, in a documented order.
   - Raise `SIM_VERSION`, then follow "Changing a sim rule" in `docs/ENGINEERING.md`: model, generated battles, goldens.
2. **Command log.**
   - Field-tower placement, with a tick. Upgrade and sell only if they're in M1.
   - `battle_spec.gd` already refuses unknown commands. Add each known one with range checks on both sides: the GDScript loader and the C++ setup.
   - Teach the generator to emit commands, valid and out of range, and teach the model to apply them.
3. **Targeting.**
   - A spatial grid. A unit re-picks every few ticks, and when its target dies or leaves range, never every tick for a unit with no target (D-026's last benchmark row shows why). Ties break by ID.
   - The model finds targets by brute force over all units in ID order, so the fuzz checks the grid against an answer that doesn't use one.
4. **Damage pipeline**, exactly in the build prompt's order, with every value from config. State the integer rounding for each step, and mirror it in the model.
5. **Waves and pressure.**
   - Ten waves on one map, from config.
   - A headless balance tool computes each wave's pressure ratio as the build prompt defines it: total wave HP ÷ (spawn time + time in the kill zone), against the damage per second the credits available by that wave can buy.
   - It checks the ratio against the targets: 0.4 to 0.6 on early waves, 0.8 to 1.0 on the last wave, about 1.1 on boss waves.
   - Leak and kill rates with a fixed tower layout are an extra check, not the target.
6. **Client battle view.** It draws from core state each frame and interpolates between ticks for display only; the sim never reads anything back from the view. Measure frame time on the phone from the first build.
7. **Goldens and replay.** New scenarios with towers and commands, recorded through CI. Add a replay test: the worker replays a battle the client played, and the hashes match.

Speed checks start with the first combat commit. CI runners vary 2 to 3 times between runs (M0's speed table shows it), so don't compare against a fixed time. In the same job, time a fixed reference battle and the new code, best of several runs each, and fail on the ratio.

### Later milestones

Follow the build prompt's order. Standing concerns to carry forward:

- **M2:** measure the raid replay budget on the real sim as soon as raid units exist; don't wait for M4's formal check.
- **M4:**
  - The worker loads the same library as the phone. The server keeps every `SIM_VERSION` still in use, so plan before the first live battle record how old libraries are stored and chosen.
  - Security: the worker parses specs and command logs that come from clients. The generator already builds out-of-range battles for the C++ setup. Before exposing anything, add malformed JSON and malformed fields for the GDScript loaders.
- **M9:**
  - Real AdMob IDs, the EU consent flow and a notification icon.
  - A credits screen from `docs/LICENSES.md`, with the exact dependency list generated from the release build.
  - Exclude the AdMob addon's editor and sample assets from release exports: 2.4 MB of logos, a font and music that the game doesn't use (`docs/LICENSES.md`).
- **Windows and macOS editors** need `tools/build_sim_native.sh` and `sim/aetd_sim.gdextension` extended. Do it only when someone needs it.

## Owner actions outstanding

| What | Why | Where |
| --- | --- | --- |
| Install the newest APK from `m0-foundations`. Run Sim tests and AdMob (step 1), do the one-time console setup and the other four checks (steps 2 to 7), and send screenshots (step 8). | Finishes M0 | `docs/PLUGINS.md` |
| Until your upload key exists (step 2), uninstall the old app before installing a newer build: each build has a new throwaway key. | Android refuses to update an app signed with a different key | `docs/PLUGINS.md` step 1 |
| Update your build prompt's Sim core line | D-026 changed it; the proposed wording is in D-026 | Your build prompt doc |
| Answer Q1 to Q3, choose M1's 3 towers and 3 aliens, and say whether M1's field towers include upgrades and selling | Needed before M1's waves, lives and commands | `docs/DECISIONS.md` |
| Say which phones you have | M1 must hold 60 fps on a low-end phone | Reply in the next session |
| Q8, Gradle cache terms | Optional | `docs/DECISIONS.md` |
