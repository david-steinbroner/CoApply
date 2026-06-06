#!/usr/bin/env bash
# CoApply — resolve the user's profile folder path.
#
# Why this exists: a plugin's userConfig value (profile_dir) is only exported
# as $CLAUDE_PLUGIN_OPTION_PROFILE_DIR to plugin SUBPROCESSES (hooks, MCP
# servers) — NOT to the Bash-tool calls a skill makes. So reading the env var
# from inside a skill returns empty for normal users.
#
# Resolution order (first hit wins):
#   1. $CLAUDE_PLUGIN_OPTION_PROFILE_DIR   — subprocess contexts / user export
#   2. ~/.coapply_profile_path             — a flat one-line file setup writes;
#                                            trivially POSIX, no python3/jq needed
#   3. ~/.claude/settings.json fallback    — best-effort parse of the userConfig
#                                            (python3 -> jq -> POSIX grep/sed)
#
# The flat file (2) is the robust primary path: `/coapply:setup` writes it once
# the profile dir is known, so day-to-day commands never depend on parsing the
# nested settings.json (whose key is pluginConfigs["coapply@<mkt>"].options.profile_dir
# and is brittle without jq/python3). The settings.json read stays as a fallback
# for the very first run before the flat file is written.
#
# Prints the resolved absolute path on stdout (empty line if not configured),
# always exits 0. Skills treat empty output as "not configured yet".
set -uo pipefail

# 1) Env var — present in subprocess contexts, or if the user exported it.
if [ -n "${CLAUDE_PLUGIN_OPTION_PROFILE_DIR:-}" ]; then
  printf '%s\n' "$CLAUDE_PLUGIN_OPTION_PROFILE_DIR"
  exit 0
fi

# 2) Flat file — the robust, dependency-free path. One line: the absolute path.
FLAT="${HOME}/.coapply_profile_path"
if [ -f "$FLAT" ]; then
  # first non-empty line, trimmed of surrounding whitespace
  val="$(sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;}' "$FLAT" 2>/dev/null)"
  if [ -n "$val" ]; then
    printf '%s\n' "$val"
    exit 0
  fi
fi

# 3) settings.json fallback. Scan any "coapply@<marketplace>" plugin config.
_read_python() {
  python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for k, v in (d.get("pluginConfigs") or {}).items():
    if k.startswith("coapply@"):
        p = ((v or {}).get("options") or {}).get("profile_dir", "")
        if p:
            print(p)
            break
PY
}

_read_jq() {
  jq -r '(.pluginConfigs // {}) | to_entries[]
         | select(.key | startswith("coapply@"))
         | .value.options.profile_dir // empty' "$1" 2>/dev/null | head -1
}

# POSIX fallback — no python3/jq. `profile_dir` is CoApply's own userConfig key,
# so the first match is ours. Handles minified or pretty-printed JSON and spaces.
_read_posix() {
  grep -o '"profile_dir"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" 2>/dev/null \
    | head -1 \
    | sed 's/.*:[[:space:]]*"//; s/"$//'
}

for cfg in "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json"; do
  [ -f "$cfg" ] || continue
  val=""
  if command -v python3 >/dev/null 2>&1; then val="$(_read_python "$cfg")"; fi
  if [ -z "$val" ] && command -v jq >/dev/null 2>&1; then val="$(_read_jq "$cfg")"; fi
  if [ -z "$val" ]; then val="$(_read_posix "$cfg")"; fi
  if [ -n "$val" ]; then
    printf '%s\n' "$val"
    exit 0
  fi
done

# Not configured — print nothing; the calling skill prompts the user to set it.
exit 0
