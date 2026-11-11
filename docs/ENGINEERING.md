# How this project is built

The standing rules and quality bar for every builder session, on top of the build prompt's "Working rules for the AI builder" (`docs/BUILD_PROMPT.md`). `docs/HANDOFF.md` holds the current plan; this file holds what doesn't change from one milestone to the next. Change a rule here only with a decision entry in `docs/DECISIONS.md`.

## Rules

1. **Never build godot-cpp or run `tools/build_sim_native.sh` in the cloud workspace.** It is refused there. CI builds the sim library. Locally, use `tools/check_sim_native.py`, the tool tests and Godot. CI keeps the Linux library as the `sim-native-linux` artifact: with it in the git-ignored `sim/bin/`, the worker and desktop tests run locally too.
2. **Never `git reset --hard`, and never force-push `m0-foundations`, a later milestone branch or `main`.** Iterate on the session branch, then cherry-pick clean commits onto the milestone branch. A milestone branch merges into `main` only when its "done when" checks pass on the owner's phone and the owner agrees.
3. **The repo is public.** Keys, `google-services.json` and account IDs live only in Actions secrets and variables (D-020, D-021).
4. **`docs/BUILD_PROMPT.md` is a copy of the owner's doc.** Change it only when the owner's doc changes, in the same commit as a decision entry.
5. **A change that can alter a battle's result raises `SIM_VERSION`** (`sim/native/src/core/fx.h`). The section below says what else has to change with it. A change that can't alter a result says why in its commit message.
6. **The core stays deterministic:** no float or double in `sim/native/src/core/` (a tool test enforces it), no iteration over hashed containers, no sort on keys that can tie, no engine random or time, and integer division truncates toward zero wherever it appears.
7. **Every balance number lives in `config/`,** with its knob documented in the schema.
8. **Claims need evidence.** "Passes" means a command's output or a CI run ID. A number in a doc says where it was measured.
9. **The build the phone tested is the build that merges.** After the owner's phone passes a milestone's checks, only docs may change before the merge. Any change to code, config, the sim or the export means a new APK and a new phone run of the affected checks. The milestone doc records the build line from the owner's screenshot and the merge commit's CI run.

## The quality bar

Each system ships with all of these, or the reason one doesn't apply is written down.

| Layer | What it is | Where |
| --- | --- | --- |
| Unit tests | Each rule alone, including the refusals. A test file that doesn't compile fails the run. | `sim/tests/unit/`, `tools/tests/` |
| Reference model | The rule written a second, independent way in Python, in closed form where possible | `tools/reference/sim_model.py` (D-028) |
| Generated battles | Fresh battles each CI run, matched to the model, fresh and on a reused battle, plus battles built to break the core's limits | `tools/sim_cases.py`, `tools/check_sim_native.py` |
| Sanitizers and shipped builds | The C++ core under UBSan and ASan, and as plain -O2 and -O3 builds, all answering the same | `tools/check_sim_native.py` |
| Platforms | x86-64 and ARM, g++ and clang++, with identical answers. The APK's sim library must resolve every import against the APK's C++ runtime and Android's libc (D-030). | CI jobs `core`, `core-agree` and `android` |
| Golden battles | Hand-written scenarios with hashes recorded by CI, and 40 committed generated battles with the model's results, on the worker, the desktop and the phone | `sim/tests/golden/`, `sim/tests/generated/` |
| Misuse tests | Calls in the wrong order, refused inputs, reuse after a failure | core check and unit tests |
| Mutation check | Plant a bug in the new rule and confirm a test fails. Do it once per new system; keep the notes in the commit message. | by hand |
| Independent review | Reviewers with different lenses, then skeptics who try to refute each finding. Fix what survives. Run it before cherry-picking onto the milestone branch, and again before the merge into `main`. | subagents |
| Phone check | The owner runs it on a real device | the milestone's walkthrough (M0: `docs/PLUGINS.md`) |

Reviews have paid for themselves every time. So far they have caught:
- a use-after-free in battle reuse
- a loader that refused a valid seed
- a loader that rounded decimals and zero-padded numbers silently
- golden checks that ignored every checkpoint before the last
- a test runner that skipped test files that didn't compile
- a CI dead end for re-recording goldens
- several wrong numbers in docs

## Changing a sim rule

When a change can alter a battle's result, do these steps in this order. `SIM_VERSION` is hashed into every state, so raising it changes every recorded hash.

1. Change the core, raise `SIM_VERSION` in `fx.h`, and teach `tools/reference/sim_model.py` the new rule. Raise its `MODEL_SIM_VERSION` to match. Record the rule and its integer rounding as a decision.
2. If the rule adds inputs, such as towers, commands or config fields, extend `tools/sim_cases.py` (`random_spec`, `_random_bundle`, `case_from_spec`, `driver_lines`) and `sim/native/tests/core_check.cpp`, so generated battles use them.
3. Run `python3 tools/gen_battles.py`. It uses only the model, so it's correct as soon as the model is.
4. Delete `sim/tests/golden/expected.json`.
5. `python3 tools/check_sim_native.py --fuzz 2000` must pass. It skips the goldens with a note, and checks the regenerated battles and the fuzz against the model.
6. Push. The tools and core jobs pass. The sim job records the goldens on its worker, uploads them as the `golden-hashes` artifact and fails on purpose (D-008).
7. Put the recorded file at `sim/tests/golden/expected.json`. Run `python3 -m pytest -q tools/tests`, where the model must reproduce the new goldens, and `python3 tools/check_sim_native.py`. Commit, and check CI is green.

## Adding a hand-written golden scenario

1. Write the spec in `sim/tests/golden/scenarios/` and add its path to `SCENARIOS` in `sim/tests/golden/golden_runner.gd`.
2. Delete `sim/tests/golden/expected.json` and push. A tool test requires the file to cover exactly the scenario files, so CI must record it again (D-008).
3. Put the recorded file in place. `python3 -m pytest -q tools/tests` checks the reference model reproduces every golden, the new one included. Commit, and check CI is green.

## Verifying locally

```sh
pip install -r tools/requirements.txt
python3 tools/config_tool.py validate
python3 tools/gen_vectors.py --check
python3 tools/gen_battles.py --check
python3 -m pytest -q tools/tests
python3 tools/check_sim_native.py          # the C++ core: three builds, vectors, goldens, generated battles
```

`check_sim_native.py --fuzz 2000 --fuzz-seed N` runs more battles. A failure prints the rerun command and saves a shrunk battle under `build/sim-native-check/fuzz-failures/`.

In this cloud workspace, clang++ can't link the sanitizers because its runtime isn't installed. Use g++ locally; CI runs both.

For the Godot tests:
1. Install Godot 4.7.2 with `tools/ci/install_godot.sh`. It works outside CI too and prints where it put `godot`; add that to `PATH`. Then run `tools/fetch_plugins.sh`.
2. Download the `sim-native-linux` artifact from the green CI run of the commit you're testing, and check its digest.
3. Unpack it into `sim/bin/`, then run `python3 tools/sync_sim.py`.
4. Import both projects (`godot --headless --path worker --import`, and the same for `client`).
5. Run `godot --headless --path worker --script res://cli/run_tests.gd` and `godot --headless --path client -- --run-tests-and-quit`. Each must print `RESULT: PASS` and exit with 0. The client's exit code also covers the Plugin Lab build.

Importing the client makes the Play Games addon rewrite `client/project.godot`'s autoload, so revert that file afterwards (D-025).
