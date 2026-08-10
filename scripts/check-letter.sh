#!/usr/bin/env bash
# CoApply — run the §1a mechanical gates from docs/features/letter-handoff/spec.md
# against a finished cover letter (in-engine output or a letter pasted back from an
# external model). Exits non-zero on any violation.
#
# Why this exists: the acceptance bar for the letter feature was, until now, prose
# plus a memory of one good run. This turns "at least as good as the reference run"
# into a repeatable test. It also closes spec §3's gap — the in-engine agent reads
# the user's caveats but nothing verifies it honored them.
#
# FIELD-AGNOSTIC BY CONSTRUCTION. Not one banned phrase, forbidden claim, or word
# range is hardcoded here. Everything is derived at runtime from the engine's shared
# rule files and the user's own profile. A rule this script can't derive is a rule it
# reports as UNCHECKED — never one it invents.
#
# ── The caveat trap (spec §2) ────────────────────────────────────────────────────
# Caveat blocks are NOT findable by fixed-string grep. In a real profile only 2 of 9
# used the header "Caveat for downstream agents"; the rest were typed variants
# (Jargon/Timing/Naming/Currency caveat) plus a bare "Never claim ..." line. A header
# match finds 2 and silently drops 7 — which is worse than not checking, because it
# looks like coverage. So: this script FINDS the blocks with a broad matcher, and
# requires their ceilings be DECLARED once in a ceilings file. Machine finds, human
# states. Anything undeclared is reported, never assumed safe.
#
# Usage:
#   check-letter.sh <letter-file> [--profile DIR] [--ceilings FILE]
#                                 [--words MIN-MAX] [--init-ceilings] [-q]
#
# Exit: 0 PASS · 1 FAIL (a gate was violated) · 2 usage/unreadable input
#       3 INCOMPLETE (nothing violated, but a gate could not be evaluated)
#
# Exit 3 is the point of the design: "clean" and "I couldn't check the caveats" must
# never be the same green.
set -uo pipefail
export LC_ALL=C LANG=C  # deterministic, locale-independent grep/awk/sort

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Heading words that open a "these are forbidden" zone in a rules file. Extraction is
# HEADING-SCOPED, and that is load-bearing: the humanizer rules carry the line
# `Use hyphens " - " for asides, never em dashes` under a MANDATORY heading. A
# line-level scan would extract " - " as a banned phrase and fail every letter ever
# written. Only headings that declare a ban open the zone.
BAN_HEADING_RE="never|banned|avoid|don'?t|do not|forbidden|prohibited"

# A caveat is any line that either calls itself a caveat or states a bare negative
# claim rule. Deliberately broad — see "The caveat trap" above.
CAVEAT_RE="caveat|never (claim|say|write|assert|describe|call|refer|render|present|imply)|(do not|don'?t) (claim|say|write|assert|describe|render|present|imply|lead with|name|fetch|use)"

# Profile files that plausibly carry claim ceilings. principles.md is excluded on
# purpose: it's a large domain-lens library, not a claims file, and folding it in
# buries the real caveats in prose that merely sounds negative.
CAVEAT_FILES="skills-experience.md identity.md facts.md positioning-modes.md"

LETTER=""; PROFILE_DIR=""; CEILINGS=""; WORDS_ARG=""; INIT=0; QUIET=0

usage() {
  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-2}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)        PROFILE_DIR="${2:-}"; shift 2 || usage ;;
    --ceilings)       CEILINGS="${2:-}";    shift 2 || usage ;;
    --words)          WORDS_ARG="${2:-}";   shift 2 || usage ;;
    --init-ceilings)  INIT=1; shift ;;
    -q|--quiet)       QUIET=1; shift ;;
    -h|--help)        usage 0 ;;
    -*)               printf 'check-letter: unknown option %s\n' "$1" >&2; usage 2 ;;
    *)                [ -z "$LETTER" ] && LETTER="$1" || { printf 'check-letter: unexpected argument %s\n' "$1" >&2; usage 2; }; shift ;;
  esac
done

