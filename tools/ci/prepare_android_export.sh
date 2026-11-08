#!/usr/bin/env bash
# Prepares a CI runner to export the Android debug APK: a throwaway debug
# keystore and Godot editor settings pointing at the Android SDK and JDK.
# Needs ANDROID_HOME and JAVA_HOME (set by GitHub's runner and setup-java).
set -euo pipefail

: "${ANDROID_HOME:?ANDROID_HOME must point at the Android SDK}"
: "${JAVA_HOME:?JAVA_HOME must point at JDK 17}"

keystore="${RUNNER_TEMP:-/tmp}/debug.keystore"
if [ ! -f "$keystore" ]; then
  keytool -genkeypair -noprompt -keystore "$keystore" -storepass android \
    -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
    -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi

# Godot reads these instead of the per-machine export credentials file.
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$keystore"
    echo "GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey"
    echo "GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android"
  } >> "$GITHUB_ENV"
fi

# The settings file name has changed across Godot 4 releases; write both forms.
config="$HOME/.config/godot"
mkdir -p "$config"
for name in editor_settings-4.tres editor_settings-4.7.tres; do
  cat > "$config/$name" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
export/android/debug_keystore = "$keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF
done
echo "Android export prepared (keystore $keystore)"
