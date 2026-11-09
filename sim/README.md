# Sim core

The one battle simulation. The phone runs it to play battles, and the server's worker runs the same code to replay and verify them, so a given seed, config and command log give the same result everywhere. Never re-implement battle logic anywhere else.

The battle itself is C++ (`native/`), built into a GDExtension that the client and the worker both load (docs/DECISIONS.md D-026: on a raid benchmark GDScript missed the 100 ms replay budget by 2 to 25 times, and got under it only after a rebuild for speed, and only while no unit died). The GDScript in `core/` reads and checks configs and battle specs and wraps the C++ with the API the rest of the game uses.

## Rules

- A fixed 20 ticks per second.
- Integer math only: HP and damage ×100, distances in thousandths of a tile, percentages in basis points. No `float` or `double` in `native/src/core/`; a tool test checks it.
- Randomness only from the battle's own `SimRng`, seeded by the server.
- Entities update in ascending ID order, and ties break by ID.
- No engine physics, navigation, timers or random functions.
- The C++ core uses only the C++ standard library: no Godot types, so it can be tested on its own under sanitizers. Godot types appear only in `native/src/godot/`.
- C++ is built with `-fwrapv` and must not rely on unspecified order (sort only on unique keys, never iterate hashed containers).
- GDScript loads sim scripts with `preload("res://sim/...")`; no `class_name`. The native classes (`SimNative`, `SimNativeBattle` and so on) are used only from `core/`.
- Any change that could alter a battle's result raises `SIM_VERSION` in `native/src/core/fx.h`, and the golden hashes are then re-recorded.

## Files

| File | Role |
| --- | --- |
| `native/src/core/battle.*` | One battle: spawns, movement, leaks, checkpoints, state hash |
| `native/src/core/lane_path.*` | Lane geometry with integer segment lengths |
| `native/src/core/sim_rng.*` | xoshiro128** generator |
| `native/src/core/state_hasher.h`, `sha256.*` | SHA-256 over integers and strings |
| `native/src/core/fx.h` | `SIM_VERSION`, tick rate, integer square root |
| `native/src/godot/` | The Godot classes over the core (godot-cpp) |
| `native/tests/core_check.cpp` | Drives the core without Godot for `tools/check_sim_native.py` |
| `aetd_sim.gdextension`, `bin/` | How Godot loads the core, and the built libraries (`bin/` is git-ignored) |
| `core/battle.gd` | Checks a config and spec fit, hands them to the core, exposes results |
| `core/battle_spec.gd`, `core/sim_config.gd` | Read and check a battle spec and a config bundle |
| `core/lane_path.gd`, `core/sim_rng.gd`, `core/state_hasher.gd`, `core/fx.gd`, `core/sim_version.gd` | Thin wrappers over the core |
| `core/data_reader.gd`, `core/json_file.gd` | Safe JSON reading |
| `tests/` | Unit tests, reference vectors and golden battles |

## Build

```sh
pip install -r tools/requirements-build.txt
tools/build_sim_native.sh linux          # desktop editor, worker, CI
tools/build_sim_native.sh android        # phone (needs the Android NDK)
python3 tools/sync_sim.py                # copies sim/ (with bin/) into client/ and worker/
```

The first build fetches godot-cpp 10.0.0-stable, pinned by commit, into `build/godot-cpp`. CI builds both platforms on every push.

## Tests

- **Core check** (`tools/check_sim_native.py`): compiles the C++ core with UndefinedBehaviorSanitizer and AddressSanitizer and checks it against every reference vector and golden battle, without Godot.
- **Unit tests** (`tests/unit/`) check each piece through the GDScript API, including integer division and the generator against vectors from `tools/gen_vectors.py`.
- **Golden battles** (`tests/golden/`) replay fixed scenarios on a frozen config and compare final hashes with `expected.json`. A mismatch reports the first checkpoint that differs.

The unit tests and goldens run through `worker/cli/run_tests.gd` (headless), the client's `--run-tests-and-quit` (desktop) and the client's Sim tests screen (phone), so the same C++ is checked on x86-64 and on the phone's ARM.
