"""tools/ci/apply_owner_config.py writes the owner's console settings into a copy of the client."""
import json
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ci"))
import apply_owner_config as aoc  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
PACKAGE = "com.alienempiretd.pluginlab"


@pytest.fixture
def client(tmp_path, monkeypatch):
    for name in ("project.godot", "export_presets.cfg"):
        shutil.copy(REPO / "client" / name, tmp_path / name)
    monkeypatch.setattr(aoc, "CLIENT", tmp_path)
    monkeypatch.setattr(aoc, "PROJECT", tmp_path / "project.godot")
    monkeypatch.setattr(aoc, "PRESETS", tmp_path / "export_presets.cfg")
    for name in ("PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER", "PLAY_GAMES_PROJECT_ID", "GOOGLE_SERVICES_JSON", "GITHUB_STEP_SUMMARY"):
        monkeypatch.delenv(name, raising=False)
    return tmp_path


def services(package: str = PACKAGE) -> str:
    return json.dumps({"project_info": {"project_number": "1"}, "client": [{"client_info": {"android_client_info": {"package_name": package}}}]})


def test_nothing_set_changes_nothing(client):
    before = {p.name: p.read_text() for p in client.iterdir()}
    assert aoc.main() == 0
    assert {p.name: p.read_text() for p in client.iterdir()} == before


def test_values_land_in_every_place(client, monkeypatch):
    monkeypatch.setenv("PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER", "123456789012")
    monkeypatch.setenv("PLAY_GAMES_PROJECT_ID", "987654321098")
    monkeypatch.setenv("GOOGLE_SERVICES_JSON", services())
    assert aoc.main() == 0
    project = (client / "project.godot").read_text()
    presets = (client / "export_presets.cfg").read_text()
    assert 'play_integrity/cloud_project_number="123456789012"' in project
    assert 'play_games/project_id="987654321098"' in project
    assert presets.count('godot_play_game_services/game_id="987654321098"') == 2
    assert "0000000000" not in presets
    assert json.loads((client / "google-services.json").read_text())["client"]


@pytest.mark.parametrize("value", ["12-34", "abc123456", "1234 5678"])
def test_ids_must_be_digits(client, monkeypatch, value):
    monkeypatch.setenv("PLAY_GAMES_PROJECT_ID", value)
    with pytest.raises(SystemExit, match="only digits"):
        aoc.main()


@pytest.mark.parametrize("value", ["123", "1" * 21])
def test_ids_must_have_a_plausible_length(client, monkeypatch, value):
    monkeypatch.setenv("PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER", value)
    with pytest.raises(SystemExit, match="6 to 20 digits"):
        aoc.main()


def test_google_services_must_match_the_package(client, monkeypatch):
    monkeypatch.setenv("GOOGLE_SERVICES_JSON", services("com.example.other"))
    with pytest.raises(SystemExit, match="no Android app for com.alienempiretd.pluginlab"):
        aoc.main()
    assert not (client / "google-services.json").exists()


def test_google_services_must_be_json(client, monkeypatch):
    monkeypatch.setenv("GOOGLE_SERVICES_JSON", "{not json")
    with pytest.raises(SystemExit, match="isn't valid JSON"):
        aoc.main()
