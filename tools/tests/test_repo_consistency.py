"""Cross-checks between files that must agree: golden scenarios and the frozen
bundle, the GDScript file lists and the files on disk, the sim copies."""
import json
import re
from pathlib import Path

import pytest

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
    # expected.json is deleted on purpose to re-record after a SIM_VERSION bump;
    # the sim job then records fresh hashes and fails (docs/DECISIONS.md D-008).
    optional = {"res://sim/tests/golden/expected.json"}
    for gd in (REPO / "sim").rglob("*.gd"):
        for res in res_paths(gd) - optional:
            assert (REPO / res.removeprefix("res://")).exists(), f"{gd.relative_to(REPO)} refers to missing {res}"


def native_sim_version() -> int:
    match = re.search(r"constexpr int64_t SIM_VERSION = (\d+);", (REPO / "sim" / "native" / "src" / "core" / "fx.h").read_text(encoding="utf-8"))
    assert match, "SIM_VERSION not found in sim/native/src/core/fx.h"
    return int(match.group(1))


def gd_int_constant(gd_file: Path, name: str) -> int:
    match = re.search(rf"const {name}\s*(?::\s*int)?\s*:?=\s*(\d+)", gd_file.read_text(encoding="utf-8"))
    assert match, f"{name} not found in {gd_file.name}"
    return int(match.group(1))


def test_golden_hashes_match_the_scenarios_bundle_and_sim_version():
    if not (GOLDEN / "expected.json").exists():
        pytest.skip("expected.json is being re-recorded; the sim job records it and fails")
    expected = ct.load_json(GOLDEN / "expected.json")
    bundle = ct.load_json(GOLDEN / "config_bundle.json")
    assert expected["sim_version"] == native_sim_version()
    assert expected["config_hash"] == bundle["config_hash"]
    names = {p.stem for p in (GOLDEN / "scenarios").glob("*.json")}
    assert set(expected["scenarios"]) == names
    every = gd_int_constant(REPO / "sim" / "core" / "battle.gd", "CHECKPOINT_TICKS")
    for name, golden in expected["scenarios"].items():
        assert re.fullmatch(r"[0-9a-f]{64}", golden["final_hash"]), name
        assert len(golden["checkpoints"]) == golden["ticks"] // every, name
        assert all(re.fullmatch(r"[0-9a-f]{16}", c) for c in golden["checkpoints"]), name


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


def plugin_pins() -> list[dict[str, str]]:
    text = (REPO / "tools" / "fetch_plugins.sh").read_text(encoding="utf-8")
    block = re.search(r'^PINS="\n(.*?)^"$', text, re.S | re.M)
    assert block, "PINS table not found in tools/fetch_plugins.sh"
    pins = []
    for line in block.group(1).splitlines():
        dest, inner, sha, url = line.split("|")
        pins.append({"dest": dest, "inner": inner, "sha": sha, "url": url})
    return pins


def test_plugin_pins_are_exact_releases_with_hashes():
    pins = plugin_pins()
    assert pins
    for pin in pins:
        assert re.fullmatch(r"[0-9a-f]{64}", pin["sha"]), pin["dest"]
        assert re.fullmatch(r"https://github\.com/[\w.-]+/[\w.-]+/releases/download/[\w.-]+/[\w.-]+\.zip", pin["url"]), pin["url"]
        assert "latest" not in pin["url"], pin["url"]
    dests = [pin["dest"] for pin in pins]
    assert len(dests) == len(set(dests))
    for i, dest in enumerate(dests):
        # A destination inside another one must be installed after it.
        for outer in dests[i + 1:]:
            assert not dest.startswith(outer + "/"), f"{dest} is listed before {outer}"


