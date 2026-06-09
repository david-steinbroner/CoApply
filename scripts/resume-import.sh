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
#   resume-import.sh write-raw <dest>  -> like write but NO neutralization (for identity.md, where a
#                                         stray <placeholder> should be CAUGHT by start's preflight,
#                                         not masked into (placeholder))
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
    # Near-empty: nothing to build from. (A real resume — even a new grad's — clears this.)
    if [ "$n" -lt 15 ]; then echo "EMPTY ($n)"; exit 0; fi
    # Keyword presence is the "is this resume-like" signal, NOT length: short real resumes
    # are common and legitimate. No resume keywords at a real length => wrong paste / not a
    # resume. (Jumbled-but-keyworded text passes here on purpose — the script can't detect
    # column-merge garble; the model's reflect-back step is the catch for that.)
    if grep -iqE 'experience|education|employ|work|skills|projects?|summary|volunteer|certification' "$file"; then
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

  write-raw)
    [ -n "$file" ] || { echo "usage: resume-import.sh write-raw <dest>" >&2; exit 2; }
    dir="$(dirname "$file")"; mkdir -p "$dir" 2>/dev/null || true
    tmp="$file.coapply.tmp.$$"
    # No neutralization: identity.md is structured fields, not free resume text. If a
    # <placeholder> slips through, it MUST stay <…> so start's preflight flags it.
    cat > "$tmp"
    mv -f "$tmp" "$file"
    echo "WROTE $file"
    ;;

  *)
    echo "usage: resume-import.sh {sanity|wordcheck|write|write-raw} <file>" >&2
    exit 2
    ;;
esac
exit 0
