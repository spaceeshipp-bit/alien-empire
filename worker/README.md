# Sim worker

Headless Godot project that runs the shared sim core with no rendering. Run `python3 tools/sync_sim.py` first so `worker/sim/` exists.

```sh
# unit tests and golden battles; exit code 0 only if all pass
godot --headless --path worker --script res://cli/run_tests.gd

# record golden hashes (absolute path)
godot --headless --path worker --script res://cli/run_tests.gd -- --record "$PWD/sim/tests/golden/expected.json"

# replay one battle and print its result as JSON (absolute or res:// paths)
godot --headless --path worker --script res://cli/replay.gd -- --bundle /abs/config_bundle.json --battle /abs/spec.json
```

From M4, Nakama hands battles to this worker and trusts its result.
