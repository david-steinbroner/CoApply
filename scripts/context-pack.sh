#!/usr/bin/env bash
# CoApply — select the user's saved example letters for one agent role, ranked by
# relevance to this job and capped to a byte budget, and emit them as a VOICE
# reference for the agent. Logs exactly what it picked/dropped so the trust
# receipt reflects reality, not the model's recollection.
#
# Determinism: ranking is `sort` over awk-computed scores with a filename
# tiebreak (POSIX awk array order is undefined, so we never rely on it). The
# agent that calls this receives the pack directly in its own context — the
# orchestrator never buffers it — which avoids output-token limits and keeps the
# log honest (the agent that used the examples is the one that logged them).
#
# Usage: context-pack.sh <profile_dir> <role> <jd_file> <run_dir>
# Prints the example pack (sentinel-wrapped) on stdout, or nothing if there are
# none / the tier excludes them. Always exits 0 (never breaks a run).
set -uo pipefail
export LC_ALL=C LANG=C  # deterministic, locale-independent sort/awk ranking

PROFILE_DIR="${1:-}"
ROLE="${2:-}"
JD_FILE="${3:-}"
RUN_DIR="${4:-}"

[ -n "$PROFILE_DIR" ] && [ -d "$PROFILE_DIR" ] || exit 0
[ -n "$ROLE" ] || exit 0
EX_DIR="$PROFILE_DIR/examples"
LOG=""
[ -n "$RUN_DIR" ] && [ -d "$RUN_DIR" ] && LOG="$RUN_DIR/.receipt.log"
TAB="$(printf '\t')"
_log() { [ -n "$LOG" ] && printf '%s\n' "$1" >> "$LOG"; }

# --- tier -> example byte budget + max count -----------------------------------
TIER="standard"
CFG="$PROFILE_DIR/coapply.config.json"
if [ -f "$CFG" ]; then
  t="$(grep -o '"tier"[[:space:]]*:[[:space:]]*"[^"]*"' "$CFG" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
  case "$t" in lite|standard|full) TIER="$t" ;; esac
fi
case "$TIER" in
  lite)     EX_BUDGET=0;     EX_MAX=0 ;;
  standard) EX_BUDGET=12000; EX_MAX=2 ;;
  full)     EX_BUDGET=24000; EX_MAX=3 ;;
esac

# Mark that the pack ran for this role (so the receipt trusts the log over a glob).
_log "PACK${TAB}${ROLE}${TAB}done"

# Lite (or any zero-budget tier): playbooks only, no examples.
[ "$EX_MAX" -gt 0 ] 2>/dev/null || exit 0
[ -d "$EX_DIR" ] || exit 0

# --- gather candidates: bytes<TAB>file<TAB>header(first line) -------------------
cand="$(
  for f in "$EX_DIR/$ROLE"--*.md; do
    [ -f "$f" ] || continue
    # Skip filenames containing control chars (tab/newline): they would break the
    # tab-delimited candidate rows and the per-line read below, which would make
    # the receipt log claim a file was used while its content was never emitted.
    printf '%s' "$f" | grep -q '[[:cntrl:]]' && continue
    b="$(wc -c < "$f" | tr -d ' ')"
    h="$(sed -n '1p' "$f" | tr '\t' ' ')"
    printf '%s\t%s\t%s\n' "$b" "$f" "$h"
  done
)"
[ -n "$cand" ] || exit 0

# --- score by header/JD word overlap, then sort (score desc, bytes asc, name) --
scored="$(
  printf '%s\n' "$cand" | awk -v jd="$JD_FILE" '
    BEGIN {
      FS="\t"
      if (jd != "") {
        while ((getline line < jd) > 0) {
          n = split(tolower(line), w, /[^a-z0-9]+/)
          for (i = 1; i <= n; i++) if (length(w[i]) > 3) S[w[i]] = 1
        }
      }
    }
    {
      b=$1; f=$2; h=$3
      hasH = (h ~ /^[ \t]*<!--/) ? 1 : 0
      sc=0; n=split(tolower(h), w, /[^a-z0-9]+/)
      for (i=1;i<=n;i++) if (length(w[i])>3 && (w[i] in S)) sc++
      printf "%d\t%d\t%s\t%d\n", sc, b, f, hasH
    }
  ' | sort -t"$TAB" -k1,1nr -k2,2n -k3,3
)"

# --- greedy pick under budget + count cap; log every decision ------------------
picklist="$(mktemp 2>/dev/null || echo /tmp/coapply-pick.$$)"; : > "$picklist"
count=0; total=0; rank=0
printf '%s\n' "$scored" | while IFS="$TAB" read -r sc b f hasH; do
  [ -n "$f" ] || continue
  base="$(basename "$f")"
  [ "$hasH" = "1" ] || _log "WARN${TAB}example${TAB}${base}${TAB}no-header (filename still used)"
  if [ "$count" -lt "$EX_MAX" ] && [ $((total + b)) -le "$EX_BUDGET" ]; then
    rank=$((rank + 1)); count=$((count + 1)); total=$((total + b))
    printf '%s\n' "$f" >> "$picklist"
    _log "LOADED${TAB}example${TAB}${base}${TAB}${b}${TAB}rank=${rank} score=${sc}"
  else
    if [ "$count" -ge "$EX_MAX" ]; then reason="count-cap (tier max ${EX_MAX})"; else reason="over-budget"; fi
    _log "DROPPED${TAB}example${TAB}${base}${TAB}${b}${TAB}${reason}"
  fi
done

# --- emit the pack (voice reference only) ---------------------------------------
if [ -s "$picklist" ]; then
  printf '===COAPPLY-EXAMPLES-BEGIN===\n'
  printf '# Your saved examples — VOICE REFERENCE ONLY.\n'
  printf '# Imitate cadence, structure, and tone. NEVER reuse a specific claim,\n'
  printf '# metric, employer, or phrasing from these as a fact about THIS\n'
  printf '# application — facts come from the profile and JD, never these examples.\n'
  ex=0
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    ex=$((ex + 1))
    printf '\n## Example %d\n' "$ex"
    cat "$f"
  done < "$picklist"
  printf '\n===COAPPLY-EXAMPLES-END===\n'
fi
rm -f "$picklist" 2>/dev/null
exit 0
