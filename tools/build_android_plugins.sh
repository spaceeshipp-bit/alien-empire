#!/usr/bin/env bash
# Builds this project's own Android plugins and copies the AARs where the
# client's export plugins expect them. Needs JDK 17, the Android SDK
# (ANDROID_HOME) and Gradle 8.9 or newer on PATH, plus network access for
# Gradle's first dependency download.
#
#   tools/build_android_plugins.sh
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
src="$repo/client/android_plugins/play_integrity"
out="$repo/client/addons/PlayIntegrity/bin"

gradle --no-daemon -p "$src" :plugin:assembleDebug :plugin:assembleRelease
mkdir -p "$out"
cp "$src/plugin/build/outputs/aar/plugin-debug.aar" "$out/PlayIntegrity-debug.aar"
cp "$src/plugin/build/outputs/aar/plugin-release.aar" "$out/PlayIntegrity-release.aar"
echo "PlayIntegrity AARs copied to ${out#"$repo"/}"
