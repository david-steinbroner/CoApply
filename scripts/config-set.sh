#!/usr/bin/env bash
# CoApply — set one key in the user's coapply.config.json without losing the others.
#
# Why this exists: the config was written with `printf '{"tier": "%s"}' > config`,
# which is correct only while the file holds exactly one key. The moment a second
# setting lands, changing the tier silently deletes it. This merges instead.
#
# Usage: config-set.sh <profile_dir> <key> <value>
# Exit:  0 written · 2 usage/unwritable
#
# Values are treated as JSON strings. Keys are restricted to a safe charset so a
# key can never inject structure into the file.
set -uo pipefail
export LC_ALL=C LANG=C

PROFILE_DIR="${1:-}"; KEY="${2:-}"; VAL="${3:-}"
[ -n "$PROFILE_DIR" ] && [ -n "$KEY" ] && [ -n "$VAL" ] || {
  printf 'usage: config-set.sh <profile_dir> <key> <value>\n' >&2; exit 2; }
[ -d "$PROFILE_DIR" ] || { printf 'config-set: no such profile dir: %s\n' "$PROFILE_DIR" >&2; exit 2; }
case "$KEY$VAL" in *[!A-Za-z0-9_.-]*) printf 'config-set: key/value may only contain A-Za-z0-9_.-\n' >&2; exit 2 ;; esac

CFG="$PROFILE_DIR/coapply.config.json"
TMP="$CFG.tmp.$$"

if command -v python3 >/dev/null 2>&1; then
  # Preferred path: a real parser, so unknown keys and nesting survive untouched.
  python3 - "$CFG" "$KEY" "$VAL" > "$TMP" <<'PY' || { rm -f "$TMP"; exit 2; }
import json, sys, os
cfg, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
d = {}
if os.path.exists(cfg):
    try:
        d = json.load(open(cfg))
        if not isinstance(d, dict):
            d = {}
    except Exception:
        d = {}          # unreadable config: rebuild rather than fail the user's command
d[key] = val
print(json.dumps(d, indent=2))
PY
else
  # Fallback for a machine without python3 (resolve-profile-dir.sh documents the same
  # contract). Flat one-level config only, which is all CoApply writes.
  if [ -f "$CFG" ]; then
    # Drop any existing entry for this key, keep the rest, then re-add it.
    _body=$(tr -d '\n' < "$CFG" \
      | sed 's/^[[:space:]]*{//; s/}[[:space:]]*$//' \
      | tr ',' '\n' \
      | grep -vE "\"$KEY\"[[:space:]]*:" \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
      | grep -v '^$' \
      | paste -sd',' -)
  else
    _body=""
  fi
  if [ -n "$_body" ]; then
    printf '{%s,"%s":"%s"}\n' "$_body" "$KEY" "$VAL" > "$TMP"
  else
    printf '{"%s":"%s"}\n' "$KEY" "$VAL" > "$TMP"
  fi
fi

mv "$TMP" "$CFG" 2>/dev/null || { rm -f "$TMP"; printf 'config-set: could not write %s\n' "$CFG" >&2; exit 2; }
printf 'set %s=%s in %s\n' "$KEY" "$VAL" "$CFG"