# --- profile resolution (reuse the one resolver; never re-parse settings.json) ----
if [ -z "$PROFILE_DIR" ]; then
  PROFILE_DIR="$(bash "$ROOT/scripts/resolve-profile-dir.sh" 2>/dev/null)"
fi
[ -n "$PROFILE_DIR" ] && [ -d "$PROFILE_DIR" ] || PROFILE_DIR=""

if [ "$INIT" = 0 ]; then
  [ -n "$LETTER" ] || { printf 'check-letter: no letter file given\n' >&2; usage 2; }
  [ -r "$LETTER" ] || { printf 'check-letter: cannot read %s\n' "$LETTER" >&2; exit 2; }
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t coapply-checkletter)" || exit 2
trap 'rm -rf "$TMP"' EXIT

say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$1"; }
warn() { printf '%s\n' "$1"; }   # warnings print even in quiet mode

# =================================================================================
# Extractors
# =================================================================================

# Pull banned phrases out of a markdown rules file.
#
# Two shapes cover every real rules file seen so far:
#   1. quoted items       - "proven track record"   /   **Closers:** "I would welcome"
#   2. bare comma lists   **Puffy verbs:** Spearheaded, Leveraged, Orchestrated
# A line with quotes uses shape 1 only, so an "instead, write X" example that shares
# the line can't be mistaken for a ban... and shape 2 is capped at 6 words per item so
# stray prose under a ban heading can't pollute the list with sentence fragments.
extract_banned() {
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function emit(x,   y, n, w, i) {
      y = trim(x)
      sub(/[.,;:!?]+$/, "", y); y = trim(y)
      sub(/\([^)]*\)$/, "", y); y = trim(y)          # "passionate (especially this one)"
      sub(/[.,;:!?]+$/, "", y); y = trim(y)
      sub(/^\*\*/, "", y); sub(/\*\*$/, "", y); y = trim(y)
      # Placeholder truncation: "Intersection of X and Y" is a template, not a phrase.
      # Keep the literal head so the grep still bites.
      if (match(y, /[ \t]+[XY]([ \t]|$)/)) y = trim(substr(y, 1, RSTART - 1))
      if (length(y) < 3) return
      if (y ~ /:$/) return
      n = split(y, w, /[ \t]+/)
      if (n > 6) return                              # a sentence, not a banned phrase
      print tolower(y)
    }
    # Curly quotes normalised to straight ones as an ALTERNATION of literal
    # characters, never a bracket expression — under LC_ALL=C a bracket would match
    # individual UTF-8 bytes, and \x escapes are not portable across awks.
    { gsub(/“|”/, "\"") }
    /^#+[ \t]/ { inban = (tolower($0) ~ BANRE); next }
    !inban { next }
    {
      s = $0; found = 0
      # rs/rl are captured BEFORE emit() runs: emit calls match() itself, which
      # clobbers the global RSTART/RLENGTH this loop advances on. Reading them after
      # the call rewinds the cursor and spins forever.
      while (match(s, /"[^"]+"/)) {
        rs = RSTART; rl = RLENGTH
        emit(substr(s, rs + 1, rl - 2)); found = 1
        s = substr(s, rs + rl)
      }
      if (found) next
      p = $0
      sub(/^[ \t]*[-*+][ \t]+/, "", p)               # bullet marker
      sub(/^\*\*[^*]+:\*\*[ \t]*/, "", p)            # **Label:** prefix
      n = split(p, a, /,|[ \t]+\/[ \t]+/)
      for (i = 1; i <= n; i++) emit(a[i])
    }
  ' BANRE="$BAN_HEADING_RE" "$1" 2>/dev/null
}

# Collapse a caveat line to a stable identity. Content-addressed, not line-numbered:
# ordinary edits elsewhere in the profile must not invalidate every declared ceiling,
# but editing the caveat ITSELF must — that's exactly when a ceiling needs re-confirming.
hash8() {
  if   command -v shasum  >/dev/null 2>&1; then shasum -a 1 | cut -c1-8
  elif command -v sha1sum >/dev/null 2>&1; then sha1sum      | cut -c1-8
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha1 | sed 's/.*[= ]//' | cut -c1-8
  else cksum | awk '{ printf "%08x\n", $1 }'
  fi
}

