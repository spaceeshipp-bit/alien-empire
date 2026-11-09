#!/usr/bin/env python3
"""Copy sim/ into the Godot projects that run it: client/ and worker/.

The build prompt keeps one shared sim core and copies it into each project at
build time. The copies are git-ignored; run this after changing anything in
sim/ (or rebuilding sim/bin/ with tools/build_sim_native.sh) and before opening
either project in Godot.

  python3 tools/sync_sim.py          # update both copies
  python3 tools/sync_sim.py --check  # exit 1 if a copy is missing or stale
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "sim"
TARGETS = (REPO / "client" / "sim", REPO / "worker" / "sim")
# Files Godot writes next to scripts and assets; never part of the source.
GENERATED_SUFFIXES = (".uid", ".import")
SKIPPED_DIRS = {"__pycache__"}
# The C++ sources of the sim core stay in sim/native; the projects get only the
# libraries built from them (sim/bin/) and sim/aetd_sim.gdextension.
SKIPPED_TOP = {"native"}


def source_files() -> dict[Path, Path]:
    files = {}
    for path in sorted(SOURCE.rglob("*")):
        rel = path.relative_to(SOURCE)
        if (
            path.is_file()
            and rel.parts[0] not in SKIPPED_TOP
            and not SKIPPED_DIRS.intersection(rel.parts)
            and not path.name.endswith(GENERATED_SUFFIXES)
        ):
            files[rel] = path
    return files


def target_files(target: Path) -> set[Path]:
    if not target.exists():
        return set()
    return {
        p.relative_to(target)
        for p in target.rglob("*")
        if p.is_file() and not p.name.endswith(GENERATED_SUFFIXES)
    }


# Godot loads the extensions listed in <project>/.godot/extension_list.cfg at
# startup. Its first scan of a fresh project adds new ones and loads them mid-run,
# and Godot 4.7.2 then crashes on exit (seen in CI: a segfault in Godot's own
# shutdown). Listing the sim core before Godot first opens a project makes it
# load at startup, as it does on every later run.
EXTENSION = "res://sim/aetd_sim.gdextension"


def extension_list(target: Path) -> Path:
    return target.parent / ".godot" / "extension_list.cfg"


def extension_listed(target: Path) -> bool:
    config = extension_list(target)
    return config.exists() and EXTENSION in {line.strip() for line in config.read_text(encoding="utf-8").splitlines()}


def list_extension(target: Path) -> bool:
    if extension_listed(target):
        return False
    config = extension_list(target)
    lines = config.read_text(encoding="utf-8").splitlines() if config.exists() else []
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text("\n".join([*[line for line in lines if line.strip()], EXTENSION]) + "\n", encoding="utf-8")
    return True


def differences(target: Path) -> list[str]:
    wanted = source_files()
    present = target_files(target)
    problems = [f"missing {rel}" for rel in wanted if rel not in present]
    problems += [f"stale {rel}" for rel, src in wanted.items() if rel in present and (target / rel).read_bytes() != src.read_bytes()]
    problems += [f"extra {rel}" for rel in sorted(present - set(wanted))]
    if not extension_listed(target):
        problems.append(f"{EXTENSION} is not in {extension_list(target).relative_to(REPO)}")
    return problems


def sync(target: Path) -> int:
    wanted = source_files()
    changed = 0
    for rel, src in wanted.items():
        dst = target / rel
        if dst.exists() and dst.read_bytes() == src.read_bytes():
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        changed += 1
    for rel in sorted(target_files(target) - set(wanted)):
        (target / rel).unlink()
        changed += 1
    if list_extension(target):
        changed += 1
    return changed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="only report whether the copies are current")
    args = parser.parse_args(argv)
    failed = False
    for target in TARGETS:
        name = target.relative_to(REPO)
        if args.check:
            problems = differences(target)
            for problem in problems:
                print(f"{name}: {problem}", file=sys.stderr)
            failed = failed or bool(problems)
        else:
            print(f"{name}: {sync(target)} file(s) updated")
    if args.check and not failed:
        print("sim copies are current")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
