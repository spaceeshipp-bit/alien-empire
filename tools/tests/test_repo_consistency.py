"""Cross-checks between files that must agree: golden scenarios and the frozen
bundle, the GDScript file lists and the files on disk, the sim copies."""
import re
from pathlib import Path

import config_tool as ct
import sync_sim

REPO = Path(__file__).resolve().parents[2]
GOLDEN = REPO / "sim" / "tests" / "golden"


def res_paths(gd_file: Path) -> set[str]:
    return set(re.findall(r'"(res://[^"]+\.(?:gd|json))"', gd_file.read_text(encoding="utf-8")))


def test_golden_scenarios_fit_the_frozen_bundle():
    registry = ct.schema_registry()
    bundle = ct.load_json(GOLDEN / "config_bundle.json")
    assert ct.check_bundle(bundle, registry) == []
    specs = sorted((GOLDEN / "scenarios").glob("*.json"))
    assert specs
    for spec in specs:
        assert ct.validate_battle_file(spec, bundle, registry) == [], spec.name


def test_golden_runner_lists_every_scenario():
    listed = {p for p in res_paths(GOLDEN / "golden_runner.gd") if "/scenarios/" in p}
    on_disk = {f"res://sim/tests/golden/scenarios/{p.name}" for p in (GOLDEN / "scenarios").glob("*.json")}
    assert listed == on_disk


def test_test_runner_lists_every_unit_test():
    listed = {p for p in res_paths(REPO / "sim" / "tests" / "test_runner.gd") if "/unit/" in p}
    on_disk = {f"res://sim/tests/unit/{p.name}" for p in (REPO / "sim" / "tests" / "unit").glob("test_*.gd")}
    assert listed == on_disk


def test_every_res_path_in_sim_exists():
    # expected.json appears once the goldens are first recorded with Godot.
    optional = {"res://sim/tests/golden/expected.json"}
    for gd in (REPO / "sim").rglob("*.gd"):
        for res in res_paths(gd) - optional:
            assert (REPO / res.removeprefix("res://")).exists(), f"{gd.relative_to(REPO)} refers to missing {res}"


def test_sync_then_check():
    assert sync_sim.main([]) == 0
    assert sync_sim.main(["--check"]) == 0


def test_ci_scripts_exist_and_are_executable():
    import os

    import yaml

    workflow = yaml.safe_load((REPO / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8"))
    scripts = set()
    for job in workflow["jobs"].values():
        for step in job["steps"]:
            scripts.update(re.findall(r"(tools/[\w/]+\.(?:sh|py))", step.get("run", "")))
    assert scripts, "the workflow runs repo scripts"
    for script in scripts:
        path = REPO / script
        assert path.exists(), script
        if script.endswith(".sh"):
            assert os.access(path, os.X_OK), f"{script} is not executable"