# Discover caveat blocks across the profile. Writes "<id>\t<file>:<line>\t<text>".
discover_caveats() {
  [ -n "$PROFILE_DIR" ] || return 0
  {
    for f in $CAVEAT_FILES; do [ -f "$PROFILE_DIR/$f" ] && printf '%s\n' "$PROFILE_DIR/$f"; done
    ls "$PROFILE_DIR"/playbooks/*.md 2>/dev/null
  } | while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -nEi -- "$CAVEAT_RE" "$f" 2>/dev/null | while IFS= read -r hit; do
      ln="${hit%%:*}"; txt="${hit#*:}"
      norm="$(printf '%s' "$txt" | tr -s ' \t' ' ' | sed 's/^ *//; s/ *$//')"
      [ -n "$norm" ] || continue
      id="$(printf '%s' "$norm" | hash8)"
      printf '%s\t%s:%s\t%s\n' "$id" "$(basename "$f")" "$ln" "$norm"
    done
  done
}

# Candidate forbidden strings for --init-ceilings. Only ever SUGGESTIONS, emitted
# commented out.
#
# Why never automatic: caveats routinely name the approved wording in the same breath
# as the banned one — `Don't lead with the internal name "<X>" — describe the mechanic
# ("<plain-English X>")`. Grabbing every quoted string would forbid the APPROVED
# REPLACEMENT. So we split the caveat into clauses and read only the clauses carrying a
# negative. Even then "don't lead with X" is not "never mention X", so the human states
# the ceiling; the machine only points at it.
suggest_forbids() {
  printf '%s\n' "$1" | awk '
    { gsub(/“|”/, "\"") }
    {
      n = split($0, c, /—|–|;| - |\. /)
      for (i = 1; i <= n; i++) {
        if (tolower(c[i]) !~ /never|don'"'"'t|do not|dont/) continue
        s = c[i]
        while (match(s, /"[^"]+"/)) {
          q = substr(s, RSTART + 1, RLENGTH - 2)
          if (length(q) >= 3) print q
          s = substr(s, RSTART + RLENGTH)
        }
      }
    }'
}

# Find a stated word range in the user's own files. Never guessed — an unstated range
# is reported UNCHECKED, because inventing one would fail letters against a bar the
# user never set.
derive_word_range() {
  for f in "$PROFILE_DIR/playbooks/cover-letter.md" "$PROFILE_DIR/voice-profile.md" \
           "$ROOT/profile/prompts/agents/cover-letter.md"; do
    [ -f "$f" ] || continue
    r="$(grep -ohEi '[0-9]{2,4}[ ]*(-|to|–|—)[ ]*[0-9]{2,4}[ ]*words' "$f" 2>/dev/null | head -1)"
    if [ -n "$r" ]; then
      printf '%s\t%s\n' "$(printf '%s' "$r" | grep -oE '[0-9]{2,4}' | tr '\n' '-' | sed 's/-$//')" "$(basename "$f")"
      return 0
    fi
  done
  return 1
}

# =================================================================================
# Ceilings file
# =================================================================================

if [ -z "$CEILINGS" ] && [ -n "$LETTER" ]; then
  d="$(cd "$(dirname "$LETTER")" && pwd)"
  [ -f "$d/.letter-ceilings" ] && CEILINGS="$d/.letter-ceilings"   # run-local, per application
fi
if [ -z "$CEILINGS" ] && [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/.letter-ceilings" ]; then
  CEILINGS="$PROFILE_DIR/.letter-ceilings"                          # the user's standing list
fi

discover_caveats | sort -u > "$TMP/caveats.tsv"
CAVEAT_COUNT="$(wc -l < "$TMP/caveats.tsv" | tr -d ' ')"

# --- --init-ceilings -------------------------------------------------------------
if [ "$INIT" = 1 ]; then
  printf '# CoApply letter ceilings\n'
  printf '# Generated by check-letter.sh --init-ceilings. Edit, then save as\n'
  printf '#   %s/.letter-ceilings   (standing)   or   <run-folder>/.letter-ceilings   (one job)\n' "${PROFILE_DIR:-<profile>}"
  printf '#\n'
  printf '# Directives:\n'
  printf '#   words MIN-MAX        the word range a letter must land in\n'
  printf '#   forbid <id> <regex>  FAIL the letter if this pattern appears (ERE, case-insensitive)\n'
  printf '#   ack    <id>          this caveat has nothing greppable (a "confirm with me" note,\n'
  printf '#                        a timing question) — reviewed, deliberately no pattern\n'
  printf '#\n'
  printf '# Every caveat below needs a forbid or an ack, or the coverage gate stays UNCHECKED.\n'
  printf '# Suggested patterns are COMMENTED OUT on purpose: only you can state the ceiling.\n'
  printf '# State the ceiling, do not just ban the noun. A pattern that bans a claim the profile\n'
  printf '# ALLOWS is worse than none — it fails good letters until you stop trusting the check.\n'
  printf '# Keep patterns simple; a heavily nested regex can hang grep on a long line.\n\n'
  if r="$(derive_word_range)"; then
    printf 'words %s\n\n' "${r%%	*}"
  else
    printf '# words 250-400   <- no range found in your profile; set one\n\n'
  fi
  if [ "$CAVEAT_COUNT" = 0 ]; then
    printf '# No caveats found in %s\n' "${PROFILE_DIR:-<profile not configured>}"
  fi
  while IFS="$(printf '\t')" read -r id loc txt; do
    [ -n "$id" ] || continue
    printf '# %s\n' "$loc"
    printf '#   %s\n' "$txt"
    suggest_forbids "$txt" | while IFS= read -r s; do
      [ -n "$s" ] && printf '#forbid %s %s\n' "$id" "$s"
    done
    printf '#ack %s\n\n' "$id"
  done < "$TMP/caveats.tsv"
  exit 0
fi

: > "$TMP/forbid.tsv"; : > "$TMP/covered.txt"
WORDS_SRC=""; RANGE=""
if [ -n "$CEILINGS" ] && [ -r "$CEILINGS" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    kw="${line%% *}"; rest="${line#* }"
    case "$kw" in
      words)  RANGE="$(printf '%s' "$rest" | tr -d ' ')"; WORDS_SRC="$(basename "$CEILINGS")" ;;
      forbid) id="${rest%% *}"; pat="${rest#* }"
              [ "$id" = "$pat" ] && continue                    # no pattern given
              printf '%s\t%s\n' "$id" "$pat" >> "$TMP/forbid.tsv"
              printf '%s\n' "$id" >> "$TMP/covered.txt" ;;
      ack)    id="${rest%% *}"; printf '%s\n' "$id" >> "$TMP/covered.txt" ;;
    esac
  done < "$CEILINGS"
fi

# --words wins over the ceilings file (a deliberate one-off override).
if [ -n "$WORDS_ARG" ]; then RANGE="$(printf '%s' "$WORDS_ARG" | tr -d ' ')"; WORDS_SRC="--words"; fi
if [ -z "$RANGE" ] && r="$(derive_word_range)"; then
  RANGE="${r%%	*}"; WORDS_SRC="${r##*	}"
fi

# =================================================================================
# Gates
# =================================================================================

violations=0; unchecked=0
result() {  # <status> <gate> <detail>
  case "$1" in
    FAIL) violations=$((violations + 1)) ;;
    "--") unchecked=$((unchecked + 1)) ;;
  esac
  [ "$QUIET" = 1 ] && [ "$1" = PASS ] && return 0
  printf '  [%-4s] %-18s %s\n' "$1" "$2" "$3"
}

