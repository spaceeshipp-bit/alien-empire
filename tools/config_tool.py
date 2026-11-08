#!/usr/bin/env python3
"""Validate and bundle the balance config, and validate battle specs.

Usage (from the repo root):
  python3 tools/config_tool.py validate
  python3 tools/config_tool.py bundle --out build/config_bundle.json
  python3 tools/config_tool.py validate-battle --bundle B.json SPEC.json [SPEC.json ...]

Every config number must be an integer in the unit its field name says
(see config/README.md). Files with decimal numbers are rejected outright.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

REPO = Path(__file__).resolve().parent.parent
SCHEMA_DIR = REPO / "config" / "schema"
BALANCE_DIR = REPO / "config" / "balance"
SCHEMA_BASE = "https://schemas.alien-empire-td.invalid/"
PARTS = ("manifest", "towers", "enemies", "counters", "damage", "status_effects")
CLASSES = ("swarm", "armored", "shielded", "air", "cloaked", "titan")
BUNDLE_FORMAT = 1
# Command types the sim accepts. M0 defines none; M1 adds field towers.
KNOWN_COMMANDS: frozenset[str] = frozenset()


class ConfigError(Exception):
    """A file couldn't be read or parsed."""


def _reject_float(text: str) -> Any:
    raise ValueError(f"decimal number {text} found; config uses integer units only")


def load_json(path: Path) -> Any:
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f, parse_float=_reject_float)
    except (OSError, ValueError) as exc:
        raise ConfigError(f"{path}: {exc}") from exc


def canonical_json(value: Any) -> bytes:
    """Serialization used for config_hash: sorted keys, no spaces, UTF-8."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def schema_registry(schema_dir: Path = SCHEMA_DIR) -> Registry:
    resources = []
    for path in sorted(schema_dir.glob("*.schema.json")):
        doc = load_json(path)
        resources.append((doc["$id"], Resource.from_contents(doc)))
    return Registry().with_resources(resources)


def validator(name: str, registry: Registry) -> Draft202012Validator:
    schema = registry[SCHEMA_BASE + f"{name}.schema.json"].contents
    return Draft202012Validator(schema, registry=registry)


def schema_errors(name: str, instance: Any, registry: Registry, label: str) -> list[str]:
    errors = []
    for err in sorted(validator(name, registry).iter_errors(instance), key=lambda e: list(e.absolute_path)):
        where = "/".join(str(p) for p in err.absolute_path) or "(root)"
        errors.append(f"{label}: {where}: {err.message}")
    return errors


def load_balance(balance_dir: Path = BALANCE_DIR) -> dict[str, Any]:
    return {part: load_json(balance_dir / f"{part}.json") for part in PARTS}


def check_references(data: dict[str, Any]) -> list[str]:
    """Rules a JSON Schema can't express: ids, cross-file links, consistency."""
    errors: list[str] = []
    towers = data["towers"]["towers"]
    enemies = data["enemies"]["enemies"]
    counters = data["counters"]["counters"]

    def unique(items: list[dict], label: str) -> dict[str, dict]:
        seen: dict[str, dict] = {}
        for item in items:
            if item["id"] in seen:
                errors.append(f"{label}: duplicate id {item['id']}")
            seen[item["id"]] = item
        return seen

    tower_by_id = unique(towers, "towers")
    enemy_by_id = unique(enemies, "enemies")

    for tower in towers:
        tid = tower["id"]
        attacks = tower["damage_x100"] > 0
        if attacks:
            if tower["shots_per_s_x100"] == 0:
                errors.append(f"towers: {tid} deals damage but has shots_per_s_x100 0")
            if tower["damage_type"] == "none":
                errors.append(f"towers: {tid} deals damage but has damage_type none")
            if tid not in counters:
                errors.append(f"counters: no row for attacking tower {tid}")
        else:
            if tower["shots_per_s_x100"] != 0 or tower["damage_type"] != "none":
                errors.append(f"towers: support tower {tid} needs shots_per_s_x100 0 and damage_type none")
            if tower["armor_pierce_bp"] != 0 or tower["splash_mt"] != 0:
                errors.append(f"towers: support tower {tid} can't have armor pierce or splash")
            if tid in counters:
                errors.append(f"counters: support tower {tid} must not have a row")
        types = [a["type"] for a in tower["abilities"]]
        if len(types) != len(set(types)):
            errors.append(f"towers: {tid} lists an ability twice")

    for tid, row in counters.items():
        if tid not in tower_by_id:
            errors.append(f"counters: row for unknown tower {tid}")
        cloaked = row["cloaked"]
        if cloaked["rating"] == "cant_hit" and cloaked["unrevealed_damage_bp"] != 0:
            errors.append(f"counters: {tid} can't hit cloaked, so unrevealed_damage_bp must be 0")

    for enemy in enemies:
        eid = enemy["id"]
        if (enemy["class"] == "air") != (enemy["movement"] == "air"):
            errors.append(f"enemies: {eid} must use air movement if and only if its class is air")
        for ability in enemy["abilities"]:
            if ability["type"] == "spawn_on_death" and ability["enemy"] not in enemy_by_id:
                errors.append(f"enemies: {eid} spawns unknown enemy {ability['enemy']}")

    # spawn_on_death chains must end, or one death could spawn forever
    def spawns(eid: str) -> list[str]:
        return [a["enemy"] for a in enemy_by_id[eid]["abilities"] if a["type"] == "spawn_on_death"]

    for start in enemy_by_id:
        stack, seen = [start], set()
        while stack:
            current = stack.pop()
            for child in spawns(current):
                if child == start:
                    errors.append(f"enemies: {start} spawns itself through spawn_on_death")
                    stack = []
                    break
                if child in enemy_by_id and child not in seen:
                    seen.add(child)
                    stack.append(child)

    pool = data["damage"]["bonus_pool"]
    if pool["full_value_until_bp"] > pool["partial_value_until_bp"]:
        errors.append("damage: bonus_pool.full_value_until_bp must not exceed partial_value_until_bp")

    ratings = data["damage"]["counter_ratings_bp"]
    if not ratings["strong"] >= ratings["neutral"] >= ratings["weak"] >= ratings["cant_hit"] == 0:
        errors.append("damage: counter ratings must run strong >= neutral >= weak >= cant_hit, with cant_hit 0")

    return errors


