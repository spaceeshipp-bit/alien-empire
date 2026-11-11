#!/usr/bin/env python3
"""Check the C++ sim core without Godot: sanitizers, vectors, goldens and a fuzz.

Builds sim/native/src/core with the driver sim/native/tests/core_check.cpp three
ways: under UndefinedBehaviorSanitizer and AddressSanitizer at -O1, and plain at
-O2 and -O3, the levels godot-cpp builds the debug and release libraries at.
Every build gets the same plan, and must answer every line as expected:
- the reference vectors (RNG, mul32, isqrt, state hashes) in sim/tests/vectors;
- the golden battles in sim/tests/golden, each also rerun on a reused battle;
- generated battles (tools/sim_cases.py), each compared with the reference model
  (tools/reference/sim_model.py) on outcome, ticks, every checkpoint and the final
  hash, run twice and on a reused battle. Cases built to break one of the core's
  limits must be refused.
The builds must also answer identically to each other.

A generated battle that fails is shrunk to a smaller one that still fails, and
both are saved under build/sim-native-check/fuzz-failures/.

The same core then runs inside Godot through the GDExtension, where the GDScript
tests check it again on the desktop, the worker and the phone.

  python3 tools/check_sim_native.py                       # 200 generated battles, seed 1
  python3 tools/check_sim_native.py --fuzz 1000 --fuzz-seed 7
  python3 tools/check_sim_native.py --fuzz-seed 7 --fuzz-case 42   # one case again
  python3 tools/check_sim_native.py --digest out.txt      # digest of every answer

Needs g++ or clang++ with C++17 (set CXX to choose) and their sanitizer runtimes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

import sim_cases
from reference import sim_model

REPO = Path(__file__).resolve().parent.parent
CORE = REPO / "sim" / "native" / "src" / "core"
DRIVER = REPO / "sim" / "native" / "tests" / "core_check.cpp"
VECTORS = REPO / "sim" / "tests" / "vectors"
GOLDEN = REPO / "sim" / "tests" / "golden"
OUT = REPO / "build" / "sim-native-check"
# The language mode the library ships in: godot-cpp 10 compiles with -std=c++17
# and -fno-exceptions, and sim/native/SConstruct adds -fwrapv.
COMMON = ["-std=c++17", "-fno-exceptions", "-fwrapv", "-Wall", "-Wextra", "-Werror"]
BUILDS = {
    "sanitized -O1": ["-O1", "-g", "-fsanitize=undefined,address", "-fno-sanitize-recover=all"],
    "plain -O2": ["-O2"],  # godot-cpp's template_debug: the APK the owner installs
    "plain -O3": ["-O3"],  # godot-cpp's template_release: the Play build and the worker
}
DEFAULT_FUZZ = 200
MAX_SHRINKS = 3


def compiler() -> str:
    """CXX if set (and it must exist: CI names one per job), else g++, else clang++."""
    wanted = os.environ.get("CXX", "")
    if wanted:
        if shutil.which(wanted):
            return wanted
        raise SystemExit(f"error: CXX is {wanted}, which isn't installed")
    for name in ("g++", "clang++"):
        if shutil.which(name):
            return name
    raise SystemExit("error: no C++ compiler found (set CXX)")


def describe_compiler(cxx: str) -> str:
    """Which compiler and target this run uses, for the log: proof of what a CI job tested."""
    version = subprocess.run([cxx, "--version"], capture_output=True, text=True).stdout.splitlines()
    target = subprocess.run([cxx, "-dumpmachine"], capture_output=True, text=True).stdout.strip()
    return f"{shutil.which(cxx)}: {version[0] if version else '?'}, target {target or '?'}"


def build(name: str, flags: list[str]) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    binary = OUT / ("core_check_" + re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_"))
    sources = sorted(str(p) for p in CORE.glob("*.cpp")) + [str(DRIVER)]
    cmd = [compiler(), *COMMON, *flags, f"-I{REPO / 'sim' / 'native' / 'src'}", *sources, "-o", str(binary)]
    subprocess.run(cmd, check=True)
    return binary


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


@dataclass(frozen=True)
class Prefix:
    """An expected answer that only has to start with text (refusals list their reasons after it)."""
    text: str

    def __str__(self) -> str:
        return self.text + "..."


def matches(want, have: str) -> bool:
    return have.startswith(want.text) if isinstance(want, Prefix) else have == want


class Plan:
    """Commands for the driver, with the answer expected for each output line."""

    def __init__(self) -> None:
        self.lines: list[str] = []
        # (what, expected answer, the generated case it belongs to or None)
        self.expect: list[tuple[str, object, object]] = []

    def send(self, line: str) -> None:
        self.lines.append(line)

    def ask(self, line: str, what: str, expected, *more: tuple[str, object], case=None) -> None:
        """Sends line; expects one output line, plus one per (what, expected) in more."""
        self.lines.append(line)
        self.expect.append((what, expected, case))
        self.expect.extend((w, e, case) for w, e in more)


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
    return sim_cases.ticks(ms)


def reuse_answer(result: sim_model.Result) -> str:
    """What battle_reuse prints first: whether the rejected setup left the battle empty."""
    return ("" if result.reuse_had_aliens else "no aliens to test with ") + "rejected yes aliens 0 tick 0"


def add_goldens(plan: Plan) -> int:
    expected_path = GOLDEN / "expected.json"
    if not expected_path.exists():
        # Deleted on purpose to re-record after a SIM_VERSION bump (D-008): the
        # vectors still run here, and CI's sim job records the fresh hashes.
        print(f"note: {expected_path.relative_to(REPO)} is missing, so no golden battles run")
        return 0
    bundle = load(GOLDEN / "config_bundle.json")
    expected = load(expected_path)["scenarios"]
    count = 0
    for path in sorted((GOLDEN / "scenarios").glob("*.json")):
        name = path.stem
        if name not in expected:
            continue
        case = sim_cases.case_from_spec(bundle, load(path), name)
        for line in sim_cases.driver_lines(case):
            plan.send(line)
        want = expected[name]
        line = " ".join(["result", want["outcome"], str(want["ticks"]), want["final_hash"], *want["checkpoints"]])
        plan.ask("battle_run", f"golden {name}", line)
        plan.ask(
            "battle_reuse", f"golden {name}: a rejected setup leaves nothing behind", "rejected yes aliens 0 tick 0",
            (f"golden {name}: rerun on the same battle", line),
        )
        count += 1
    return count


def add_generated(plan: Plan) -> int:
    """The committed generated battles (tools/gen_battles.py), against the results
    stored with them, which the golden runner also checks inside Godot."""
    path = REPO / "sim" / "tests" / "generated" / "battles.json"
    if not path.exists():
        return 0
    doc = load(path)
    bundle = load(GOLDEN / "config_bundle.json")
    for battle in doc["battles"]:
        case = sim_cases.case_from_spec(bundle, battle["spec"], battle["name"])
        for line in sim_cases.driver_lines(case):
            plan.send(line)
        want = battle["expected"]
        line = " ".join(["result", want["outcome"], str(want["ticks"]), want["final_hash"], *want["checkpoints"]])
        plan.ask("battle_run", f"generated battle {battle['name']} (sim/tests/generated)", line)
    return len(doc["battles"])


def add_case(plan: Plan, case: sim_cases.Case, label: str) -> None:
    for line in sim_cases.driver_lines(case):
        plan.send(line)
    if not case.valid:
        plan.ask("battle_run", f"{label}: refuses {case.broken}", Prefix("error"), case=case)
        return
    want = sim_model.run(case)
    line = want.line()
    plan.ask("battle_run", f"{label}: matches the reference model", line, case=case)
    plan.ask(
        "battle_reuse", f"{label}: a rejected setup leaves nothing behind", reuse_answer(want),
        (f"{label}: rerun on the same battle", line), case=case,
    )


def add_fuzz(plan: Plan, seed: int, count: int, only_case: int | None) -> list[sim_cases.Case]:
    bundle = load(GOLDEN / "config_bundle.json")
    indices = [only_case] if only_case is not None else range(count)
    cases = []
    for i in indices:
        case = sim_cases.random_case(seed, i, bundle)
        add_case(plan, case, f"generated case {i} ({case.profile})")
        cases.append(case)
    return cases


def run_driver(binary: Path, lines: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([str(binary)], input="\n".join(lines) + "\n", capture_output=True, text=True)


def still_fails(binary: Path, case: sim_cases.Case) -> bool:
    """For shrinking: does this smaller case still show the core and the model disagreeing?"""
    try:
        plan = Plan()
        add_case(plan, case, "shrink")
    except (ValueError, IndexError):
        return False  # a candidate the core would refuse anyway: not a smaller version of this failure
    run = run_driver(binary, plan.lines)
    got = run.stdout.splitlines()
    if case.valid and got and got[0].startswith("error"):
        return False  # the core refuses this candidate: a different failure, not a smaller one
    return run.returncode != 0 or len(got) != len(plan.expect) or any(
        not matches(want, have) for (_, want, _), have in zip(plan.expect, got))


def save_failure(binary: Path, seed: int, case: sim_cases.Case) -> Path:
    smallest = shrink_case(binary, case) if case.valid else case
    folder = OUT / "fuzz-failures"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{case.name}.json"
    record = {"seed": seed, "case": case.to_json(), "smallest_failing": smallest.to_json()}
    if smallest.valid:
        plan = Plan()
        add_case(plan, smallest, "smallest")
        record["driver_input"] = plan.lines
        record["expected"] = [str(want) for _, want, _ in plan.expect]
        record["got"] = run_driver(binary, plan.lines).stdout.splitlines()
    path.write_text(json.dumps(record, indent=1) + "\n", encoding="utf-8")
    return path


def shrink_case(binary: Path, case: sim_cases.Case) -> sim_cases.Case:
    return sim_cases.shrink(case, lambda c: still_fails(binary, c))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fuzz", type=int, default=DEFAULT_FUZZ, help="generated battles to run (0: none)")
    parser.add_argument("--fuzz-seed", type=int, default=1, help="seed for the generated battles")
    parser.add_argument("--fuzz-case", type=int, help="run only this generated battle")
    parser.add_argument("--digest", type=Path, help="write a digest of every answer to this file")
    args = parser.parse_args(argv)

    for source in CORE.glob("*"):
        if re.search(r"\b(float|double)\b", source.read_text(encoding="utf-8")):
            print(f"error: {source.relative_to(REPO)} mentions float or double; the sim is integer only")
            return 1
    core_version = int(re.search(r"SIM_VERSION\s*=\s*(\d+)", (CORE / "fx.h").read_text(encoding="utf-8")).group(1))
    if core_version != sim_model.MODEL_SIM_VERSION and (args.fuzz > 0 or args.fuzz_case is not None):
        print(f"error: the core is sim version {core_version} but tools/reference/sim_model.py models version "
              f"{sim_model.MODEL_SIM_VERSION}. Teach the model the new rules (D-028).")
        return 1

    plan = Plan()
    add_vectors(plan)
    goldens = add_goldens(plan)
    generated = add_generated(plan)
    cases = add_fuzz(plan, args.fuzz_seed, args.fuzz, args.fuzz_case) if args.fuzz > 0 or args.fuzz_case is not None else []

    print("compiler " + describe_compiler(compiler()))
    with ThreadPoolExecutor() as pool:
        binaries = dict(zip(BUILDS, pool.map(lambda item: build(*item), BUILDS.items())))
        runs = dict(zip(binaries, pool.map(lambda b: run_driver(b, plan.lines), binaries.values())))

    failures = 0
    failed_cases: dict[str, sim_cases.Case] = {}
    for name, run in runs.items():
        if run.returncode != 0:
            print(run.stdout[-2000:])
            print(run.stderr[-4000:])
            print(f"error: the {name} core check exited with {run.returncode}")
            failures += 1
            continue
        got = run.stdout.splitlines()
        if len(got) != len(plan.expect):
            print(f"error: {name}: expected {len(plan.expect)} answers, got {len(got)}")
            failures += 1
        shown = 0
        for (what, want, case), have in zip(plan.expect, got):
            if not matches(want, have):
                failures += 1
                shown += 1
                if case is not None:
                    failed_cases[case.name] = case
                if shown <= 10:
                    print(f"FAIL {name}: {what}\n  expected {want}\n  got      {have}")
    outputs = {name: run.stdout for name, run in runs.items()}
    if len(set(outputs.values())) > 1:
        failures += 1
        print("error: the builds answered differently: " + ", ".join(
            f"{name} {hashlib.sha256(text.encode()).hexdigest()[:12]}" for name, text in outputs.items()))

    if failed_cases:
        sanitized = binaries["sanitized -O1"]
        for case in list(failed_cases.values())[:MAX_SHRINKS]:
            path = save_failure(sanitized, args.fuzz_seed, case)
            index = case.name.rsplit("-", 1)[-1]
            print(f"saved {path.relative_to(REPO)}; rerun with --fuzz-seed {args.fuzz_seed} --fuzz-case {index}")
        if len(failed_cases) > MAX_SHRINKS:
            print(f"({len(failed_cases) - MAX_SHRINKS} more failing generated battles not shrunk)")

    answers = outputs["sanitized -O1"]
    digest = hashlib.sha256(answers.encode("utf-8")).hexdigest()
    if args.digest:
        args.digest.write_text(
            f"fuzz seed {args.fuzz_seed}, {len(cases)} generated battles, {len(plan.expect)} answers, sha256 {digest}\n",
            encoding="utf-8")
    valid = sum(1 for c in cases if c.valid)
    print(f"{len(BUILDS)} builds: {', '.join(BUILDS)}")
    print(f"each answered {len(plan.expect)} checks: vectors, {goldens} golden battles, the {generated} committed "
          f"generated battles, {valid} fresh ones against the reference model and {len(cases) - valid} it must refuse "
          f"(fuzz seed {args.fuzz_seed})")
    print(f"answers sha256 {digest}")
    print("RESULT: " + ("PASS" if failures == 0 else f"FAIL ({failures} wrong answers)"))
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
