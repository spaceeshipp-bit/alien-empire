"""tools/check_sim_native.py: how it plans the checks. The checks themselves run in
CI's core job, which compiles the C++."""
import re
import shutil

import pytest

import check_sim_native as csn
import sim_cases
from reference import sim_model


def test_goldens_skip_while_being_re_recorded(tmp_path, monkeypatch):
    golden = tmp_path / "golden"
    shutil.copytree(csn.GOLDEN, golden)
    # D-008 deletes expected.json to re-record, so this must hold with or without it.
    (golden / "expected.json").unlink(missing_ok=True)
    monkeypatch.setattr(csn, "GOLDEN", golden)
    monkeypatch.setattr(csn, "REPO", tmp_path)
    plan = csn.Plan()
    assert csn.add_goldens(plan) == 0
    assert plan.lines == [] and plan.expect == []


def test_every_golden_also_runs_on_a_reused_battle():
    if not (csn.GOLDEN / "expected.json").exists():
        pytest.skip("expected.json is being re-recorded (D-008)")
    plan = csn.Plan()
    count = csn.add_goldens(plan)
    assert count == len(list((csn.GOLDEN / "scenarios").glob("*.json")))
    assert plan.lines.count("battle_run") == count
    assert plan.lines.count("battle_reuse") == count
    # battle_run answers once; battle_reuse answers twice (the refused setup, then the rerun).
    assert len(plan.expect) == 3 * count


def test_generated_battles_are_checked_against_the_model():
    plan = csn.Plan()
    cases = csn.add_fuzz(plan, seed=3, count=30, only_case=None)
    assert len(cases) == 30
    runs = [(what, want) for what, want, case in plan.expect if what.endswith("matches the reference model")]
    refusals = [(what, want) for what, want, case in plan.expect if "refuses" in what]
    assert len(runs) == sum(c.valid for c in cases)
    assert len(refusals) == sum(not c.valid for c in cases) > 0
    for case in cases:
        if case.valid:
            line = sim_model.run(case).line()
            assert sum(1 for _, want, c in plan.expect if c is case and want == line) == 2  # fresh and reused
    assert all(want == csn.Prefix("error") for _, want in refusals)


def test_one_case_can_be_run_alone():
    plan = csn.Plan()
    (case,) = csn.add_fuzz(plan, seed=3, count=0, only_case=7)
    assert case == sim_cases.random_case(3, 7, csn.load(csn.GOLDEN / "config_bundle.json"))


def test_a_named_compiler_must_exist(monkeypatch):
    monkeypatch.setenv("CXX", "no-such-compiler-c++")
    with pytest.raises(SystemExit, match="isn't installed"):
        csn.compiler()


def test_the_model_knows_the_core_version():
    """A SIM_VERSION bump changes the rules, so it must teach the model the new rules too (D-028)."""
    fx = (csn.CORE / "fx.h").read_text(encoding="utf-8")
    core_version = int(re.search(r"SIM_VERSION\s*=\s*(\d+)", fx).group(1))
    assert sim_model.MODEL_SIM_VERSION == core_version


def test_builds_cover_the_shipped_optimization_levels():
    flags = {name: set(f) for name, f in csn.BUILDS.items()}
    assert any("-fsanitize=undefined,address" in f for f in flags.values())
    assert any("-O2" in f for f in flags.values())  # godot-cpp template_debug
    assert any("-O3" in f for f in flags.values())  # godot-cpp template_release
    assert {"-std=c++17", "-fno-exceptions", "-fwrapv"} <= set(csn.COMMON)
