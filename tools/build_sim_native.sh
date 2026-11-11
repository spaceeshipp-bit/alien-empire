#!/usr/bin/env bash
# Builds the sim core GDExtension (sim/native) into sim/bin/, for the platforms
# given. Fetches the pinned godot-cpp into build/godot-cpp the first time.
#
#   tools/build_sim_native.sh linux                 # desktop, worker and CI (debug + release)
#   tools/build_sim_native.sh android               # phone (debug + release, arm64)
#   tools/build_sim_native.sh linux android
#
# tools/check_sim_native.py checks the same core without Godot, under sanitizers.
#
# Needs SCons (tools/requirements-build.txt), a C++17 compiler, and for Android the NDK
# below under $ANDROID_HOME/ndk/. Then run tools/sync_sim.py to copy sim/ (with
# sim/bin/) into the Godot projects.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
# godot-cpp 10.0.0-stable, which targets Godot 4.7 with api_version=4.7.
GODOT_CPP_TAG="10.0.0-stable"
GODOT_CPP_COMMIT="507ed9d840c01a3c5b2a39af8bb4000bfac30bf5"
godot_cpp="${GODOT_CPP_DIR:-$repo/build/godot-cpp}"
# The NDK Godot 4.7.2 builds its Android libraries with (platform/android/detect.py).
# The sim library shares Godot's C++ runtime (libc++_shared.so) in the APK, and the
# NDK docs advise building with the same NDK as the libraries you share a runtime
# with. godot-cpp would otherwise use 28.1.13356709. CI installs this version too.
GODOT_NDK_VERSION="29.0.14206865"
jobs="$(nproc 2>/dev/null || echo 4)"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 linux|android [...]" >&2
  exit 2
fi

if [ ! -d "$godot_cpp/.git" ]; then
  mkdir -p "$(dirname "$godot_cpp")"
  git clone --quiet --depth 1 --branch "$GODOT_CPP_TAG" https://github.com/godotengine/godot-cpp "$godot_cpp"
fi
actual="$(git -C "$godot_cpp" rev-parse HEAD)"
if [ "$actual" != "$GODOT_CPP_COMMIT" ]; then
  echo "error: $godot_cpp is at $actual, expected godot-cpp $GODOT_CPP_TAG ($GODOT_CPP_COMMIT)." >&2
  echo "Delete it and run this script again." >&2
  exit 1
fi

build() {
  GODOT_CPP_DIR="$godot_cpp" scons -C "$repo/sim/native" -j"$jobs" \
    build_profile="$repo/sim/native/build_profile.json" "$@"
}

for platform in "$@"; do
  case "$platform" in
    linux)
      # Symbols only in the debug build, which never ships, for readable crash backtraces.
      build platform=linux arch=x86_64 target=template_debug debug_symbols=yes
      build platform=linux arch=x86_64 target=template_release
      ;;
    android)
      : "${ANDROID_HOME:?ANDROID_HOME must point at the Android SDK}"
      build platform=android arch=arm64 target=template_debug ndk_version="$GODOT_NDK_VERSION"
      build platform=android arch=arm64 target=template_release ndk_version="$GODOT_NDK_VERSION"
      ;;
    *)
      echo "error: unknown platform $platform (linux or android)" >&2
      exit 2
      ;;
  esac
done
ls -l "$repo/sim/bin"
