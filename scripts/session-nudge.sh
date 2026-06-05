#!/usr/bin/env bash
# CoApply — SessionStart nudge.
# Points a new user at the next step until their profile is configured, then
# stays silent forever after. No state file: "configured" is simply whether
# identity.md exists in the chosen profile folder, so the nudge self-suppresses
# the moment setup is complete and re-appears if the profile is removed.
set -euo pipefail

PROFILE_DIR="${CLAUDE_PLUGIN_OPTION_PROFILE_DIR:-}"

# Configured (profile folder set AND has identity.md) → say nothing.
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/identity.md" ]; then
  exit 0
fi

# Not configured yet → one CLI-visible line pointing at the next step.
if [ -z "$PROFILE_DIR" ]; then
  printf '%s\n' '{"systemMessage": "👋 CoApply is installed, but no profile folder is set yet. Run /plugin → CoApply → set a Profile folder, then run /coapply:setup."}'
else
  printf '%s\n' '{"systemMessage": "👋 CoApply is installed. Run /coapply:setup to fill in your profile and start applying."}'
fi

exit 0
