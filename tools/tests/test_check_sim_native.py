"""tools/check_sim_native.py: how it plans the golden battles."""
import shutil

import check_sim_native


def test_goldens_skip_while_being_re_recorded(tmp_path, monkeypatch):
    golden = tmp_path / "golden"
    shutil.copytree(check_sim_native.GOLDEN, golden)
    (golden / "expected.json").unlink()
    monkeypatch.setattr(check_sim_native, "GOLDEN", golden)
    monkeypatch.setattr(check_sim_native, "REPO", tmp_path)
    plan = check_sim_native.Plan()
    assert check_sim_native.add_goldens(plan) == 0
    assert plan.lines == [] and plan.expect == []


def test_every_golden_also_runs_on_a_reused_battle():
    plan = check_sim_native.Plan()
    count = check_sim_native.add_goldens(plan)
    assert count == 4
    assert plan.lines.count("battle_run") == count
    assert plan.lines.count("battle_reuse") == count
    # battle_run answers once; battle_reuse answers twice (the refused setup, then the rerun).
    assert len(plan.expect) == 3 * count
