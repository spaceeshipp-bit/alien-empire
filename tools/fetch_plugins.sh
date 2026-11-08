#!/usr/bin/env bash
# Downloads the third-party Godot Android plugins the client uses, checks each
# download against its pinned SHA-256 and unpacks it into client/. Run it before
# opening or exporting the client, like tools/sync_sim.py.
#
#   tools/fetch_plugins.sh          # install any plugin that is missing or out of date
#   tools/fetch_plugins.sh --check  # exit 1 unless every pinned plugin is installed
#
# Downloads are cached in $PLUGIN_CACHE (default build/plugin-cache, git-ignored).
# Versions, sources and licenses: docs/PLUGINS.md. To update a plugin, change its
# line below, run this script and commit the new hash only after it passes.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
client="$repo/client"
cache="${PLUGIN_CACHE:-$repo/build/plugin-cache}"

# One line per release asset, in install order:
#   destination in client/ | folder inside the zip ("." for all of it) | SHA-256 | URL
# The destination is replaced by that folder of the zip. A destination inside
# an earlier one (AdMob's binaries) must come after it.
PINS="
addons/GodotGooglePlayBilling|GodotGooglePlayBilling|20d75623d6f337f08d8283c83098b73678d5f575e39247af5a8eb80588b18568|https://github.com/godot-sdk-integrations/godot-google-play-billing/releases/download/3.3.0/godot-google-play-billing.zip
addons/admob|poing-godot-admob/addons/admob|8c53ff52719edf6a81cc7d32a9cdaad2d9e11693c85faca25008a1c19355726f|https://github.com/poingstudios/godot-admob-plugin/releases/download/v5.1.0/poing-godot-admob-v5.1.0.zip
addons/admob/android/bin|.|f7fdf644d50c0e231d8f02ae044057e489d0bcafcf50e908a4858477e7ee05ee|https://github.com/poingstudios/godot-admob-plugin/releases/download/v5.1.0/android-template-v4.7.2.zip
addons/admob/ios/bin|.|6e7f1c807761f9c0ad45d335ac4c74acd4bba7a31f9e1c7cd16a5220010cce71|https://github.com/poingstudios/godot-admob-plugin/releases/download/v5.1.0/ios-template-v4.7.2.zip
"

check_only=false
case "${1:-}" in
  "") ;;
  --check) check_only=true ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

# The stamp in each destination records the hash it was unpacked from.
stamp_name=".fetched-sha256"

installed() {
  local dest="$1" sha="$2"
  [ -f "$client/$dest/$stamp_name" ] && [ "$(cat "$client/$dest/$stamp_name")" = "$sha" ]
}

download() {
  local url="$1" sha="$2" file="$cache/$2.zip"
  if [ ! -f "$file" ] || ! echo "$sha  $file" | sha256sum -c --status -; then
    mkdir -p "$cache"
    curl -fsSL --retry 3 -o "$file.part" "$url"
    if ! echo "$sha  $file.part" | sha256sum -c --status -; then
      echo "error: $url does not match its pinned SHA-256" >&2
      echo "  expected $sha" >&2
      echo "  got      $(sha256sum "$file.part" | cut -d' ' -f1)" >&2
      rm -f "$file.part"
      return 1
    fi
    mv "$file.part" "$file"
  fi
  echo "$file"
}

unpack() {
  local file="$1" inner="$2" dest="$3" sha="$4"
  local work
  work="$(mktemp -d)"
  unzip -q "$file" -d "$work"
  if [ ! -d "$work/$inner" ]; then
    echo "error: $(basename "$file") has no folder $inner" >&2
    rm -rf "$work"
    return 1
  fi
  rm -rf "${client:?}/$dest"
  mkdir -p "$(dirname "$client/$dest")"
  if [ "$inner" = "." ]; then
    mv "$work" "$client/$dest"
    chmod 755 "$client/$dest"
  else
    mv "$work/$inner" "$client/$dest"
    rm -rf "$work"
  fi
  echo "$sha" > "$client/$dest/$stamp_name"
}

# Plugin-specific touches after unpacking.
tidy() {
  case "$1" in
    addons/admob)
      # Keeps Godot from scanning the addon's C# samples in a non-.NET editor
      # (the addon writes this file itself, but only after its first start).
      : > "$client/addons/admob/csharp/.gdignore"
      ;;
  esac
}

missing=0
while IFS='|' read -r dest inner sha url; do
  [ -n "$dest" ] || continue
  if installed "$dest" "$sha"; then
    echo "ok       client/$dest"
  elif $check_only; then
    echo "missing  client/$dest" >&2
    missing=1
  else
    file="$(download "$url" "$sha")"
    unpack "$file" "$inner" "$dest" "$sha"
    tidy "$dest"
    echo "fetched  client/$dest"
  fi
done <<< "$PINS"

if [ "$missing" -ne 0 ]; then
  echo "Run tools/fetch_plugins.sh to install the missing plugins." >&2
  exit 1
fi
