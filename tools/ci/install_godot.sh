#!/usr/bin/env bash
# Downloads the pinned Godot editor for Linux x86_64, checks it against the
# release's SHA512-SUMS.txt and puts `godot` on PATH (GITHUB_PATH in CI).
# With --templates it also installs the matching export templates.
#
#   GODOT_VERSION=4.7.2 tools/ci/install_godot.sh [--templates]
set -euo pipefail

version="${GODOT_VERSION:-4.7.2}"
tag="${version}-stable"
base="https://github.com/godotengine/godot/releases/download/${tag}"
work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/godot-${tag}"
mkdir -p "$work/bin"
cd "$work"

fetch() {
  local name="$1"
  if [ ! -f "$name" ]; then
    curl -fsSL --retry 3 -o "$name" "${base}/${name}"
  fi
  grep -E "^[0-9a-f]{128} [ *]${name}\$" SHA512-SUMS.txt | sha512sum -c -
}

curl -fsSL --retry 3 -o SHA512-SUMS.txt "${base}/SHA512-SUMS.txt"

editor="Godot_v${tag}_linux.x86_64"
fetch "${editor}.zip"
unzip -q -o "${editor}.zip"
ln -sf "$work/${editor}" "$work/bin/godot"

if [ "${1:-}" = "--templates" ]; then
  templates="Godot_v${tag}_export_templates.tpz"
  fetch "$templates"
  dest="$HOME/.local/share/godot/export_templates/${version}.stable"
  rm -rf "$dest" "$work/templates"
  unzip -q -o "$templates"
  mkdir -p "$(dirname "$dest")"
  mv "$work/templates" "$dest"
  echo "Export templates installed in $dest"
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$work/bin" >> "$GITHUB_PATH"
fi
"$work/bin/godot" --headless --version
echo "Godot ${tag} is at $work/bin/godot"
