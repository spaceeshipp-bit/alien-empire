#!/usr/bin/env python3
"""Write the owner's Google console settings into the client before an export.

The values live in the GitHub repo's Actions settings, so the owner never edits
code (walkthrough: docs/PLUGINS.md). Each is optional; a missing one leaves the
committed default, and the Plugin Lab says which setting a check is missing.

  PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER  variable: Google Cloud project number (digits)
  PLAY_GAMES_PROJECT_ID                variable: Play Games Services project ID (digits)
  GOOGLE_SERVICES_JSON                 secret: the Firebase google-services.json text

  python3 tools/ci/apply_owner_config.py
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CLIENT = REPO / "client"
PROJECT = CLIENT / "project.godot"
PRESETS = CLIENT / "export_presets.cfg"


def set_key(text: str, section: str, key: str, value: str) -> str:
    """Sets key=value inside [section] of a Godot config file; the key must exist."""
    pattern = re.compile(rf"(^\[{re.escape(section)}\]\n(?:(?!^\[).*\n)*?){re.escape(key)}=.*$", re.M)
    new, count = pattern.subn(lambda m: f"{m.group(1)}{key}={value}", text)
    if count != 1:
        raise SystemExit(f"error: {key} not found in [{section}]")
    return new


def digits(name: str) -> str | None:
    value = os.environ.get(name, "").strip()
    if not value:
        return None
    if not value.isdigit():
        raise SystemExit(f"error: {name} must be only digits, with no spaces or dashes. See docs/PLUGINS.md.")
    if not 6 <= len(value) <= 20:
        raise SystemExit(f"error: {name} must be 6 to 20 digits (got {len(value)}). Copy the whole number. See docs/PLUGINS.md.")
    return value


def package_name(presets: str) -> str:
    names = set(re.findall(r'^package/unique_name="([^"]+)"$', presets, re.M))
    if len(names) != 1:
        raise SystemExit(f"error: expected one package name in {PRESETS.name}, found {sorted(names)}")
    return names.pop()


def check_google_services(text: str, package: str) -> None:
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"error: GOOGLE_SERVICES_JSON isn't valid JSON ({exc.msg} at line {exc.lineno}). Paste the whole file.")
    packages = {
        client.get("client_info", {}).get("android_client_info", {}).get("package_name")
        for client in data.get("client", [])
    }
    if package not in packages:
        raise SystemExit(
            f"error: GOOGLE_SERVICES_JSON has no Android app for {package} (it has {sorted(p for p in packages if p)}). "
            "Add an Android app with that package name in Firebase and download the file again."
        )


def main() -> int:
    project = PROJECT.read_text(encoding="utf-8")
    presets = PRESETS.read_text(encoding="utf-8")
    rows = []

    number = digits("PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER")
    if number:
        project = set_key(project, "aetd", "play_integrity/cloud_project_number", f'"{number}"')
    rows.append(("PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER", "set" if number else "not set"))

    game_id = digits("PLAY_GAMES_PROJECT_ID")
    if game_id:
        project = set_key(project, "aetd", "play_games/project_id", f'"{game_id}"')
        for section in ("preset.0.options", "preset.1.options"):
            presets = set_key(presets, section, "godot_play_game_services/game_id", f'"{game_id}"')
    rows.append(("PLAY_GAMES_PROJECT_ID", "set" if game_id else "not set (placeholder ID)"))

    services = os.environ.get("GOOGLE_SERVICES_JSON", "").strip()
    if services:
        check_google_services(services, package_name(presets))
        (CLIENT / "google-services.json").write_text(services + "\n", encoding="utf-8")
    rows.append(("GOOGLE_SERVICES_JSON", "set" if services else "not set (Firebase unconfigured)"))

    PROJECT.write_text(project, encoding="utf-8")
    PRESETS.write_text(presets, encoding="utf-8")

    lines = ["", "| Owner setting | In this build |", "| --- | --- |"]
    lines += [f"| `{name}` | {state} |" for name, state in rows]
    report = "\n".join(lines) + "\n"
    print(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as out:
            out.write(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