def validate_balance(data: dict[str, Any], registry: Registry | None = None) -> list[str]:
    registry = registry or schema_registry()
    errors: list[str] = []
    for part in PARTS:
        errors += schema_errors(part, data[part], registry, part)
    if errors:
        return errors  # reference checks assume the shapes are right
    return check_references(data)


def make_bundle(data: dict[str, Any]) -> dict[str, Any]:
    payload = copy.deepcopy(data)
    return {
        "format": BUNDLE_FORMAT,
        "config_hash": hashlib.sha256(canonical_json(payload)).hexdigest(),
        "data": payload,
    }


def check_bundle(bundle: dict[str, Any], registry: Registry | None = None) -> list[str]:
    registry = registry or schema_registry()
    errors = schema_errors("bundle", bundle, registry, "bundle")
    if errors:
        return errors
    errors = check_references(bundle["data"])
    expected = hashlib.sha256(canonical_json(bundle["data"])).hexdigest()
    if bundle["config_hash"] != expected:
        errors.append(f"bundle: config_hash is {bundle['config_hash']} but data hashes to {expected}")
    return errors


def check_battle(spec: dict[str, Any], data: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    bid = spec["battle_id"]
    enemy_by_id = {e["id"]: e for e in data["enemies"]["enemies"]}
    lanes: dict[str, dict] = {}
    for lane in spec["map"]["lanes"]:
        if lane["id"] in lanes:
            errors.append(f"{bid}: duplicate lane id {lane['id']}")
        lanes[lane["id"]] = lane
        for kind in ("ground", "air"):
            points = lane.get(kind, [])
            for a, b in zip(points, points[1:]):
                if a == b:
                    errors.append(f"{bid}: lane {lane['id']} {kind} path repeats point {a}")
    for wi, wave in enumerate(spec["waves"]):
        for gi, group in enumerate(wave["groups"]):
            where = f"{bid}: wave {wi} group {gi}"
            enemy = enemy_by_id.get(group["enemy"])
            lane = lanes.get(group["lane"])
            if enemy is None:
                errors.append(f"{where}: unknown enemy {group['enemy']}")
            if lane is None:
                errors.append(f"{where}: unknown lane {group['lane']}")
            if enemy and lane and enemy["movement"] == "air" and "air" not in lane:
                errors.append(f"{where}: air enemy {enemy['id']} needs an air path on lane {lane['id']}")
    ticks = [c["tick"] for c in spec["commands"]]
    if ticks != sorted(ticks):
        errors.append(f"{bid}: commands must be in tick order")
    for command in spec["commands"]:
        if command["type"] not in KNOWN_COMMANDS:
            errors.append(f"{bid}: unknown command type {command['type']}")
    return errors


def validate_battle_file(path: Path, bundle: dict[str, Any], registry: Registry) -> list[str]:
    spec = load_json(path)
    errors = schema_errors("battle", spec, registry, path.name)
    if errors:
        return errors
    return check_battle(spec, bundle["data"])


def _report(errors: list[str], ok_message: str) -> int:
    for line in errors:
        print(f"ERROR {line}", file=sys.stderr)
    if errors:
        print(f"{len(errors)} error(s)", file=sys.stderr)
        return 1
    print(ok_message)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p_val = sub.add_parser("validate", help="check config/balance against the schema and cross-file rules")
    p_val.add_argument("--balance-dir", type=Path, default=BALANCE_DIR)
    p_bun = sub.add_parser("bundle", help="validate, then write the merged bundle with its config_hash")
    p_bun.add_argument("--balance-dir", type=Path, default=BALANCE_DIR)
    p_bun.add_argument("--out", type=Path, required=True)
    p_bat = sub.add_parser("validate-battle", help="check battle spec files against a config bundle")
    p_bat.add_argument("--bundle", type=Path, required=True)
    p_bat.add_argument("specs", type=Path, nargs="+")
    args = parser.parse_args(argv)

    try:
        registry = schema_registry()
        if args.command == "validate":
            data = load_balance(args.balance_dir)
            return _report(validate_balance(data, registry), f"config OK (version {data['manifest']['config_version']})")
        if args.command == "bundle":
            data = load_balance(args.balance_dir)
            errors = validate_balance(data, registry)
            if errors:
                return _report(errors, "")
            bundle = make_bundle(data)
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(json.dumps(bundle, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
            print(f"wrote {args.out} (config_hash {bundle['config_hash']})")
            return 0
        bundle = load_json(args.bundle)
        errors = check_bundle(bundle, registry)
        for spec_path in args.specs:
            errors += validate_battle_file(spec_path, bundle, registry)
        return _report(errors, f"{len(args.specs)} battle spec(s) OK")
    except ConfigError as exc:
        return _report([str(exc)], "")


if __name__ == "__main__":
    sys.exit(main())
