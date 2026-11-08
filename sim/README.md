# Sim core

The one battle simulation. The phone runs it to play battles, and the server's worker runs the same files to replay and verify them, so a given seed, config and command log give the same result everywhere. Never re-implement battle logic anywhere else.

## Rules

- A fixed 20 ticks per second.
- Integer math only: HP and damage ×100, distances in thousandths of a tile, percentages in basis points. No floats.
- Randomness only from the battle's own `SimRng`, seeded by the server.
- Entities update in ascending ID order, and ties break by ID.
- No engine physics, navigation, timers or random functions.
- Scripts load each other with `preload("res://sim/...")`; no `class_name`.
- Any change that could alter a battle's result raises `SIM_VERSION` in `core/sim_version.gd`, and the golden hashes are then re-recorded.

## Files

| File | Role |
| --- | --- |
| `core/battle.gd` | One battle: spawns, movement, leaks, checkpoints, result and state hash |
| `core/battle_spec.gd` | Reads a battle spec (seed, lanes, waves, commands) |
| `core/sim_config.gd` | Reads the values the sim uses from a config bundle |
| `core/lane_path.gd` | Lane geometry with integer segment lengths |
| `core/sim_rng.gd` | xoshiro128** generator |
| `core/state_hasher.gd` | SHA-256 over integers and strings |
| `core/fx.gd` | Integer helpers: ticks, integer square root |
| `core/data_reader.gd`, `core/json_file.gd` | Safe JSON reading |
| `tests/` | Unit tests, reference vectors and golden battles |

## Tests

- **Unit tests** (`tests/unit/`) check each piece, including integer division and the generator against vectors from `tools/gen_vectors.py`.
- **Golden battles** (`tests/golden/`) replay fixed scenarios on a frozen config and compare final hashes with `expected.json`. A mismatch reports the first checkpoint that differs.

Both run through `worker/cli/run_tests.gd` (headless), the client's `--run-tests-and-quit` (desktop) and the client's Sim tests screen (phone).
