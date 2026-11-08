#!/usr/bin/env bash
# Fails unless every Android plugin the Plugin Lab tests is registered in the
# APK's manifest. Godot drops an enabled plugin it can't find, and the Firebase
# addon only warns about a missing library, so an export can succeed without
# them; this catches that before the APK reaches a phone.
#
#   tools/ci/check_apk_plugins.sh build/android/aetd-m0-debug.apk
#
# Needs aapt2 from the Android SDK build-tools (ANDROID_HOME).
set -euo pipefail

apk="${1:?usage: $0 path/to/app.apk}"
: "${ANDROID_HOME:?ANDROID_HOME must point at the Android SDK}"
aapt2="$(ls -d "$ANDROID_HOME"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"
[ -x "$aapt2" ] || { echo "error: no aapt2 under $ANDROID_HOME/build-tools" >&2; exit 1; }

manifest="$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk")"

# Godot v2 plugins register as org.godotengine.plugin.v2.<singleton name>.
expected=(
  org.godotengine.plugin.v2.GodotGooglePlayBilling
  org.godotengine.plugin.v2.PoingGodotAdMob
  org.godotengine.plugin.v2.PoingGodotAdMobRewardedAd
  org.godotengine.plugin.v2.GodotxFirebaseCore
  org.godotengine.plugin.v2.GodotxFirebaseMessaging
  org.godotengine.plugin.v2.GodotPlayGameServices
  org.godotengine.plugin.v2.PlayIntegrity
  com.google.android.gms.ads.APPLICATION_ID
  com.google.android.gms.games.APP_ID
)
missing=0
for name in "${expected[@]}"; do
  if grep -q "\"$name\"" <<< "$manifest"; then
    echo "ok       $name"
  else
    echo "missing  $name" >&2
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "error: $apk lacks plugins the Plugin Lab tests. Check the export log for skipped plugins." >&2
  exit 1
fi
