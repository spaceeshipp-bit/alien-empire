#!/usr/bin/env python3
"""Check the C++ sim core without Godot, under sanitizers.

Compiles sim/native/src/core with sim/native/tests/core_check.cpp, using
UndefinedBehaviorSanitizer and AddressSanitizer, then feeds it the reference
vectors (RNG, mul32, isqrt, state hashes) and the golden battles, and compares
every answer with sim/tests/vectors/*.json and sim/tests/golden/expected.json.
The golden battles are converted the way sim/core/sim_config.gd and
battle_spec.gd read them.

The same core then runs inside Godot through the GDExtension, where the
GDScript tests check it again on the desktop, the worker and the phone.

  python3 tools/check_sim_native.py          # needs g++ or clang++ with C++20
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CORE = REPO / "sim" / "native" / "src" / "core"
DRIVER = REPO / "sim" / "native" / "tests" / "core_check.cpp"
VECTORS = REPO / "sim" / "tests" / "vectors"
GOLDEN = REPO / "sim" / "tests" / "golden"
OUT = REPO / "build" / "sim-native-check"
FLAGS = [
    "-std=c++20", "-O1", "-g", "-fwrapv", "-Wall", "-Wextra", "-Werror",
    "-fsanitize=undefined,address", "-fno-sanitize-recover=all",
]


def compiler() -> str:
    for name in (os.environ.get("CXX", ""), "g++", "clang++"):
        if name and shutil.which(name):
            return name
    raise SystemExit("error: no C++ compiler found (set CXX)")


def build() -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    binary = OUT / "core_check"
    sources = sorted(str(p) for p in CORE.glob("*.cpp")) + [str(DRIVER)]
    cmd = [compiler(), *FLAGS, f"-I{REPO / 'sim' / 'native' / 'src'}", *sources, "-o", str(binary)]
    subprocess.run(cmd, check=True)
    return binary


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


class Plan:
    """Commands for the driver, with the answer expected for each output line."""

    def __init__(self) -> None:
        self.lines: list[str] = []
        self.expect: list[tuple[str, str]] = []  # (what, expected output line)

    def send(self, line: str) -> None:
        self.lines.append(line)

    def ask(self, line: str, what: str, expected: str) -> None:
        self.lines.append(line)
        self.expect.append((what, expected))


def add_vectors(plan: Plan) -> None:
    rng = load(VECTORS / "rng_vectors.json")
    for case in rng["rng"]:
        seed = case["seed"]
        plan.send(f"rng {seed}")
        for i, call in enumerate(case["calls"]):
            what = f"rng seed {seed} call {i}"
            if call[0] == "u32":
                plan.ask("u32", what, str(call[1]))
            elif call[0] == "range":
                plan.ask(f"range {call[1]} {call[2]}", what, str(call[3]))
            elif call[0] == "chance":
                plan.ask(f"chance {call[1]}", what, "true" if call[2] else "false")
            else:
                raise SystemExit(f"error: unknown rng call {call[0]}")
        plan.ask("state", f"rng seed {seed} final state", " ".join(str(w) for w in case["state_after"]))
    for a, b, product in rng["mul32"]:
        plan.ask(f"mul32 {a} {b}", f"mul32({a}, {b})", str(product))
    for n, root in load(VECTORS / "isqrt_vectors.json")["isqrt"]:
        plan.ask(f"isqrt {n}", f"isqrt({n})", str(root))
    for case in load(VECTORS / "hash_vectors.json")["cases"]:
        plan.send("hash_begin")
        for kind, value in case["ops"]:
            if kind == "int":
                plan.send(f"int {value}")
            else:
                plan.send(f"str {value.encode('utf-8').hex()}")
        plan.ask("hash_end", f"hash {case['name']}", case["sha256"])


def ticks(ms: int) -> int:
    return ms // 50


def add_goldens(plan: Plan) -> int:
    bundle = load(GOLDEN / "config_bundle.json")
    expected = load(GOLDEN / "expected.json")["scenarios"]
    enemies = sorted(bundle["data"]["enemies"]["enemies"], key=lambda e: e["id"])
    index = {e["id"]: i for i, e in enumerate(enemies)}
    count = 0
    for path in sorted((GOLDEN / "scenarios").glob("*.json")):
        name = path.stem
        if name not in expected:
            continue
        spec = load(path)
        plan.send("battle_begin")
        plan.send(f"config {bundle['config_hash']} {bundle['data']['manifest']['config_version']}")
        for e in enemies:
            air = 1 if e["movement"] == "air" else 0
            plan.send(f"enemy {e['hp_x100']} {e['armor']} {e['shield_x100']} {e['speed_mtps']} {air} {e['leak_lives']}")
        plan.send(f"spec {spec['battle_id']} {spec['seed']} {ticks(spec['max_ms'])}")
        lane_ids = [lane["id"] for lane in spec["map"]["lanes"]]
        for lane in spec["map"]["lanes"]:
            parts = ["lane", str(len(lane["ground"]))]
            parts += [str(p[0]) for p in lane["ground"]] + [str(p[1]) for p in lane["ground"]]
            air = lane.get("air", [])
            parts.append(str(len(air)))
            parts += [str(p[0]) for p in air] + [str(p[1]) for p in air]
            plan.send(" ".join(parts))
        for wave in spec["waves"]:
            start = ticks(wave["start_ms"])
            for g in wave["groups"]:
                plan.send(" ".join(str(v) for v in (
                    "group", index[g["enemy"]], lane_ids.index(g["lane"]), g["count"],
                    start + ticks(g["offset_ms"]), ticks(g["interval_ms"]), ticks(g["jitter_ms"]),
                )))
        want = expected[name]
        line = " ".join(["result", want["outcome"], str(want["ticks"]), want["final_hash"], *want["checkpoints"]])
        plan.ask("battle_run", f"golden {name}", line)
        count += 1
    return count


def main() -> int:
    for source in CORE.glob("*"):
        if re.search(r"\b(float|double)\b", source.read_text(encoding="utf-8")):
            print(f"error: {source.relative_to(REPO)} mentions float or double; the sim is integer only")
            return 1
    binary = build()
    plan = Plan()
    add_vectors(plan)
    goldens = add_goldens(plan)
    run = subprocess.run([str(binary)], input="\n".join(plan.lines) + "\n", capture_output=True, text=True)
    if run.returncode != 0:
        print(run.stdout[-2000:])
        print(run.stderr[-4000:])
        print(f"error: the core check exited with {run.returncode}")
        return 1
    got = run.stdout.splitlines()
    failures = 0
    if len(got) != len(plan.expect):
        print(f"error: expected {len(plan.expect)} answers, got {len(got)}")
        failures += 1
    for (what, want), have in zip(plan.expect, got):
        if have != want:
            failures += 1
            if failures <= 20:
                print(f"FAIL {what}\n  expected {want}\n  got      {have}")
    print(f"{len(plan.expect) - failures} of {len(plan.expect)} checks pass, including {goldens} golden battles")
    print("RESULT: " + ("PASS" if failures == 0 else "FAIL"))
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
