#!/usr/bin/env bash
# CoApply — SessionStart hook. Two jobs, both quiet by default:
#   1. Announce a version change. Claude Code auto-applies plugin updates with no
#      author-controllable approval, and only a generic "reload" notice — it never
#      shows the new version. So we read our plugin.json version, compare it to the
#      last version seen on this machine, and announce the real number ONCE when it
#      changes, then stay silent until it changes again.
#   2. Nudge an unconfigured user toward setup until their profile exists, then
#      stay silent (no state file: "configured" = identity.md exists).
set -euo pipefail

# --- resolve our installed version from plugin.json (POSIX; no jq dependency) ---
VERSION=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]; then
  VERSION="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null \
    | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
fi

# --- version-change announcement (only when it actually changed) ----------------
version_msg=""
STATE="${HOME:-/tmp}/.coapply_last_version"
if [ -n "$VERSION" ]; then
  last=""
  [ -f "$STATE" ] && last="$(sed -n '1p' "$STATE" 2>/dev/null | tr -d '[:space:]')"
  if [ "$VERSION" != "$last" ]; then
    printf '%s\n' "$VERSION" > "$STATE" 2>/dev/null || true
    # Only announce an *update* if a prior version was recorded (not a fresh install).
    [ -n "$last" ] && version_msg="✅ CoApply updated to v${VERSION} — run /coapply:help to see what changed."
  fi
fi

# --- profile-configured check --------------------------------------------------
PROFILE_DIR="${CLAUDE_PLUGIN_OPTION_PROFILE_DIR:-}"
if [ -z "$PROFILE_DIR" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PROFILE_DIR="$("${CLAUDE_PLUGIN_ROOT}/scripts/resolve-profile-dir.sh" 2>/dev/null || true)"
fi

nudge_msg=""
if [ -z "$PROFILE_DIR" ]; then
  nudge_msg="👋 CoApply${VERSION:+ v$VERSION} is installed, but no profile folder is set yet. Run /plugin → CoApply → set a Profile folder, then run /coapply:setup."
elif [ ! -f "$PROFILE_DIR/identity.md" ]; then
  nudge_msg="👋 CoApply${VERSION:+ v$VERSION} is installed. Run /coapply:setup to fill in your profile and start applying."
fi

# --- emit a single systemMessage (combine if both apply); silent if neither ----
msg="$version_msg"
if [ -n "$nudge_msg" ]; then
  [ -n "$msg" ] && msg="$msg  $nudge_msg" || msg="$nudge_msg"
fi
[ -n "$msg" ] || exit 0

# Hand-build JSON (no jq). Escape backslashes and double quotes in the message.
esc="$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')"
printf '{"systemMessage": "%s"}\n' "$esc"
exit 0
