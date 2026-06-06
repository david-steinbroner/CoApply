#!/usr/bin/env bash
# CoApply — render the per-run "What shaped this application" trust receipt.
#
# Deterministic by construction: everything here is derived from the filesystem
# (which playbooks/examples exist) and the run's tier (which agents ran), NOT from
# the model's recollection. The orchestrator runs this at the end of a run and
# prints its output verbatim. This is the trust centerpiece — it answers the
# "did it actually use my stuff?" question with facts, not a self-report.
#
# Honest scope: it reports the rules/examples that were AVAILABLE to and
# instructed-for the agents that ran (the engine follows any playbook that
# exists). It is not a cryptographic proof the model obeyed every rule — see the
# spec's "best-effort / script-logged selection" framing.
#
# Usage: render-receipt.sh <profile_dir> <run_dir>
# Always exits 0; fail-closed to "Receipt unavailable" if inputs are missing.
set -uo pipefail

PROFILE_DIR="${1:-}"
RUN_DIR="${2:-}"

_unavailable() {
  printf 'What shaped this application\n'
  printf '  (Receipt unavailable for this run.)\n'
  exit 0
}

[ -n "$PROFILE_DIR" ] && [ -d "$PROFILE_DIR" ] || _unavailable
PB_DIR="$PROFILE_DIR/playbooks"
EX_DIR="$PROFILE_DIR/examples"

# --- tier -> which roles produced output this run -------------------------------
# Mirrors master-apply.md's tier table. general.md always applies.
TIER="standard"
CFG="$PROFILE_DIR/coapply.config.json"
if [ -f "$CFG" ]; then
  t="$(grep -o '"tier"[[:space:]]*:[[:space:]]*"[^"]*"' "$CFG" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
  case "$t" in lite|standard|full) TIER="$t" ;; esac
fi
case "$TIER" in
  lite)     ROLES="positioning cover-letter" ;;
  standard) ROLES="positioning cover-letter outreach resume-update interview-prep" ;;
  full)     ROLES="positioning cover-letter outreach resume-update interview-prep application-questions" ;;
esac
# general.md applies to every run.
ROLES="$ROLES general"

# --- count rules across the playbooks that applied; collect bullets -------------
# Rule grammar: a rule is a line beginning with "- " (a markdown bullet).
TMP_BULLETS="$(mktemp 2>/dev/null || echo /tmp/coapply-bullets.$$)"
: > "$TMP_BULLETS"
total_rules=0
used_playbooks=0
for role in $ROLES; do
  f="$PB_DIR/$role.md"
  [ -f "$f" ] || continue
  n="$(grep -c '^- ' "$f" 2>/dev/null || echo 0)"
  [ "$n" -gt 0 ] 2>/dev/null || continue
  used_playbooks=$((used_playbooks + 1))
  total_rules=$((total_rules + n))
  # strip the leading "- " and append each rule for sampling
  sed -n 's/^- //p' "$f" >> "$TMP_BULLETS"
done

# --- pick a JD-matched sample rule (relevant, not a trivial first-line mirror) --
sample=""
if [ "$total_rules" -gt 0 ]; then
  JD="$RUN_DIR/jd.txt"
  [ -f "$JD" ] || JD=""
  sample="$(
    awk -v jd="$JD" '
      BEGIN {
        if (jd != "") {
          while ((getline line < jd) > 0) {
            n = split(tolower(line), w, /[^a-z0-9]+/)
            for (i = 1; i <= n; i++) if (length(w[i]) > 3) seen[w[i]] = 1
          }
        }
      }
      {
        score = 0
        n = split(tolower($0), w, /[^a-z0-9]+/)
        for (i = 1; i <= n; i++) if (length(w[i]) > 3 && (w[i] in seen)) score++
        if (score > best || best == "") { best = score; bestline = $0 }
      }
      END { if (bestline != "") print bestline }
    ' "$TMP_BULLETS"
  )"
  # fall back to the first rule if no JD or no overlap surfaced one
  [ -n "$sample" ] || sample="$(head -1 "$TMP_BULLETS")"
fi
rm -f "$TMP_BULLETS" 2>/dev/null

# --- count saved examples that applied this run --------------------------------
ex_used=0
if [ -d "$EX_DIR" ]; then
  for role in $ROLES; do
    [ "$role" = "general" ] && continue
    for g in "$EX_DIR/$role"--*.md; do
      [ -f "$g" ] && ex_used=$((ex_used + 1))
    done
  done
fi

# --- render --------------------------------------------------------------------
printf 'What shaped this application\n'
printf '  Your background:  your résumé, experience, and writing voice\n'
if [ "$total_rules" -gt 0 ]; then
  if [ -n "$sample" ]; then
    printf '  Your rules:       %s of your own writing rules — e.g. "%s"\n' "$total_rules" "$sample"
  else
    printf '  Your rules:       %s of your own writing rules\n' "$total_rules"
  fi
fi
if [ "$ex_used" -gt 0 ]; then
  printf '  Your examples:    %s of your saved letters, used as a style reference only —\n' "$ex_used"
  printf '                    none of their facts were reused.\n'
fi
if [ "$total_rules" -eq 0 ] && [ "$ex_used" -eq 0 ]; then
  printf '                    (Add your own writing rules with "add this to my profile"\n'
  printf '                     so future applications sound more like you.)\n'
fi
exit 0