def test_fetched_plugins_are_ignored_and_enabled():
    ignored = (REPO / ".gitignore").read_text(encoding="utf-8").splitlines()
    project = (REPO / "client" / "project.godot").read_text(encoding="utf-8")
    enabled = set(re.findall(r'"(res://addons/[^"]+/plugin\.cfg)"', re.search(r"^enabled=.*$", project, re.M).group(0)))
    for pin in plugin_pins():
        dest = pin["dest"]
        assert any(f"/client/{dest}/".startswith(line) for line in ignored if line.startswith("/client/") and line.endswith("/")), (
            f"{dest} is fetched, so .gitignore must cover /client/{dest}/"
        )
        if re.fullmatch(r"addons/[^/]+", dest):
            assert f"res://{dest}/plugin.cfg" in enabled, f"enable res://{dest}/plugin.cfg in client/project.godot"


def export_presets() -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current = None
    for line in (REPO / "client" / "export_presets.cfg").read_text(encoding="utf-8").splitlines():
        if line.startswith("["):
            current = sections.setdefault(line.strip("[]"), {})
        elif "=" in line and current is not None:
            key, value = line.split("=", 1)
            current[key] = value
    return sections


def test_aab_preset_matches_the_apk_preset():
    presets = export_presets()
    apk, aab = presets["preset.0"], presets["preset.1"]
    assert apk["name"] == '"Android"' and aab["name"] == '"Android AAB"'
    differ = {"name", "export_path"}
    assert {k: v for k, v in apk.items() if k not in differ} == {k: v for k, v in aab.items() if k not in differ}
    apk_opts, aab_opts = presets["preset.0.options"], presets["preset.1.options"]
    assert apk_opts["gradle_build/export_format"] == "0" and aab_opts["gradle_build/export_format"] == "1"
    assert {k: v for k, v in apk_opts.items() if k != "gradle_build/export_format"} == {
        k: v for k, v in aab_opts.items() if k != "gradle_build/export_format"
    }


def test_autoloads_use_res_paths():
    # Fetched addons ship no .uid files, so each machine makes its own uids. The
    # Play Games addon rewrites its autoload to uid:// on every editor start;
    # committing that would break the autoload everywhere else.
    project = (REPO / "client" / "project.godot").read_text(encoding="utf-8")
    section = re.search(r"^\[autoload\]\n(.*?)(?=^\[|\Z)", project, re.S | re.M)
    assert section, "client/project.godot has no [autoload] section"
    entries = re.findall(r'^(\w+)="([^"]*)"$', section.group(1), re.M)
    assert entries
    for name, path in entries:
        assert path.lstrip("*").startswith("res://"), f"autoload {name} must use a res:// path, not {path}"


def test_sync_copies_no_native_sources():
    assert sync_sim.main([]) == 0
    for target in sync_sim.TARGETS:
        assert not (target / "native").exists(), f"{target} has a copy of sim/native"
        assert (target / "aetd_sim.gdextension").exists()
        listed = (target.parent / ".godot" / "extension_list.cfg").read_text(encoding="utf-8").split()
        assert "res://sim/aetd_sim.gdextension" in listed


def _fake_sim(tmp_path, monkeypatch, with_library: bool):
    """A small sim/ and two projects in tmp_path, with sync_sim pointed at them."""
    source = tmp_path / "sim"
    (source / "core").mkdir(parents=True, exist_ok=True)
    (source / "core" / "battle.gd").write_text("extends RefCounted\n")
    (source / "native" / "src").mkdir(parents=True, exist_ok=True)
    (source / "native" / "src" / "battle.cpp").write_text("// not copied\n")
    (source / "aetd_sim.gdextension").write_text("[configuration]\n")
    if with_library:
        (source / "bin").mkdir(exist_ok=True)
        (source / "bin" / "libaetd_sim.linux.template_debug.x86_64.so").write_bytes(b"new library")
    targets = (tmp_path / "client" / "sim", tmp_path / "worker" / "sim")
    monkeypatch.setattr(sync_sim, "REPO", tmp_path)
    monkeypatch.setattr(sync_sim, "SOURCE", source)
    monkeypatch.setattr(sync_sim, "TARGETS", targets)
    return source, targets


