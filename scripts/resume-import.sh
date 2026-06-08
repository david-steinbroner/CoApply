#!/usr/bin/env bash
# CoApply — deterministic helpers for resume-import onboarding.
#
# The drafting itself is model-driven (profile/prompts/onboarding/import-resume.md).
# These are the parts that must NOT be left to the model's judgment:
#   - the fail-closed parse sanity gate (don't draft a profile from OCR garbage),
#   - the bloat-cap word check (the profile is sent on every run — keep it lean),
#   - atomic, placeholder-neutralized file writes (never half-write; never emit a
#     <[A-Z]…> token that would later trip /coapply:start's placeholder preflight).
#
# Usage:
#   resume-import.sh sanity <file>     -> "OK (<n> words)" | "TOO_SHORT (<n>)" | "NO_KEYWORDS (<n>)" | "NO_FILE"
#   resume-import.sh wordcheck <file>  -> "<n> OK" | "<n> HIGH" | "<n> OVER"   (skills-experience bloat cap)
#   resume-import.sh write <dest>      -> read stdin, neutralize <Xxx> tokens, write atomically (tmp + mv)
#
# Best-effort; exits 0 except on usage error (2). LC_ALL=C for deterministic text ops.
set -uo pipefail
export LC_ALL=C LANG=C

cmd="${1:-}"; file="${2:-}"

words_in() { wc -w < "$1" 2>/dev/null | tr -d ' '; }

case "$cmd" in
  sanity)
    [ -n "$file" ] || { echo "usage: resume-import.sh sanity <file>" >&2; exit 2; }
    [ -f "$file" ] || { echo "NO_FILE"; exit 0; }
    n="$(words_in "$file")"; n="${n:-0}"
    if [ "$n" -lt 100 ]; then echo "TOO_SHORT ($n)"; exit 0; fi
    # Resume keywords — if none, the read is probably garbled/not a resume; fail closed.
    if grep -iqE 'experience|education|employ|work|skills|projects?|summary' "$file"; then
      echo "OK ($n words)"
    else
      echo "NO_KEYWORDS ($n)"
    fi
    ;;

  wordcheck)
    [ -n "$file" ] || { echo "usage: resume-import.sh wordcheck <file>" >&2; exit 2; }
    n="$(words_in "$file")"; n="${n:-0}"
    # §16.C: target under ~800; hard concern at ~1000.
    if [ "$n" -gt 1000 ]; then echo "$n OVER"
    elif [ "$n" -gt 800 ]; then echo "$n HIGH"
    else echo "$n OK"; fi
    ;;

  write)
    [ -n "$file" ] || { echo "usage: resume-import.sh write <dest>" >&2; exit 2; }
    dir="$(dirname "$file")"; mkdir -p "$dir" 2>/dev/null || true
    tmp="$file.coapply.tmp.$$"
    # Neutralize placeholder-shaped tokens <[A-Z]…> -> (…) so transcribed resume content
    # (e.g. List<String>, <EMAIL>) can't later match /coapply:start's <[A-Z][^>]*> preflight
    # grep and block the user's first run. Lowercase <foo> is left alone (the grep ignores it).
    sed -E 's/<([A-Z][^>]*)>/(\1)/g' > "$tmp"
    mv -f "$tmp" "$file"
    echo "WROTE $file"
    ;;

  *)
    echo "usage: resume-import.sh {sanity|wordcheck|write} <file>" >&2
    exit 2
    ;;
esac
exit 0
