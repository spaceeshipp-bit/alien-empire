# Builder handoff

Updated 2026-11-11. Read this first, then `docs/ENGINEERING.md` (the standing rules and quality bar), `docs/milestones/M0.md`, `docs/DECISIONS.md` and the "Working rules for the AI builder" in `docs/BUILD_PROMPT.md`. This file is the current plan only: replace each step as it lands. Commits are named by subject, because cherry-picks give them new IDs on the milestone branch.

## Where things stand

- **M0 is built and green in CI** on `m0-foundations`. `docs/milestones/M0.md` names the green `m0-foundations` run for this code.
- **M0 is not done.** It's done when the owner's phone shows **Sim tests: ALL CHECKS PASS** and every Plugin Lab check passes (`docs/PLUGINS.md`). Nothing merges into `main` before that. Don't start M1 code on `m0-foundations`.
- **The sim is C++ in a GDExtension** (D-026). GDScript parses and checks inputs and wraps the core. The build prompt's "pure GDScript" line waits on the owner's doc (see Owner actions).
- **What the phone checks now:**
  - 35 unit tests;
  - 4 hand-written goldens;
  - 40 generated battles whose results come from an independent reference model (D-028), with 912 checkpoints.

  The screen names its build ("build 2601 · abc1234"), so a screenshot ties to a commit. It also shows the sim's speed in ns per alien-tick, which fills M0's last empty speed row.
- **Reviews done.** Two rounds this session, each with one reviewer for the code and one for the docs. Every finding was checked by reproducing it before it was fixed.
  - The first round reviewed the previous session's fixes and its plan. The second reviewed this session's own work.
  - Every confirmed problem is fixed. See the commits from "Sim tests: fail a test file that doesn't compile" through "Sim tests: every checkpoint must match; record and JSON gaps closed", "Core check: blame crashes on their battle; shrink with the failing build" and the docs corrections.
  - The fixes were checked against Godot 4.7.2 itself, using CI's built library locally. One suggested fix wouldn't have worked: Godot reports a failed compile only on the script with the error, not on scripts that depend on it.
  - The hardening the previous handoff planned is done: D-028's model and fuzz, the `core-agree` job, the version-skew guard, the missing-library note, the phone speed line and `docs/LICENSES.md`.
  - The second review also found the sim library was built with an older NDK than the C++ runtime Godot ships in the APK. It's now built with Godot's NDK, and CI checks it will load on Android (D-030).

## Plan

### Step 1. The owner's phone check (now)

Tell the owner the APK to install is the newest green CI run on `m0-foundations`. Steps 1 to 8 of the walkthrough in `docs/PLUGINS.md`; screenshots come back.

When they arrive:
1. Check the build line on the Sim tests screenshot matches the newest commit on `m0-foundations`. If it's older, ask for Sim tests again on the newest build. Only the build that merges counts (rule 9 in `docs/ENGINEERING.md`).
2. If a check fails, fix it on the session branch, with a test that would have caught it where one can exist. Review the fix, cherry-pick it onto `m0-foundations`, and send that run's APK. Don't work around a failing check.

### Step 2. Finish M0 when the phone passes

After the phone passes, only docs may change before the merge. Anything else means a new APK and a new phone run (rule 9).

1. In `docs/milestones/M0.md`, record:
   - the build line from the screenshot, and the merge commit's CI run;
   - the Sim tests result: unit tests, the 4 goldens and the 40 generated battles;
   - the phone's ns per alien-tick, in the speed table;
   - each Plugin Lab check.
2. Tick the last boxes. Write the close-out the working rules ask for: what changed, how to try it, open issues.
3. Run the review protocol over everything since the last review (`docs/ENGINEERING.md`). If a fix touches anything but docs, it needs a new APK and phone run first.
4. Ask the owner to confirm. Then merge `m0-foundations` into `main` with a merge commit, and branch `m1-pve-slice` from `main`.

### Step 3. M1 PvE slice

The plan is `docs/milestones/M1.md`: scope, the owner's questions with recommendations, defaults, systems with their files and tests, order of work and risks. The owner has it with the M0 phone check.

1. When the answers arrive, record each in `docs/DECISIONS.md` (Q2, Q3 and Q4 move from open questions to decisions) and update M1.md.
2. Branch `m1-pve-slice` from `main` once M0 has merged. Not before.
3. Build in M1.md's order, with the full quality bar on every system. Each rule change raises `SIM_VERSION` and follows "Changing a sim rule" in `docs/ENGINEERING.md`.
4. The reference model changes character in M1. Combat decides who lives, so it steps tick by tick, but it keeps its own structures, such as brute-force targeting. Keep generated battles small enough for CI.

### Later milestones

Follow the build prompt's order. Standing concerns to carry forward:

- **M2:** measure the raid replay budget on the real sim as soon as raid units exist; don't wait for M4's formal check.
- **M4:**
  - The worker loads a build of the same sim source and `SIM_VERSION` as the phone. The server keeps every `SIM_VERSION` still in use, so plan before the first live battle record how old libraries are stored and chosen.
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
| Answer M1's questions: the 3 towers and 3 aliens, field-tower upgrades and selling, lives, jitter, credits, the wave timer, the pressure terms, and when real art arrives (M1-G) | Needed before M1 starts | `docs/milestones/M1.md` |
| Say which phone is your low-end test phone (M1-D) | M1 must hold 60 fps on a low-end phone | `docs/milestones/M1.md` |
| Q8, Gradle cache terms | Optional | `docs/DECISIONS.md` |