say ""
say "CoApply letter check — $(basename "$LETTER")"
say "  profile:  ${PROFILE_DIR:-(not configured)}"
say "  ceilings: ${CEILINGS:-(none)}"
say ""

# --- Gate 1: banned phrases ------------------------------------------------------
: > "$TMP/banned.txt"; srcs=0
for f in "$ROOT/profile/prompts/shared/anti-ai-detection.md" \
         "$ROOT/profile/prompts/shared/humanizer-rules.md" \
         "${PROFILE_DIR:-/nonexistent}/voice-profile.md" \
         "${PROFILE_DIR:-/nonexistent}/playbooks/cover-letter.md"; do
  [ -f "$f" ] || continue
  extract_banned "$f" >> "$TMP/banned.txt"
  srcs=$((srcs + 1))
done
# A blank line in a -f pattern file matches EVERY line. Never let one through.
grep -v '^[[:space:]]*$' "$TMP/banned.txt" 2>/dev/null | sort -u > "$TMP/banned.sorted"
mv "$TMP/banned.sorted" "$TMP/banned.txt"
BANNED_N="$(wc -l < "$TMP/banned.txt" | tr -d ' ')"

if [ "$BANNED_N" = 0 ]; then
  result "--" "banned phrases" "no rule files readable — nothing to check against"
