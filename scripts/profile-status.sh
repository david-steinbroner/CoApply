#!/usr/bin/env bash
# CoApply — resolve the profile folder AND report its readiness in one call.
#
# Why this exists: skills used to do this in an inline Bash block that wrapped
# the resolver in a command substitution —
#   PROFILE_DIR="$(".../resolve-profile-dir.sh")"; if [ -z "$PROFILE_DIR" ] ...
# A `VAR="$(...)"` assignment-wrapped substitution can't be covered by a user's
# permission allowlist, so it prompted on EVERY command. Running this one script
# bare instead is a single prefix-matchable call the user can pre-approve once
# (see README "fewer permission prompts"), and it also moves the touch/grep/find
# probing OUT of an inline compound command (which prompted too).
#
# It calls resolve-profile-dir.sh internally, then probes the folder and prints a
# stable, line-per-field block. Field values are `yes`/`no` (or a path). Always
# exits 0; an empty PROFILE_DIR means "not configured yet".
#
# Fields:
#   PROFILE_DIR=<abs path or empty>
#   RUNS_DIR=<$APPLY_RUNS_DIR override, else PROFILE_DIR/runs, empty if no dir>
#   WRITABLE=<yes|no>          folder exists and is writable (touch probe)
#   IDENTITY=<yes|no>          identity.md exists
#   IDENTITY_FILLED=<yes|no>   identity.md has real (alphabetic) content
#   SKILLS=<yes|no>            skills-experience.md exists
#   RESUME=<yes|no>            at least one *.md under resumes/
#   PLACEHOLDERS=<yes|no>      unfilled <Xxx> tokens in identity/skills-experience
set -uo pipefail

HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
DIR="$("$HERE/resolve-profile-dir.sh")"

printf 'PROFILE_DIR=%s\n' "$DIR"

# Nothing else is knowable without a folder — emit the not-configured shape.
if [ -z "$DIR" ]; then
  printf 'RUNS_DIR=\nWRITABLE=no\nIDENTITY=no\nIDENTITY_FILLED=no\nSKILLS=no\nRESUME=no\nPLACEHOLDERS=no\n'
  exit 0
fi

printf 'RUNS_DIR=%s\n' "${APPLY_RUNS_DIR:-$DIR/runs}"

# Writable? (folder present AND a probe file can be created/removed)
if [ -d "$DIR" ] && touch "$DIR/.coapply_wtest" 2>/dev/null; then
  rm -f "$DIR/.coapply_wtest" 2>/dev/null
  printf 'WRITABLE=yes\n'
else
  printf 'WRITABLE=no\n'
fi

yesno() { [ "$1" = 0 ] && printf '%s=yes\n' "$2" || printf '%s=no\n' "$2"; }

[ -f "$DIR/identity.md" ]; yesno $? IDENTITY
grep -q '[A-Za-z]' "$DIR/identity.md" 2>/dev/null; yesno $? IDENTITY_FILLED
[ -f "$DIR/skills-experience.md" ]; yesno $? SKILLS

# A resume = any *.md under resumes/
if find "$DIR/resumes" -maxdepth 1 -name '*.md' 2>/dev/null | grep -q .; then
  printf 'RESUME=yes\n'
else
  printf 'RESUME=no\n'
fi

# Unfilled <Xxx> placeholders left in the two core files
if grep -qnE '<[A-Z][^>]*>' "$DIR/identity.md" "$DIR/skills-experience.md" 2>/dev/null; then
  printf 'PLACEHOLDERS=yes\n'
else
  printf 'PLACEHOLDERS=no\n'
fi

exit 0
