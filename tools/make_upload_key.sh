#!/usr/bin/env bash
# Makes the owner's Android upload key and prints what to paste into the
# repo's Actions secrets. Run it once, in a GitHub Codespace on this repo or on
# any computer with Java 17 or newer (it needs keytool). Walkthrough:
# docs/PLUGINS.md.
#
#   tools/make_upload_key.sh [output folder]   # default: ~/aetd-upload-key
#
# The key and its password are written outside the repo, never committed. Keep
# a copy of both somewhere safe: Play only accepts uploads signed with this key
# (a lost upload key can be reset through Play Console, which takes a while).
set -euo pipefail

out="${1:-$HOME/aetd-upload-key}"
keystore="$out/upload-key.jks"
alias_name="upload"

if ! command -v keytool >/dev/null 2>&1; then
  echo "error: keytool not found. Install a JDK (17 or newer) or use a GitHub Codespace." >&2
  exit 1
fi
if [ -e "$out" ] && [ -n "$(ls -A "$out" 2>/dev/null)" ]; then
  echo "error: $out already exists and isn't empty. Pick a new folder; this script never overwrites a key." >&2
  exit 1
fi
mkdir -p "$out"
if git -C "$out" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: $out is inside a git repository, where the key could get committed. Use a folder outside it (the default is ~/aetd-upload-key)." >&2
  rmdir "$out" 2>/dev/null || true
  exit 1
fi
chmod 700 "$out"

# 32 random letters and digits. Godot needs the key and store passwords to be
# the same, which is what a PKCS12 keystore does anyway.
password=""
while [ "${#password}" -lt 32 ]; do
  password+="$(head -c 64 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
done
password="${password:0:32}"

if ! keytool_out="$(keytool -genkeypair -noprompt -storetype PKCS12 -keystore "$keystore" \
  -storepass "$password" -keypass "$password" -alias "$alias_name" \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Alien Empire TD upload key" 2>&1)"; then
  echo "error: keytool couldn't make the key:" >&2
  printf '%s\n' "$keytool_out" >&2
  exit 1
fi

base64 < "$keystore" | tr -d '\n' > "$out/ANDROID_KEYSTORE_BASE64.txt"
printf '%s' "$password" > "$out/ANDROID_KEYSTORE_PASSWORD.txt"
printf '%s' "$alias_name" > "$out/ANDROID_KEY_ALIAS.txt"
chmod 600 "$keystore" "$out/ANDROID_KEYSTORE_BASE64.txt" "$out/ANDROID_KEYSTORE_PASSWORD.txt" "$out/ANDROID_KEY_ALIAS.txt"

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

Back the key up before you delete anything: save the text of
ANDROID_KEYSTORE_BASE64.txt and the password together in a password manager.
Together they are the whole key ("base64 -d" turns the text back into
upload-key.jks). Then delete this folder, and the codespace if you used one.

The key's SHA-1, needed later for Play Games sign-in on sideloaded builds:
  $sha1
EOF