def test_sync_replaces_a_loaded_library_without_touching_it(tmp_path, monkeypatch):
    source, targets = _fake_sim(tmp_path, monkeypatch, with_library=True)
    lib = "bin/libaetd_sim.linux.template_debug.x86_64.so"
    for target in targets:
        (target / "bin").mkdir(parents=True)
        (target / lib).write_bytes(b"old library")
    with (targets[0] / lib).open("rb") as loaded:  # stands in for Godot's mapping of the library
        assert sync_sim.main([]) == 0
        assert loaded.read() == b"old library"
    for target in targets:
        assert (target / lib).read_bytes() == b"new library"
        assert sorted(p.name for p in (target / "bin").iterdir()) == [Path(lib).name]  # no temp file left
        assert not (target / "native").exists()
    assert sync_sim.main(["--check"]) == 0


def test_sync_notes_a_missing_library(tmp_path, monkeypatch, capsys):
    _fake_sim(tmp_path, monkeypatch, with_library=False)
    assert sync_sim.main([]) == 0
    assert sync_sim.main(["--check"]) == 0  # not an error: CI checks the copies before building
    assert "no built sim library" in capsys.readouterr().out
    _fake_sim(tmp_path, monkeypatch, with_library=True)
    sync_sim.main([])
    assert "no built sim library" not in capsys.readouterr().out


def test_sim_json_has_no_decimal_numbers():
    """sim/core/json_file.gd refuses decimal notation (Godot rounds it before it can
    be checked), so no JSON the sim reads may use it. Python's parser calls
    parse_float for exactly the tokens with a fraction or an exponent."""
    def refuse(token: str):
        raise ValueError(f"decimal number {token}")
    for path in sorted((REPO / "sim").rglob("*.json")):
        json.loads(path.read_text(encoding="utf-8"), parse_float=refuse)


def test_ci_installs_the_ndk_the_build_uses():
    """The sim library is built with Godot's NDK (tools/build_sim_native.sh), and CI must
    install that same version for the build and for the symbol check."""
    script = (REPO / "tools" / "build_sim_native.sh").read_text(encoding="utf-8")
    version = re.search(r'^GODOT_NDK_VERSION="([0-9.]+)"', script, re.M).group(1)
    workflow = (REPO / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    assert re.findall(r"ndk[;/]([0-9]+\.[0-9]+\.[0-9]+)", workflow) == [version, version]


def test_symbol_check_reads_readelf_rows():
    import sys
    sys.path.insert(0, str(REPO / "tools" / "ci"))
    import check_apk_sim_symbols as c
    rows = [
        "    12: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND memcpy@LIBC (2)",
        "    13: 0000000000000000     0 FUNC    WEAK   DEFAULT  UND __cxa_finalize@LIBC (2)",
        "    14: 0000000000012340    64 FUNC    GLOBAL DEFAULT   12 aetd_sim_library_init",
        "     2: 0000000000000000     0 SECTION LOCAL  DEFAULT    9 .text",
    ]
    parsed = [c.ROW.match(r).groups() for r in rows]
    assert parsed[0] == ("FUNC", "GLOBAL", "UND", "memcpy@LIBC")
    assert parsed[1][1] == "WEAK" and parsed[2][2] == "12" and parsed[3][0] == "SECTION"


def test_native_core_is_integer_only():
    for source in (REPO / "sim" / "native" / "src" / "core").glob("*"):
        text = source.read_text(encoding="utf-8")
        assert not re.search(r"\b(float|double)\b", text), f"{source.name} mentions float or double"


def test_gdextension_lists_every_built_library():
    text = (REPO / "sim" / "aetd_sim.gdextension").read_text(encoding="utf-8")
    for key, platform, target, arch in [
        ("linux.debug.x86_64", "linux", "template_debug", "x86_64"),
        ("linux.release.x86_64", "linux", "template_release", "x86_64"),
        ("android.debug.arm64", "android", "template_debug", "arm64"),
        ("android.release.arm64", "android", "template_release", "arm64"),
    ]:
        assert f'{key} = "res://sim/bin/libaetd_sim.{platform}.{target}.{arch}.so"' in text, key