else
  grep -noiFf "$TMP/banned.txt" -- "$LETTER" 2>/dev/null | sort -u -t: -k1,1n -k2,2 > "$TMP/banned-hits.txt"
  n="$(wc -l < "$TMP/banned-hits.txt" | tr -d ' ')"
  if [ "$n" = 0 ]; then
    result PASS "banned phrases" "0 hits ($BANNED_N phrases from $srcs rule file(s))"
  else
    result FAIL "banned phrases" "$n hit(s) of $BANNED_N phrases"
    while IFS= read -r h; do say "           L${h%%:*}: \"${h#*:}\""; done < "$TMP/banned-hits.txt"
  fi
fi

# --- Gate 2: em-dashes -----------------------------------------------------------
grep -n -- '—' "$LETTER" 2>/dev/null > "$TMP/emdash.txt"
EM_N="$(grep -o -- '—' "$LETTER" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$EM_N" = 0 ]; then
  result PASS "em dashes" "0"
else
  result FAIL "em dashes" "$EM_N occurrence(s)"
  while IFS= read -r h; do say "           L${h%%:*}"; done < "$TMP/emdash.txt"
fi

# --- Gate 3: word count ----------------------------------------------------------
# Headings, the generation watermark and HTML comments are scaffolding, not letter.
WORDS="$(sed -e '/^[[:space:]]*#/d' -e '/coapply:/d' -e '/^[[:space:]]*<!--/d' "$LETTER" | wc -w | tr -d ' ')"
if [ -z "$RANGE" ]; then
  result "--" "word count" "$WORDS words — no range stated in your profile or ceilings"
else
  MIN="${RANGE%%-*}"; MAX="${RANGE##*-}"
  if [ "$MIN" -gt 0 ] 2>/dev/null && [ "$MAX" -gt 0 ] 2>/dev/null; then
    if [ "$WORDS" -lt "$MIN" ] || [ "$WORDS" -gt "$MAX" ]; then
      result FAIL "word count" "$WORDS words, outside $MIN-$MAX (from $WORDS_SRC)"
    else
      result PASS "word count" "$WORDS words, within $MIN-$MAX (from $WORDS_SRC)"
    fi
  else
    result "--" "word count" "$WORDS words — unreadable range '$RANGE' from $WORDS_SRC"
  fi
fi

# --- Coverage, computed before gate 4 because gate 4's verdict depends on it -------
sort -u "$TMP/covered.txt" -o "$TMP/covered.txt" 2>/dev/null
cut -f1 "$TMP/caveats.tsv" | sort -u > "$TMP/ids.txt"
MISSING="$(comm -23 "$TMP/ids.txt" "$TMP/covered.txt" | wc -l | tr -d ' ')"
STALE="$(comm -13 "$TMP/ids.txt" "$TMP/covered.txt" | wc -l | tr -d ' ')"
COVERED=$((CAVEAT_COUNT - MISSING))

