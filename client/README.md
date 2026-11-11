# Client (Godot 4.7.2)

The phone app. In M0 it's a test build with two screens: **Sim tests** (unit tests, golden battles and generated battles on the device) and **Plugin Lab** (one check per Android plugin).

## Open it

1. From the repo root, build the sim core for your desktop (`tools/build_sim_native.sh linux`; see `sim/README.md`), then run `python3 tools/sync_sim.py`. It copies `sim/` with the built library to `client/sim/`; the copy is git-ignored. CI builds the core for Linux and Android only, so opening the project on Windows or macOS needs `tools/build_sim_native.sh` and `sim/aetd_sim.gdextension` extended to that platform first.
2. Run `tools/fetch_plugins.sh`. It downloads the pinned third-party Android plugins into `client/addons/` and checks their hashes. Run it before opening the editor: otherwise Godot drops the missing plugins from `project.godot`, and the AdMob addon downloads its binaries itself without a hash check.
3. Open `client/project.godot` in Godot 4.7.2.
4. Press Play. On desktop the Plugin Lab checks report that they need Android.

## Export the Android test build

CI builds it on every push (the `aetd-m0-debug.apk` artifact, plus `aetd-m0-release.aab` once the upload key is set up). CI also writes `client/build_info.json` (git-ignored) before export, so the app names its build and commit on the home screen and the Sim tests report; a build from the editor says "local build". To build it yourself you need JDK 17, Gradle 8.9 or newer on PATH (CI uses 8.14.3), the Android SDK, the Godot 4.7.2 export templates and network access for Gradle.

1. `tools/build_android_plugins.sh` builds the Play Integrity plugin, and `tools/build_sim_native.sh android` the sim core for the phone (run `tools/sync_sim.py` after).
2. In Godot, Project > Install Android Build Template.
3. Project > Export > Android > Export Project (debug). The APK goes to `build/android/`. The "Android AAB" preset makes the release bundle for Play.

The plugins, the owner's setup and the phone walkthrough are in `docs/PLUGINS.md`.

## Layout

- `scenes/` boot screen, sim tests, Plugin Lab
- `ui/` placeholder theme from the concept-board palette, and the shared test report
- `plugin_lab/` one check per plugin
- `addons/PlayIntegrity/` export plugin for our Play Integrity AAR
- `android_plugins/` Java source for our own Android plugins (Godot skips this folder)
