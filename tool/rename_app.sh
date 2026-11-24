#!/usr/bin/env bash
# Rename the app everywhere it is user-visible.
#
#   tool/rename_app.sh "New Name"                    # display name only
#   tool/rename_app.sh "New Name" com.example.newapp # name + app/bundle ID
#
# Updates config/brand.properties (read by Android + iOS builds) and
# lib/app/brand.dart (used in the UI). Changing the ID after you have set up
# Google sign-in or published to the stores requires updating those too.
set -euo pipefail
cd "$(dirname "$0")/.."

name="${1:?usage: tool/rename_app.sh \"New Name\" [new.app.id]}"
id="${2:-}"

if [[ "$name" =~ [\"\'\$\&\<\>\\] ]]; then
  echo "Please avoid quotes, \$, &, <, > and backslashes in the app name." >&2
  exit 1
fi
if [[ -n "$id" && ! "$id" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]]; then
  echo "App ID must look like com.example.app (lowercase, dots)." >&2
  exit 1
fi

tmp=$(mktemp)
awk -v n="$name" -v i="$id" -F= '
  $1=="APP_DISPLAY_NAME" { print "APP_DISPLAY_NAME=" n; next }
  $1=="APP_ID" && i!=""  { print "APP_ID=" i; next }
  { print }' config/brand.properties > "$tmp" && mv "$tmp" config/brand.properties

APP_NAME="$name" perl -0pi -e "s/static const name = '[^']*';/static const name = '\$ENV{APP_NAME}';/" lib/app/brand.dart

echo "Renamed to: $name${id:+ ($id)}"
cat config/brand.properties
grep -n "static const name" lib/app/brand.dart