# --- Gate 4: forbidden claims ----------------------------------------------------
FORBID_N="$(wc -l < "$TMP/forbid.tsv" | tr -d ' ')"
if [ "$FORBID_N" = 0 ]; then
  if [ "$CAVEAT_COUNT" = 0 ]; then
    result "--" "forbidden claims" "no caveats found in the profile — nothing to enforce"
  elif [ "$MISSING" = 0 ]; then
    # Every caveat reviewed and acknowledged as having nothing greppable (a "confirm
    # with me" note, a timing question). Zero patterns is then the correct answer, not
    # a gap — otherwise a fully-reviewed profile could never reach a clean pass.
    result PASS "forbidden claims" "0 patterns — all $CAVEAT_COUNT caveat(s) acknowledged as non-textual"
  else
    result "--" "forbidden claims" "$CAVEAT_COUNT caveat(s) found, 0 ceilings declared — run --init-ceilings"
  fi
else
  : > "$TMP/claim-hits.txt"
  while IFS="$(printf '\t')" read -r id pat; do
    [ -n "$pat" ] || continue
    grep -niEo -- "$pat" "$LETTER" 2>/dev/null | while IFS= read -r h; do
      printf '           L%s [%s] "%s"  (/%s/)\n' "${h%%:*}" "$id" "${h#*:}" "$pat" >> "$TMP/claim-hits.txt"
    done
  done < "$TMP/forbid.tsv"
  hits="$(wc -l < "$TMP/claim-hits.txt" | tr -d ' ')"
  if [ "$hits" = 0 ]; then
    result PASS "forbidden claims" "0 hits ($FORBID_N ceiling pattern(s))"
  else
    result FAIL "forbidden claims" "$hits hit(s) against $FORBID_N ceiling pattern(s)"
    while IFS= read -r h; do say "$h"; done < "$TMP/claim-hits.txt"
  fi
fi

# --- Gate 5: caveat coverage -----------------------------------------------------
if [ "$CAVEAT_COUNT" = 0 ]; then
  if [ -n "$PROFILE_DIR" ]; then
    result "--" "caveat coverage" "no caveat blocks found in the profile"
  else
    result "--" "caveat coverage" "profile not configured"
  fi
else
  if [ "$MISSING" = 0 ]; then
    result PASS "caveat coverage" "$COVERED of $CAVEAT_COUNT caveat(s) declared"
  else
    result "--" "caveat coverage" "$COVERED of $CAVEAT_COUNT declared — $MISSING undeclared"
    comm -23 "$TMP/ids.txt" "$TMP/covered.txt" | while IFS= read -r id; do
      row="$(grep -m1 "^$id	" "$TMP/caveats.tsv")"
      say "           [$id] $(printf '%s' "$row" | cut -f2) — $(printf '%s' "$row" | cut -f3 | cut -c1-70)…"
    done
    say "           run: check-letter.sh --init-ceilings > \"${PROFILE_DIR:-<profile>}/.letter-ceilings\""
  fi
  # A declared id that matches no caveat means the caveat's wording changed. The old
  # ceiling may no longer say what the profile says — re-confirm it, don't trust it.
  if [ "$STALE" != 0 ]; then
    warn "  [WARN] stale ceilings      $STALE declared id(s) match no caveat in the profile — re-confirm them:"
    comm -13 "$TMP/ids.txt" "$TMP/covered.txt" | while IFS= read -r id; do warn "           [$id]"; done
  fi
fi

# =================================================================================
say ""
if [ "$violations" != 0 ]; then
  printf 'FAIL — %s gate(s) violated%s.\n' "$violations" "$([ "$unchecked" != 0 ] && printf ', %s unevaluated' "$unchecked")"
  exit 1
fi
if [ "$unchecked" != 0 ]; then
  printf 'INCOMPLETE — 0 violations, but %s gate(s) could not be evaluated.\n' "$unchecked"
  exit 3
fi
printf 'PASS — every §1a gate clean.\n'
exit 0
