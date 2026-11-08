#!/usr/bin/env bash
# Prepares a CI runner to export the Android builds: signing, version numbers
# and Godot editor settings pointing at the Android SDK and JDK.
#
# Signing: if the repo has the owner's upload key as secrets
# (ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS), both
# the debug APK and the release AAB are signed with it, so every build has the
# same certificate. Otherwise a throwaway debug key is made and only the debug
# APK can be built. Setup: docs/PLUGINS.md.
#
# Needs ANDROID_HOME and JAVA_HOME (set by GitHub's runner and setup-java).
# VERSION_CODE sets the Android version code, which must rise with every upload
# to Play. In CI it's the run number times 100 plus the attempt, so a re-run
# ("Re-run all jobs") also gets a new, higher code.
set -euo pipefail

: "${ANDROID_HOME:?ANDROID_HOME must point at the Android SDK}"
: "${JAVA_HOME:?JAVA_HOME must point at JDK 17}"

repo="$(cd "$(dirname "$0")/../.." && pwd)"
temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
version_code="${VERSION_CODE:-$(( ${GITHUB_RUN_NUMBER:-0} * 100 + ${GITHUB_RUN_ATTEMPT:-1} ))}"

if [ -n "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  : "${ANDROID_KEYSTORE_PASSWORD:?the ANDROID_KEYSTORE_PASSWORD secret is missing}"
  : "${ANDROID_KEY_ALIAS:?the ANDROID_KEY_ALIAS secret is missing}"
  signing="upload-key"
  keystore="$temp/upload.keystore"
  key_user="$ANDROID_KEY_ALIAS"
  key_pass="$ANDROID_KEYSTORE_PASSWORD"
  if ! printf '%s' "$ANDROID_KEYSTORE_BASE64" | tr -d ' \r\n' | base64 -d > "$keystore" 2>/dev/null; then
    echo "error: the ANDROID_KEYSTORE_BASE64 secret isn't valid base64. Paste the whole of ANDROID_KEYSTORE_BASE64.txt." >&2
    exit 1
  fi
else
  signing="throwaway"
  keystore="$temp/debug.keystore"
  key_user="androiddebugkey"
  key_pass="android"
  if [ ! -f "$keystore" ]; then
    keytool -genkeypair -noprompt -keystore "$keystore" -storepass "$key_pass" \
      -alias "$key_user" -keypass "$key_pass" -keyalg RSA -keysize 2048 \
      -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
  fi
fi

if ! cert="$(keytool -list -v -keystore "$keystore" -storepass "$key_pass" -alias "$key_user" 2>&1)"; then
  echo "error: can't open the signing key. Check the ANDROID_KEYSTORE_BASE64 (the whole text), ANDROID_KEYSTORE_PASSWORD and ANDROID_KEY_ALIAS secrets." >&2
  printf '%s\n' "$cert" | grep -i "keytool error" >&2 || true
  exit 1
fi
sha1="$(printf '%s\n' "$cert" | sed -n 's/^[[:space:]]*SHA1: //p' | head -1)"
sha256="$(printf '%s\n' "$cert" | sed -n 's/^[[:space:]]*SHA256: //p' | head -1)"

# Godot reads these instead of the per-machine export credentials file.
exports=(
  "GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$keystore"
  "GODOT_ANDROID_KEYSTORE_DEBUG_USER=$key_user"
  "GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=$key_pass"
)
if [ "$signing" = "upload-key" ]; then
  exports+=(
    "GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$keystore"
    "GODOT_ANDROID_KEYSTORE_RELEASE_USER=$key_user"
    "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$key_pass"
  )
fi
if [ -n "${GITHUB_ENV:-}" ]; then
  printf '%s\n' "${exports[@]}" >> "$GITHUB_ENV"
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "signing=$signing" >> "$GITHUB_OUTPUT"
fi

# Every export preset gets this run's version code.
sed -i "s/^version\/code=.*/version\/code=$version_code/" "$repo/client/export_presets.cfg"

# The settings file name has changed across Godot 4 releases; write both forms.
config="$HOME/.config/godot"
mkdir -p "$config"
for name in editor_settings-4.tres editor_settings-4.7.tres; do
  cat > "$config/$name" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
EOF
done

summary="Android signing: **$signing** key, version code **$version_code**.

| Certificate | Fingerprint |
| --- | --- |
| SHA-1 | \`$sha1\` |
| SHA-256 | \`$sha256\` |
"
if [ "$signing" = "throwaway" ]; then
  summary+="
This key is new on every run, so this build can't update an earlier one, and Play Games sign-in can't be set up for it. Add the upload key secrets (docs/PLUGINS.md) for a stable key and a Play-ready AAB.
"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s' "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
printf '%s' "$summary"
