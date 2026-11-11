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

## The quality bar

Each system ships with all of these, or the reason one doesn't apply is written down.

| Layer | What it is | Where |
| --- | --- | --- |
| Unit tests | Each rule alone, including the refusals. A test file that doesn't compile fails the run. | `sim/tests/unit/`, `tools/tests/` |
| Reference model | The rule written a second, independent way in Python, in closed form where possible | `tools/reference/sim_model.py` (D-028) |
| Generated battles | Fresh battles each CI run, matched to the model, fresh and on a reused battle, plus battles built to break the core's limits | `tools/sim_cases.py`, `tools/check_sim_native.py` |
| Sanitizers and shipped builds | The C++ core under UBSan and ASan, and as plain -O2 and -O3 builds, all answering the same | `tools/check_sim_native.py` |
| Platforms | x86-64 and ARM, g++ and clang++, with identical answers | CI jobs `core` and `core-agree` |
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

When a change can alter a battle's result:

1. Change the core, raise `SIM_VERSION` in `fx.h`, and teach `tools/reference/sim_model.py` the new rule. Raise its `MODEL_SIM_VERSION` to match.
2. `python3 tools/check_sim_native.py --fuzz 2000` must pass: the core and the model agree on the new rule.
3. Run `python3 tools/gen_battles.py` to regenerate the generated battles.
4. Delete `sim/tests/golden/expected.json` and push. CI records the goldens on its worker and uploads them as the `golden-hashes` artifact (D-008).
5. Review those hashes, commit them, and check CI is green.
6. Extend the generator (`tools/sim_cases.py`) so new inputs, such as commands or towers, are generated too.

## Verifying locally

```sh
python3 tools/config_tool.py validate
python3 tools/gen_vectors.py --check
python3 tools/gen_battles.py --check
python3 -m pytest -q tools/tests
python3 tools/check_sim_native.py          # the C++ core: three builds, vectors, goldens, generated battles
```

`check_sim_native.py --fuzz 2000 --fuzz-seed N` runs more battles. A failure prints the rerun command and saves a shrunk battle under `build/sim-native-check/fuzz-failures/`.

In this cloud workspace, clang++ can't link the sanitizers because its runtime isn't installed. Use g++ locally; CI runs both.

For the Godot tests:
1. Download the `sim-native-linux` artifact from a green CI run and check its digest.
2. Unpack it into `sim/bin/`, then run `python3 tools/sync_sim.py`.
3. Run `godot --headless --path worker --script res://cli/run_tests.gd` and `godot --headless --path client -- --run-tests-and-quit`. Both must print `RESULT: PASS`.

The Play Games addon rewrites `client/project.godot`'s autoload when the editor imports, so revert that file afterwards (D-025).
