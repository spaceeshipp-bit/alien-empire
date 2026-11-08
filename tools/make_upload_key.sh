#!/usr/bin/env bash
# Makes the owner's Android upload key and prints what to paste into the
# repo's Actions secrets. Run it once, in a GitHub Codespace on this repo or on
# any computer with Java 17 or newer (it needs keytool). Walkthrough:
# docs/PLUGINS.md.
#
#   tools/make_upload_key.sh [output folder]   # default: ~/aetd-upload-key
#
# The key and its password are written outside the repo, never committed. Keep
# a copy of both somewhere safe: Play only accepts uploads signed with this key.
set -euo pipefail

out="${1:-$HOME/aetd-upload-key}"
keystore="$out/upload-key.jks"
alias_name="upload"

if ! command -v keytool >/dev/null 2>&1; then
  echo "error: keytool not found. Install a JDK (17 or newer) or use a GitHub Codespace." >&2
  exit 1
fi
if [ -e "$keystore" ]; then
  echo "error: $keystore already exists. Move it away first; this script never overwrites a key." >&2
  exit 1
fi
mkdir -p "$out"
chmod 700 "$out"

# 32 random letters and digits. Godot needs the key and store passwords to be
# the same, which is what a PKCS12 keystore does anyway.
password=""
while [ "${#password}" -lt 32 ]; do
  password+="$(head -c 64 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
done
password="${password:0:32}"

keytool -genkeypair -noprompt -storetype PKCS12 -keystore "$keystore" \
  -storepass "$password" -keypass "$password" -alias "$alias_name" \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Alien Empire TD upload key" >/dev/null 2>&1

base64 < "$keystore" | tr -d '\n' > "$out/ANDROID_KEYSTORE_BASE64.txt"
printf '%s' "$password" > "$out/ANDROID_KEYSTORE_PASSWORD.txt"
printf '%s' "$alias_name" > "$out/ANDROID_KEY_ALIAS.txt"
chmod 600 "$out"/*

sha1="$(keytool -list -v -keystore "$keystore" -storepass "$password" -alias "$alias_name" 2>/dev/null \
  | sed -n 's/^[[:space:]]*SHA1: //p' | head -1)"

cat <<EOF
Upload key made in $out

Add three repository secrets (GitHub: Settings > Secrets and variables >
Actions > New repository secret). Each value is in a file of the same name;
open it, copy everything, paste it as the secret's value:

  ANDROID_KEYSTORE_BASE64    $out/ANDROID_KEYSTORE_BASE64.txt
  ANDROID_KEYSTORE_PASSWORD  $out/ANDROID_KEYSTORE_PASSWORD.txt
  ANDROID_KEY_ALIAS          $out/ANDROID_KEY_ALIAS.txt   (it is "$alias_name")

Then keep a private copy of upload-key.jks and the password, for example in a
password manager, and delete this folder (and the codespace, if you used one).

The key's SHA-1, needed later for Play Games sign-in on sideloaded builds:
  $sha1
EOF
