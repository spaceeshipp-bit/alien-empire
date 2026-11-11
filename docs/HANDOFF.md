# Builder handoff

Written 2026-11-11 for the next builder session. Read this first, then `docs/milestones/M0.md`, `docs/DECISIONS.md` and the "Working rules for the AI builder" in `docs/BUILD_PROMPT.md`. Delete each section here as its work lands; the milestone docs are the lasting record.

## Where things stand

- **M0 is built and green in CI.** Every job passes: config and tools, the C++ sim core on x86-64 and ARM, sim tests on the headless worker and the desktop client, and the Android APK with all five plugins and the sim library inside.
- **M0 is not done.** It is done when the owner's phone shows **Sim tests: ALL CHECKS PASS** and every Plugin Lab check passes (`docs/PLUGINS.md`). Nothing merges into `main` before that. Do not start M1 code on `m0-foundations`.
- **The sim is C++ in a GDExtension** (D-026). GDScript parses and checks inputs and wraps the core. The build prompt's "pure GDScript" line is waiting on the owner's doc (see Owner actions).
- **Reviewed.** A 47-agent adversarial review of the C++ port, with a 1,800-spec differential fuzz against the old GDScript sim, found no mismatch and no determinism defect. Its ten confirmed findings (one loader bug, CI and tooling gaps, doc errors) are fixed. A second review of those four fix commits (`a4421ac`, `b09950b`, `e346d04`, `9133f94`) did not run. Do it first: it is step 1 below.

## Hard rules, on top of the build prompt's

1. **Never build godot-cpp or run `tools/build_sim_native.sh` in the cloud workspace.** It is refused there. CI builds the library; locally use `tools/check_sim_native.py`, the tool tests and Godot without the library.
2. **Never `git reset --hard`, never force-push `m0-foundations` or `main`.** Iterate on the session branch, then cherry-pick clean commits onto `m0-foundations`.
3. **The repo is public.** Keys, `google-services.json` and account IDs live only in Actions secrets and variables (D-020, D-021).
4. **`docs/BUILD_PROMPT.md` is a copy of the owner's doc.** Change it only when the owner's doc changes, in the same commit as a decision entry.
5. **A change that can alter a battle's result bumps `SIM_VERSION`** in `sim/native/src/core/fx.h` and re-records the goldens through CI (D-008). A change that cannot must say why in its commit message.
6. **No float or double in `sim/native/src/core/`**, no hashed-container iteration, no sort on non-unique keys, no engine random or time. A tool test enforces the first; the rest are review items.
7. **Every balance number lives in `config/`** with its knob documented in the schema.
8. **Claims need evidence.** "Passes" means a command's output or a CI run ID. A number in a doc names where it was measured.

## The quality bar for every piece of work

Each system ships with all of these, or the reason one doesn't apply is written down:

| Layer | What it is | Where |
| --- | --- | --- |
| Unit tests | Each rule alone, including the refusals | `sim/tests/unit/`, `tools/tests/` |
| Sanitizer run | The C++ core under UBSan and ASan, on x86-64 and ARM, g++ and clang++ | `tools/check_sim_native.py`, CI job `core` |
| Golden battles | Fixed scenarios, final hash and every checkpoint | `sim/tests/golden/` |
| Reference model | A second, independent implementation of each new rule (Python), compared with the core on generated cases | extend `tools/gen_vectors.py` and the vectors |
| Differential or property fuzz | Random valid inputs: same result twice, same result on a reused battle, invariants hold (HP never rises without a heal, IDs ascend, no entity outside the map) | new, see step 3 |
| Misuse tests | Wrong order of calls, refused inputs, reuse after failure | core check and unit tests |
| Adversarial review | Independent reviewers with different lenses, then skeptics who try to refute each finding; fix what survives | before every merge to a milestone branch |
| Phone check | The owner runs it on a real device | walkthrough in the milestone doc |

Reviews so far paid for themselves: they caught a use-after-free in battle reuse, a loader that refused a valid seed, a CI dead end for re-recording goldens, and several wrong numbers in docs. Keep doing them, and keep the skeptic pass so findings are real.

## Plan

### Step 1. Close out the current branch (small)

1. Re-run the review that didn't run: one reviewer for the code in `a4421ac`, `b09950b`, `e346d04` and the CI `core` job, one for the docs in `9133f94` and this file, two skeptics per finding. Fix what survives.
2. Confirm the newest CI run on `m0-foundations` is green, including all four `core` matrix jobs, and that `aetd-m0-debug.apk` is in its artifacts.
3. Tell the owner the APK to install is the newest green run on `m0-foundations`.

### Step 2. While waiting for the phone (no M1 code yet)

These harden M0 and cost the owner nothing. Each is its own commit with tests.

