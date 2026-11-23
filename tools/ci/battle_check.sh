#!/usr/bin/env bash
# Plays landfall_01 through the battle screen with the autoplay builder
# (client/scenes/battle.gd), replays its spec and command log on the headless
# worker, and fails unless both reach the same final hash (M1: the client's
# battle is the battle the server would verify). With --video, also records
# 40 seconds of the battle with Godot's Movie Maker to build/battle.mp4.
#
#   tools/ci/battle_check.sh [--video]
# Needs godot on PATH, the sim library synced into both projects, both
# projects imported, and xvfb-run for the desktop renderer.
set -euo pipefail

out="build/battle-check"
mkdir -p "$out"
root="$(pwd)"
tools/ci/run_godot.sh 300 xvfb-run -a godot --path client --rendering-driver opengl3 res://scenes/battle.tscn \
  -- --autoplay --fast --quit-at-end --replay-out "$root/$out/client.json"
python3 - "$out" <<'PY'
import json, sys
out = sys.argv[1]
doc = json.load(open(f"{out}/client.json"))
json.dump(doc["spec"], open(f"{out}/spec.json", "w"))
print(f"client: {doc['result']['outcome']} at tick {doc['result']['ticks']}, {len(doc['spec']['commands'])} commands, "
      f"hash {doc['result']['final_hash']}")
PY
tools/ci/run_godot.sh 120 godot --headless --path worker --script res://cli/replay.gd -- \
  --bundle "$root/client/data/config_bundle.json" --battle "$root/$out/spec.json" > "$out/worker.json"
python3 - "$out" <<'PY'
import json, sys
out = sys.argv[1]
client = json.load(open(f"{out}/client.json"))["result"]
text = open(f"{out}/worker.json").read()
worker = json.loads(text[text.index("{"):])
print(f"worker: {worker['outcome']} at tick {worker['ticks']}, hash {worker['final_hash']}")
if worker["final_hash"] != client["final_hash"]:
    sys.exit("error: the worker's replay doesn't match the battle the client played")
print("RESULT: PASS (the client's battle replays to the same hash)")
PY
if [ "${1:-}" = "--video" ]; then
  xvfb-run -a -s "-screen 0 1280x1600x24" godot --path client --rendering-driver opengl3 \
    --write-movie "$root/$out/battle.avi" --fixed-fps 30 --quit-after 1200 res://scenes/battle.tscn -- --autoplay
  ffmpeg -loglevel error -y -i "$out/battle.avi" -c:v libx264 -pix_fmt yuv420p -crf 26 -movflags +faststart "$out/battle.mp4"
  rm -f "$out/battle.avi"
  echo "video: $out/battle.mp4 ($(du -h "$out/battle.mp4" | cut -f1))"
fi
