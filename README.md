# Alien Empire TD (working title)

A fair-to-play alien tower defense game for Android: PvE tower defense, async PvP raids, a shared sector map and clans. Built milestone by milestone from [`docs/BUILD_PROMPT.md`](docs/BUILD_PROMPT.md); every decision is logged in [`docs/DECISIONS.md`](docs/DECISIONS.md).

**Current milestone:** M0 Foundations, on branch `m0-foundations`. Status and next steps: [`docs/milestones/M0.md`](docs/milestones/M0.md).

## Layout

| Folder | What's in it |
| --- | --- |
| `client/` | Godot 4.7.2 phone app. In M0, a test build: on-device sim tests and the Plugin Lab |
| `sim/` | The shared, deterministic battle sim (pure GDScript, integer math) and its tests. Copied into `client/` and `worker/` by `tools/sync_sim.py` |
| `worker/` | Headless Godot project that runs the sim: tests now, server-side battle replays from M4 |
| `server/` | Nakama backend modules (M4) |
| `config/` | Every balance number, as JSON checked against a schema |
| `tools/` | Config validator, reference test vectors, sync and build scripts, CI helpers |
| `docs/` | Build prompt, decisions, plugin setup, milestone reports |

## Quick checks (Python 3.11+)

```sh
pip install -r tools/requirements.txt
python3 tools/config_tool.py validate     # config against the schema and cross-file rules
python3 -m pytest -q tools/tests          # tool tests, reference vectors, repo consistency
```

## Sim tests (Godot 4.7.2)

```sh
python3 tools/sync_sim.py
tools/fetch_plugins.sh                     # pinned Android plugins for the client
godot --headless --path worker --script res://cli/run_tests.gd
godot --headless --path client -- --run-tests-and-quit
```

CI (`.github/workflows/ci.yml`) runs these on every push and builds the Android test APK, `aetd-m0-debug.apk`, with every plugin in it. Installing it on a phone and the one-time console setup: [`docs/PLUGINS.md`](docs/PLUGINS.md).