1. **Property fuzz in CI.** Add a fuzz mode to `tools/check_sim_native.py`: a few hundred seeded random specs per run through the sanitizer build, checking run-twice equality, reuse equality and invariants. Seeded, so a failure reproduces. The earlier differential harness is gone with the old GDScript sim; this replaces it.
2. **Cross-platform hash proof.** The `core` job already runs goldens on ARM. Add its fuzz hashes as an artifact from x86-64 and ARM and compare them in a final job, so any platform divergence fails CI before a phone sees it.
3. **Version-skew guard.** If the library loads but the sim scripts don't compile, the phone's Sim tests screen stays on "Running…". Make `client/ui/sim_library.gd` detect a null report script and show a message. Add the `SIM_VERSION` the app expects next to the one the library reports.
4. **`sync_sim.py --check` when `sim/bin/` is empty.** It passes today. Make it say the library is missing, without failing the tools job, which runs before the build.
5. **Phone speed line.** Have the Sim tests screen print ns per alien-tick like the worker does, so the first phone screenshot fills the last empty row of M0's speed table.
6. **Credits file.** Start `docs/LICENSES.md` listing Godot, godot-cpp and each plugin with license and notice text (the build prompt's rule on recorded licenses; D-026 promises godot-cpp's notice in the credits).

### Step 3. When the phone passes: finish M0

1. Record the owner's screenshots' results in `docs/milestones/M0.md` (hashes match on ARM, each plugin check, phone speed).
2. Tick the last two boxes, write the "what changed, how to try it, open issues" close-out the working rules ask for.
3. Ask the owner to confirm, then merge `m0-foundations` into `main` with a merge commit. Only then branch `m1-pve-slice` from `main`.

If a phone check fails, fix it on `m0-foundations`, with a test that would have caught it where one is possible, and send a new APK. Do not work around a failing check.

### Step 4. M1 PvE slice

Done when it holds 60 fps on a low-end phone and wave pressure is within target. Before any code, post the plan the working rules require (systems, files, tests) and get answers to Q1 to Q3 in `docs/DECISIONS.md`: Hive Carrier leak lives, starting lives, spawn jitter. Use the defaults there only if the owner says so.

Build in this order, each with the full quality bar:

1. **Battle state in the core, data-oriented.** Towers, projectiles or instant hits, and aliens as flat arrays in ID order. Extend the state hash for every new field, in a fixed documented order, and bump `SIM_VERSION`.
2. **Command log.** Field-tower place, upgrade and sell as commands with a tick. `battle_spec.gd` already refuses unknown commands; add each known one with range checks on both sides (GDScript loader and C++ setup).
3. **Targeting.** Spatial grid, re-pick every few ticks and when a target dies or leaves range, never every tick for a unit with no target (D-026's last benchmark row shows why). Ties break by ID.
4. **Damage pipeline** exactly in the build prompt's order, all values from config, integer rounding stated for each step and mirrored in the Python reference.
5. **Waves and pressure.** Ten waves on one map from config; a headless tool that plays them with a fixed tower layout and reports leak and kill rates against the target.
6. **Client battle view.** Draws from core state each frame, interpolating between ticks for display only. The sim never reads anything back from the view. Measure frame time on the phone from the first build.
7. **Goldens for M1.** New scenarios with towers and commands, recorded through CI, plus a replay test: the worker replays a battle the client played and the hashes match.

Budget checks from the first combat commit: the worker prints ms per battle; fail CI if a reference M1 battle takes more than a set time on the runner, so a slowdown is seen the day it lands.

### Later milestones

Follow the build prompt's order (M2 full combat, M3 base, M4 backend, M5 raids, and on). Standing concerns to carry forward:

- **M2:** the raid replay budget is measured on the real sim as soon as raid units exist; don't wait for M4's formal check.
- **M4:** the worker loads the same library as the phone; the server keeps every `SIM_VERSION` still in use, so plan how old libraries are stored and selected before the first live battle record.
- **M4, security:** the worker parses specs and command logs that come from clients. Fuzz the GDScript loaders and the C++ setup with malformed input before exposing them.
- **M9:** real AdMob IDs, EU consent, notification icon, credits screen from `docs/LICENSES.md`.
- **Windows and macOS editors** need `tools/build_sim_native.sh` and `sim/aetd_sim.gdextension` extended. Do it only when someone needs it.

## Owner actions outstanding

| What | Why | Where |
| --- | --- | --- |
| Install the newest APK from `m0-foundations`, run Sim tests and the Plugin Lab, send screenshots | Finishes M0 | `docs/PLUGINS.md` |
| Update the build prompt's Sim core line | D-026 changed it; proposed wording is in D-026 | The owner's build prompt doc |
| Answer Q1 to Q3 | Needed before M1's waves and lives | `docs/DECISIONS.md` |
| Q8, Gradle cache terms | Optional | `docs/DECISIONS.md` |

## How to verify anything locally

```sh
python3 tools/config_tool.py validate
python3 tools/gen_vectors.py --check
python3 -m pytest -q tools/tests
python3 tools/check_sim_native.py        # the C++ core, sanitizers, vectors, goldens
```

Godot tests with the library run only in CI. Read a run's results from the job logs: the worker prints one line per golden with its hash and ns per alien-tick.
