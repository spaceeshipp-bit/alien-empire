# Client (Godot 4.7.2)

The phone app. In M0 it's a test build with two screens: **Sim tests** (unit tests and golden battles on the device) and **Plugin Lab** (one check per Android plugin).

## Open it

1. From the repo root, run `python3 tools/sync_sim.py`. It copies `sim/` to `client/sim/`; the copy is git-ignored.
2. Open `client/project.godot` in Godot 4.7.2.
3. Press Play. On desktop the Plugin Lab checks report that they need Android.

## Export the Android test build

Needs JDK 17, the Android SDK, the Godot 4.7.2 export templates and network access for Gradle.

1. `tools/build_android_plugins.sh` builds the Play Integrity plugin.
2. In Godot, Project > Install Android Build Template.
3. Project > Export > Android > Export Project (debug). The APK goes to `build/android/`.

Third-party plugins and the console setup are in `docs/PLUGINS.md`.

## Layout

- `scenes/` boot screen, sim tests, Plugin Lab
- `ui/` placeholder theme from the concept-board palette, and the shared test report
- `plugin_lab/` one check per plugin
- `addons/PlayIntegrity/` export plugin for our Play Integrity AAR
- `android_plugins/` Java source for our own Android plugins (Godot skips this folder)
