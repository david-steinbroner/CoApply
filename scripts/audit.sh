#!/usr/bin/env bash
# CoApply release audit — run before every release (and in CI).
# Verifies the engine stays generic (no personal data, no field assumptions)
# and structurally intact. Embodies the "verify before ship" principle.
# Usage: bash scripts/audit.sh   (exit 0 = clean, exit 1 = problems found)

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
fail=0
note() { printf '  %s\n' "$1"; }
section() { printf '\n=== %s ===\n' "$1"; }

# Scan the shipping engine + templates + manifest + docs — NOT a user's real profile.
# Every path here is scanned by §1 (personal data), §2 (field assumptions) and §3 (absolute
# paths). Keep the matcher scripts listed: they carry the word lists that decide which jobs a
# user ever sees, which is exactly where a field assumption would do the most damage.
SCAN_PATHS=(skills profile profile.example .claude-plugin README.md PRINCIPLES.md SECURITY.md CLAUDE.md CHANGELOG.md scripts/discover-surface.py scripts/discover-triage.py scripts/discover-querygen.py scripts/check-letter.sh hub)

section "1. Personal-data leak scan"
# The engine must never carry a user's personal proof data: employers, internal
# project names, account IDs, home paths. Author attribution (LICENSE, plugin.json,
# README) is expected and is not what this looks for.
#
# The person-specific token list is deliberately NOT in this file. This script is
# public, and a hardcoded list of one person's employers and internal project names
# is itself the leak it exists to prevent - it publishes their work history and
# advertises that the engine was written around a single user. So: structural
# patterns, which name nobody, live here; personal tokens live in a gitignored local
# file that each maintainer keeps for their own profile.
#
# See scripts/audit-pii-local.example for the format.
PII_LOCAL="scripts/.audit-pii-local"
_pii_hits=""
_pii_scan() { # <ere> -> append matches
  [ -n "$1" ] || return 0
  local h; h=$(grep -rInE "$1" "${SCAN_PATHS[@]}" 2>/dev/null | grep -viE 'run-folder|scaffold')
  [ -n "$h" ] && _pii_hits="${_pii_hits}${h}
"
  return 0
}
# Structural: account/session-ID-shaped strings. Names nobody, so it can live here.
_pii_scan '[0-9a-f]{15,}'
if [ -f "$PII_LOCAL" ]; then
  _pii_pat=$(grep -vE '^[[:space:]]*(#|$)' "$PII_LOCAL" | paste -sd'|' -)
  _pii_scan "$_pii_pat"
  _pii_state="local token list applied"
else
  _pii_state="UNCHECKED — no $PII_LOCAL, so structural patterns only"
fi
if [ -n "${_pii_hits//[[:space:]]/}" ]; then
  printf '%s' "$_pii_hits"; note "FAIL: personal-data tokens found in the engine."; fail=1
elif [ "$_pii_state" = "local token list applied" ]; then
  note "clean — no personal-data tokens (structural + local token list)."
else
  note "clean (structural) — $_pii_state."
fi

section "2. Field-assumption scan (engine must be field-agnostic)"
# High-signal tells that the engine assumes the user is a PM / in tech.
# Case-INSENSITIVE on purpose: without -i, "Product Manager" in a template or example sails
# past a lowercase pattern, so a field assumption passes the audit on capitalization alone.
FIELD='Growth PM|Compliance PM|product manager|product-manager|pm-builder|pm-growth|fintech\b'
hits=$(grep -rInEi "$FIELD" "${SCAN_PATHS[@]}" 2>/dev/null)
if [ -n "$hits" ]; then echo "$hits"; note "FAIL: field/PM assumptions found — genericize them."; fail=1; else note "clean — no PM/field assumptions."; fi

section "3. Stray absolute paths / unresolved engine vars"
hits=$(grep -rInE '/Users/|/Projects/apply' "${SCAN_PATHS[@]}" 2>/dev/null)
if [ -n "$hits" ]; then echo "$hits"; note "FAIL: hardcoded absolute paths found."; fail=1; else note "clean — no hardcoded absolute paths."; fi

section "4. Structure & invariants"
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json profile/prompts/master-apply.md PRINCIPLES.md LICENSE; do
  [ -f "$f" ] || { note "FAIL: missing $f"; fail=1; }
done
for s in start resume list help setup tier add feedback discover hub; do
  [ -f "skills/$s/SKILL.md" ] || { note "FAIL: missing skills/$s/SKILL.md"; fail=1; }
done
[ -d commands ] && { note "FAIL: commands/ exists — entry points must be skills (\${CLAUDE_PLUGIN_ROOT} doesn't resolve in commands)."; fail=1; }
grep -q '"name": "coapply"' .claude-plugin/plugin.json || { note "FAIL: plugin name is not 'coapply'."; fail=1; }
# Count the employee-mode agents. The real invariant is cross-checked in §14: every
# agent file must have a tagged dispatch. A bare count here would just be a magic
# number to bump, so record it for §14 to compare against.
agents=$(ls profile/prompts/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$agents" -gt 0 ] 2>/dev/null || { note "FAIL: no agent instruction files found under profile/prompts/agents/."; fail=1; }
[ "$fail" = 0 ] && note "structure OK."

section "5. resolve-profile-dir.sh works without python3/jq (POSIX fallback)"
# A user may have neither python3 nor jq. The resolver must still read the
# profile dir from settings.json via the POSIX (grep/sed) fallback, and the
# flat ~/.coapply_profile_path file must take precedence. We shadow python3 and
# jq with `false` (present but yielding nothing) to force the POSIX branch.
_rp_t=$(mktemp -d); _rp_shim=$(mktemp -d)
ln -sf /usr/bin/false "$_rp_shim/python3" 2>/dev/null; ln -sf /usr/bin/false "$_rp_shim/jq" 2>/dev/null
mkdir -p "$_rp_t/.claude"
printf '%s\n' '{"pluginConfigs":{"coapply@coapply-marketplace":{"options":{"profile_dir":"/tmp/coapply-audit-x"}}}}' > "$_rp_t/.claude/settings.json"
_rp_out=$(HOME="$_rp_t" PATH="$_rp_shim:$PATH" bash scripts/resolve-profile-dir.sh 2>/dev/null)
if [ "$_rp_out" = "/tmp/coapply-audit-x" ]; then note "clean — POSIX settings.json fallback works (no python3/jq)."; else note "FAIL: POSIX fallback returned [$_rp_out], expected /tmp/coapply-audit-x."; fail=1; fi
printf '/tmp/coapply-audit-flat\n' > "$_rp_t/.coapply_profile_path"
_rp_out2=$(HOME="$_rp_t" PATH="$_rp_shim:$PATH" bash scripts/resolve-profile-dir.sh 2>/dev/null)
if [ "$_rp_out2" = "/tmp/coapply-audit-flat" ]; then note "clean — flat ~/.coapply_profile_path takes precedence."; else note "FAIL: flat-file precedence returned [$_rp_out2]."; fail=1; fi
# Scoping: a different plugin's profile_dir appearing BEFORE coapply must not be picked.
rm -f "$_rp_t/.coapply_profile_path"
printf '%s\n' '{"pluginConfigs":{"other@m":{"options":{"profile_dir":"/WRONG"}},"coapply@m":{"options":{"profile_dir":"/RIGHT"}}}}' > "$_rp_t/.claude/settings.json"
_rp_scope=$(HOME="$_rp_t" PATH="$_rp_shim:$PATH" bash scripts/resolve-profile-dir.sh 2>/dev/null)
if [ "$_rp_scope" = "/RIGHT" ]; then note "clean — POSIX fallback is scoped to CoApply's config."; else note "FAIL: scoping picked [$_rp_scope], expected /RIGHT."; fail=1; fi
# HOME unset must still exit 0 (documented contract).
( env -u HOME bash scripts/resolve-profile-dir.sh >/dev/null 2>&1 ); if [ "$?" = "0" ]; then note "clean — exits 0 even with HOME unset."; else note "FAIL: nonzero exit with HOME unset."; fail=1; fi
rm -rf "$_rp_t" "$_rp_shim"

section "6. render-receipt.sh — deterministic + fail-closed"
# Receipt must fail closed (never imply nothing was used) and must report a
# playbook's rules + a sample when one is present.
_rr_p=$(mktemp -d); _rr_r=$(mktemp -d)
_rr_bad=$(bash scripts/render-receipt.sh "/no/such/dir/xyz" "$_rr_r" 2>/dev/null)
case "$_rr_bad" in *"Receipt unavailable"*) note "clean — fails closed on a bad profile dir." ;; *) note "FAIL: receipt did not fail closed: [$_rr_bad]"; fail=1 ;; esac
mkdir -p "$_rr_p/playbooks"; printf '{"tier":"lite"}\n' > "$_rr_p/coapply.config.json"
printf -- '- Lead with the work, not the label.\n- Keep concrete proof concrete.\n' > "$_rr_p/playbooks/cover-letter.md"
printf 'role wants concrete proof and measurable results\n' > "$_rr_r/jd.txt"
_rr_ok=$(bash scripts/render-receipt.sh "$_rr_p" "$_rr_r" 2>/dev/null)
case "$_rr_ok" in *"2 of your own writing rules"*) note "clean — counts rules + renders a sample." ;; *) note "FAIL: receipt did not report rules: [$_rr_ok]"; fail=1 ;; esac
# Fenced "- " lines must NOT be counted as rules.
printf '# Rules\n- Real rule one.\n- Real rule two.\n\n```\n- not a rule\n- also not\n```\n' > "$_rr_p/playbooks/cover-letter.md"
_rr_fence=$(bash scripts/render-receipt.sh "$_rr_p" "$_rr_r" 2>/dev/null)
case "$_rr_fence" in *"2 of your own writing rules"*) note "clean — fenced '- ' lines are not counted as rules." ;; *) note "FAIL: fenced lines miscounted: [$_rr_fence]"; fail=1 ;; esac
# The receipt must credit only artifacts that actually completed. Crediting a
# skipped/failed agent's playbook is the receipt reporting a PLAN as a FACT — the
# one failure this file cannot have. Regression guard for 0.15.1.
printf -- '- Letter rule one.\n- Letter rule two.\n' > "$_rr_p/playbooks/cover-letter.md"
printf -- '- Position rule one.\n- Position rule two.\n- Position rule three.\n' > "$_rr_p/playbooks/positioning.md"
printf '{"tier":"full","artifacts":[{"name":"positioning","status":"done","path":"a"},{"name":"cover-letter","status":"skipped","path":"b"}]}\n' > "$_rr_r/_run.json"
_rr_skip=$(bash scripts/render-receipt.sh "$_rr_p" "$_rr_r" 2>/dev/null)
case "$_rr_skip" in
  *"3 of your own writing rules"*) note "clean — a skipped artifact's playbook is not credited (3, not 5)." ;;
  *"5 of your own writing rules"*) note "FAIL: receipt credited a SKIPPED artifact's playbook — it is reporting the tier plan, not the run record."; fail=1 ;;
  *) note "FAIL: unexpected receipt with a skipped artifact: [$_rr_skip]"; fail=1 ;;
esac
# Same matcher must survive pretty-printed JSON. Splitting on `{` without stripping
# newlines first matches nothing and silently falls back to the tier table — which
# looks like a pass on the compact fixture above and fails on every real run file.
printf '{\n  "tier": "full",\n  "artifacts": [\n    {\n      "name": "positioning",\n      "status": "done"\n    },\n    {\n      "name": "cover-letter",\n      "status": "skipped"\n    }\n  ]\n}\n' > "$_rr_r/_run.json"
_rr_pretty=$(bash scripts/render-receipt.sh "$_rr_p" "$_rr_r" 2>/dev/null)
case "$_rr_pretty" in
  *"3 of your own writing rules"*) note "clean — artifact matcher handles pretty-printed _run.json too." ;;
  *) note "FAIL: pretty-printed _run.json was not parsed (fell back to the tier table): [$_rr_pretty]"; fail=1 ;;
esac
rm -rf "$_rr_p" "$_rr_r"

section "7. context-pack.sh — JD-ranked, byte-capped, logs its selection"
# Standard tier caps examples at 2; the most JD-relevant must rank first and the
# overflow must be logged DROPPED (so the receipt can show "set aside").
_cp_p=$(mktemp -d); _cp_r=$(mktemp -d); mkdir -p "$_cp_p/examples"
printf '{"tier":"standard"}\n' > "$_cp_p/coapply.config.json"
printf 'fintech growth activation retention\n' > "$_cp_r/jd.txt"
printf '<!-- tags: fintech, growth, activation, retention -->\nx\n' > "$_cp_p/examples/cover-letter--fintech--a.md"
printf '<!-- tags: retention -->\nx\n' > "$_cp_p/examples/cover-letter--mid--b.md"
printf '<!-- tags: gaming -->\nx\n' > "$_cp_p/examples/cover-letter--gaming--c.md"
bash scripts/context-pack.sh "$_cp_p" "cover-letter" "$_cp_r/jd.txt" "$_cp_r" >/dev/null 2>&1
_cp_loaded=$(awk -F'\t' '$1=="LOADED" && $2=="example"{c++} END{print c+0}' "$_cp_r/.receipt.log" 2>/dev/null)
_cp_drop=$(awk -F'\t' '$1=="DROPPED" && $2=="example"{c++} END{print c+0}' "$_cp_r/.receipt.log" 2>/dev/null)
_cp_top=$(awk -F'\t' '$1=="LOADED" && $5 ~ /rank=1/{print $3}' "$_cp_r/.receipt.log" 2>/dev/null)
if [ "$_cp_loaded" = "2" ] && [ "$_cp_drop" = "1" ]; then note "clean — caps at 2, logs 1 dropped."; else note "FAIL: expected 2 loaded / 1 dropped, got $_cp_loaded / $_cp_drop."; fail=1; fi
if [ "$_cp_top" = "cover-letter--fintech--a.md" ]; then note "clean — most JD-relevant example ranks first."; else note "FAIL: rank=1 was [$_cp_top], expected the fintech example."; fail=1; fi
rm -rf "$_cp_p" "$_cp_r"

section "8. scan-pii.sh — flags true secrets, allows the middle tier, leaks no digits"
_pi_f=$(mktemp)
printf 'My SSN is 123-45-6789\n' > "$_pi_f"
_pi_out=$(bash scripts/scan-pii.sh "$_pi_f"); _pi_rc=$?
if [ "$_pi_rc" = "3" ] && printf '%s' "$_pi_out" | grep -q 'SSN' && ! printf '%s' "$_pi_out" | grep -q '6789'; then
  note "clean — flags SSN, exit 3, redacts the digits."
else note "FAIL: SSN scan rc=$_pi_rc out=[$_pi_out]"; fail=1; fi
printf 'Targeting $140k, based in Austin, authorized to work in the US, call 512-555-0199\n' > "$_pi_f"
bash scripts/scan-pii.sh "$_pi_f" >/dev/null 2>&1
if [ "$?" = "0" ]; then note "clean — middle-tier facts (salary/city/work-auth/phone) not flagged."; else note "FAIL: middle-tier facts were flagged as secrets."; fail=1; fi
# Modern token shapes must be flagged.
printf 'key ghp_abcdefghij0123456789ABCDEFGHIJ012345 and sk_live_abcdefghij0123456789\n' > "$_pi_f"
bash scripts/scan-pii.sh "$_pi_f" >/dev/null 2>&1
if [ "$?" = "3" ]; then note "clean — modern API token shapes (ghp_/sk_live_) flagged."; else note "FAIL: modern token shapes not flagged."; fail=1; fi
# PEM private key flagged.
printf -- '-----BEGIN RSA PRIVATE KEY-----\n' > "$_pi_f"
bash scripts/scan-pii.sh "$_pi_f" >/dev/null 2>&1
if [ "$?" = "3" ]; then note "clean — PEM private key flagged."; else note "FAIL: PEM private key not flagged."; fail=1; fi
# False positives: a run of consecutive years must NOT look like a card.
printf 'I worked across 2019 2020 2021 2022 on growth and passwordless login\n' > "$_pi_f"
bash scripts/scan-pii.sh "$_pi_f" >/dev/null 2>&1
if [ "$?" = "0" ]; then note "clean — year runs / 'passwordless' not false-flagged."; else note "FAIL: false positive on years/passwordless."; fail=1; fi
rm -f "$_pi_f"

section "9. session-nudge.sh — announces the real version on change, silent otherwise"
_sn_h=$(mktemp -d); _sn_p=$(mktemp -d); printf 'x\n' > "$_sn_p/identity.md"
_pjv=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' .claude-plugin/plugin.json | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')
printf '0.0.0-old\n' > "$_sn_h/.coapply_last_version"
_sn_out=$(HOME="$_sn_h" CLAUDE_PLUGIN_ROOT="$(pwd)" CLAUDE_PLUGIN_OPTION_PROFILE_DIR="$_sn_p" bash scripts/session-nudge.sh)
if printf '%s' "$_sn_out" | grep -q "updated to v$_pjv"; then note "clean — announces the real version after a change."; else note "FAIL: version-change not announced: [$_sn_out]"; fail=1; fi
_sn_out2=$(HOME="$_sn_h" CLAUDE_PLUGIN_ROOT="$(pwd)" CLAUDE_PLUGIN_OPTION_PROFILE_DIR="$_sn_p" bash scripts/session-nudge.sh)
if [ -z "$_sn_out2" ]; then note "clean — silent when the version is unchanged."; else note "FAIL: not silent on unchanged version: [$_sn_out2]"; fail=1; fi
rm -rf "$_sn_h" "$_sn_p"

section "10. feedback-context.sh — context block, URL encoding, run state"
# The context block must report the real version + tier; the URL builder must
# percent-encode title/labels/body; the run block must name the failed step.
_fb_p=$(mktemp -d); printf '{"tier":"lite"}\n' > "$_fb_p/coapply.config.json"
_fb_ctx=$(bash scripts/feedback-context.sh context "$_fb_p")
if printf '%s' "$_fb_ctx" | grep -q 'CoApply version:' && printf '%s' "$_fb_ctx" | grep -q 'Tier: lite'; then
  note "clean — context block reports version + tier."
else note "FAIL: context block: [$_fb_ctx]"; fail=1; fi
# URL: spaces/colon in title encoded, label literal, body specials encoded.
_fb_bf=$(mktemp); printf 'line one\nwith #hash & ampersand' > "$_fb_bf"
_fb_url=$(bash scripts/feedback-context.sh url "Bug: it broke" "bug" "$_fb_bf")
case "$_fb_url" in
  *"/issues/new?title=Bug%3A%20it%20broke&labels=bug&body="*) note "clean — title/labels percent-encoded." ;;
  *) note "FAIL: url title/labels: [$_fb_url]"; fail=1 ;;
esac
if printf '%s' "$_fb_url" | grep -q '%0A' && printf '%s' "$_fb_url" | grep -q '%23' && printf '%s' "$_fb_url" | grep -q '%26'; then
  note "clean — body newline/#/& encoded (%0A/%23/%26)."
else note "FAIL: body encoding: [$_fb_url]"; fail=1; fi
# Run block: names the FAILED artifact, not the first one (compact + pretty JSON).
mkdir -p "$_fb_p/runs/r1" "$_fb_p/runs/r2"
printf '{ "phase": "content", "artifacts": [ { "name": "role-analysis", "status": "done", "path": "x" }, { "name": "cover-letter", "status": "failed", "path": "y" } ] }\n' > "$_fb_p/runs/r1/_run.json"
printf '{\n "phase": "strategy",\n "artifacts": [\n  { "name": "fit-score",\n    "status": "failed" }\n ]\n}\n' > "$_fb_p/runs/r2/_run.json"
_fb_r1=$(bash scripts/feedback-context.sh context "$_fb_p" "r1")
_fb_r2=$(bash scripts/feedback-context.sh context "$_fb_p" "r2")
if printf '%s' "$_fb_r1" | grep -q 'failed step: cover-letter' && printf '%s' "$_fb_r2" | grep -q 'failed step: fit-score'; then
  note "clean — run block names the failed step (compact + pretty JSON)."
else note "FAIL: run block: r1=[$_fb_r1] r2=[$_fb_r2]"; fail=1; fi
# A bad/unknown run slug must omit the run block, not error.
_fb_none=$(bash scripts/feedback-context.sh context "$_fb_p" "nonexistent")
if ! printf '%s' "$_fb_none" | grep -q 'Run:'; then note "clean — unknown run slug omits the run block."; else note "FAIL: phantom run block: [$_fb_none]"; fail=1; fi
rm -rf "$_fb_p" "$_fb_bf"

section "11. feedback skill — no-fabrication discipline intact"
# The feedback skill turns a user's words into a GitHub issue. It must capture what the
# user said, never compose content they didn't (a 2026-06-08 regression filled empty
# 'Why it matters'/'How I imagine it working' sections with invented rationale). Guard
# both the rule's presence and the absence of the empty-section scaffolding that invited it.
_fbk=skills/feedback/SKILL.md
if grep -qi "capture, don't compose" "$_fbk"; then note "clean — capture-don't-compose rule present."; else note "FAIL: feedback skill lost its no-fabrication rule."; fail=1; fi
if grep -qi "fill this in" "$_fbk"; then note "FAIL: feedback skill reintroduced 'fill this in' empty-section scaffolding (invites fabrication)."; fail=1; else note "clean — no empty-section fill-in scaffolding."; fi
# Vague input must trigger a clarifying question, not an auto-generated issue.
if grep -qi "clarifying question" "$_fbk"; then note "clean — clarify-when-vague step present."; else note "FAIL: feedback skill lost its clarify-when-vague step (would auto-file vague input)."; fail=1; fi

section "12. resume-import (onboarding) — field-agnostic prompt + helper discipline"
_imp=profile/prompts/onboarding/import-resume.md
if [ -f "$_imp" ]; then note "clean — import prompt present."; else note "FAIL: import prompt missing."; fail=1; fi
# §16.J: the import prompt is the highest field-leak risk in the engine — must pass the field grep.
if grep -inE 'product manager|product-manager|pm-builder|pm-growth|fintech|growth pm|compliance pm' "$_imp" >/dev/null 2>&1; then
  note "FAIL: import prompt contains field/PM assumptions — genericize."; fail=1
else note "clean — import prompt is field-agnostic."; fi
# §16.A/B: verbatim-extraction rule + [GAP:] markers must survive.
grep -qi 'verbatim' "$_imp" && note "clean — verbatim-extraction rule present." || { note "FAIL: import prompt lost its verbatim rule."; fail=1; }
grep -q '\[GAP:' "$_imp" && note "clean — [GAP:] marker convention present." || { note "FAIL: import prompt lost the [GAP:] markers."; fail=1; }
# §16.M: the no-resume Q&A path keeps "anyone can use it" true for career-changers/new grads.
grep -qi 'Step 1b\|no resume' "$_imp" && note "clean — no-resume Q&A path present." || { note "FAIL: import prompt lost the no-resume Q&A path."; fail=1; }
# Helper: fail-closed sanity gate, bloat tiers, neutralizing atomic write.
_ri=$(mktemp)
printf 'hi there\n' > "$_ri"
case "$(bash scripts/resume-import.sh sanity "$_ri")" in EMPTY*) note "clean — sanity flags near-empty input." ;; *) note "FAIL: sanity should flag near-empty as EMPTY."; fail=1 ;; esac
# A SHORT but real resume (≈30 words, has keywords) must pass — new-grad/career-changer case.
printf 'Jane Doe. Experience: Teacher at Lincoln High 2019-2023, taught biology. Education: BS Biology 2019. Skills: classroom management, lab safety, curriculum.\n' > "$_ri"
case "$(bash scripts/resume-import.sh sanity "$_ri")" in OK*) note "clean — a short real resume passes (not bounced as too-short)." ;; *) note "FAIL: short real resume should pass."; fail=1 ;; esac
# Real length, NO resume keywords (wrong paste / scrambled into non-resume text) -> NO_KEYWORDS.
printf 'the quick brown fox jumped over %.0s' $(seq 1 10) > "$_ri"
case "$(bash scripts/resume-import.sh sanity "$_ri")" in NO_KEYWORDS*) note "clean — non-resume text flagged NO_KEYWORDS." ;; *) note "FAIL: non-resume text should be NO_KEYWORDS."; fail=1 ;; esac
printf 'w %.0s' $(seq 1 1100) > "$_ri"
case "$(bash scripts/resume-import.sh wordcheck "$_ri")" in *OVER) note "clean — wordcheck flags bloat (>1000)." ;; *) note "FAIL: wordcheck should flag >1000 as OVER."; fail=1 ;; esac
_rio="$(mktemp -d)/out.md"
printf 'Built List<String>; <EMAIL> redacted\n' | bash scripts/resume-import.sh write "$_rio" >/dev/null 2>&1
if grep -qE '<[A-Z][^>]*>' "$_rio"; then note "FAIL: write left <Xxx> tokens (would trip start preflight)."; fail=1; else note "clean — write neutralizes placeholder-shaped tokens."; fi
# write-raw (identity.md) must NOT neutralize — a stray <placeholder> stays visible so the
# preflight catches it instead of masking an unfilled field into (placeholder).
_rir="$(mktemp -d)/identity.md"
printf '**Location:** <City, ST>\n' | bash scripts/resume-import.sh write-raw "$_rir" >/dev/null 2>&1
if grep -qE '<[A-Z][^>]*>' "$_rir"; then note "clean — write-raw preserves <placeholder> (preflight can catch it)."; else note "FAIL: write-raw neutralized a placeholder (would mask an unfilled identity field)."; fail=1; fi
rm -f "$_ri"; rm -rf "$(dirname "$_rio")" "$(dirname "$_rir")"

section "13. profile-status.sh — bare resolver + readiness flags (allowlist-friendly Step 0)"
# Skills call this ONE script bare in Step 0 instead of wrapping the resolver in
# PROFILE_DIR="$(...)" — a substitution-in-assignment that can't be allowlisted and
# prompted every command. It must resolve the dir AND report readiness in one call.
# Skills must NOT reintroduce the un-allowlistable wrapper around the resolver.
_ps_w=$(grep -rn '"\$("\${CLAUDE_PLUGIN_ROOT}/scripts/resolve-profile-dir.sh")"' skills/ 2>/dev/null)
if [ -n "$_ps_w" ]; then echo "$_ps_w"; note "FAIL: a skill wraps the resolver in VAR=\"\$(...)\" — run it bare so it can be allowlisted."; fail=1; else note "clean — no un-allowlistable resolver wrapper in skills."; fi
_ps_t=$(mktemp -d); _ps_p="$_ps_t/prof"; mkdir -p "$_ps_p/resumes"
printf 'Name: Jane Doe\n' > "$_ps_p/identity.md"; printf 'Experience with 40%% lift.\n' > "$_ps_p/skills-experience.md"
printf '# r\nx\n' > "$_ps_p/resumes/main.md"; printf '%s\n' "$_ps_p" > "$_ps_t/.coapply_profile_path"
_ps_ok=$(HOME="$_ps_t" bash scripts/profile-status.sh 2>/dev/null)
if printf '%s' "$_ps_ok" | grep -q "PROFILE_DIR=$_ps_p" \
   && printf '%s' "$_ps_ok" | grep -qx 'WRITABLE=yes' \
   && printf '%s' "$_ps_ok" | grep -qx 'IDENTITY=yes' \
   && printf '%s' "$_ps_ok" | grep -qx 'RESUME=yes' \
   && printf '%s' "$_ps_ok" | grep -qx 'PLACEHOLDERS=no'; then
  note "clean — reports PROFILE_DIR + ready flags for a filled-in profile."
else echo "$_ps_ok"; note "FAIL: ready-profile flags wrong."; fail=1; fi
# Placeholders + missing resume must show.
printf 'Name: <Your Name>\n' > "$_ps_p/identity.md"; rm -f "$_ps_p/resumes/main.md"
_ps_np=$(HOME="$_ps_t" bash scripts/profile-status.sh 2>/dev/null)
if printf '%s' "$_ps_np" | grep -qx 'PLACEHOLDERS=yes' && printf '%s' "$_ps_np" | grep -qx 'RESUME=no'; then
  note "clean — flags placeholders + missing resume."
else echo "$_ps_np"; note "FAIL: placeholder/resume flags wrong."; fail=1; fi
# Not configured (no flat file, no settings): empty PROFILE_DIR, never errors.
_ps_t2=$(mktemp -d)
_ps_none=$(HOME="$_ps_t2" bash scripts/profile-status.sh 2>/dev/null); _ps_rc=$?
if [ "$_ps_rc" = 0 ] && printf '%s' "$_ps_none" | grep -qx 'PROFILE_DIR='; then note "clean — empty PROFILE_DIR when unconfigured, exits 0."; else note "FAIL: unconfigured case rc=$_ps_rc out=[$_ps_none]"; fail=1; fi
rm -rf "$_ps_t" "$_ps_t2"

section "14. Per-agent model tiering — Model map present + every dispatch tagged"
# Tier picks the model per agent via a Model map in master-apply.md; phase-dispatch
# files must tag EVERY agent dispatch with a class so the orchestrator knows which
# model to pass. A new agent added without a class tag = silent inherit (a bug).
_mm=profile/prompts/master-apply.md
if grep -qi 'Model map' "$_mm" && grep -q '\*\*mechanical\*\*' "$_mm" && grep -q '\*\*reasoning\*\*' "$_mm" && grep -q '\*\*voice\*\*' "$_mm"; then
  note "clean — Model map with all three classes present in master-apply.md."
else note "FAIL: master-apply.md is missing the Model map or a class row."; fail=1; fi
# The matrix must name the three model aliases.
if grep -q 'haiku' "$_mm" && grep -q 'sonnet' "$_mm" && grep -q 'opus' "$_mm"; then
  note "clean — Model map names haiku/sonnet/opus."
else note "FAIL: Model map missing a model alias (haiku/sonnet/opus)."; fail=1; fi
# Every agent dispatch line in the phase files must carry a [class] tag.
_untagged=$(grep -nE 'instructed by `\$\{CLAUDE_PLUGIN_ROOT\}/profile/prompts/agents/[a-z-]+\.md' \
  profile/prompts/phases/phase-research.md profile/prompts/phases/phase-content.md 2>/dev/null \
  | grep -vE '\[(mechanical|reasoning|voice)\]')
if [ -z "$_untagged" ]; then note "clean — every agent dispatch line carries a [class] tag."; else echo "$_untagged"; note "FAIL: an agent dispatch line has no [mechanical|reasoning|voice] class tag — it would silently inherit the session model."; fail=1; fi
# Every agent file must have a tagged dispatch. Cross-checking the two counts beats
# a hardcoded number: adding a properly-wired agent passes without editing the audit,
# while adding an agent file nobody dispatches (or deleting one still dispatched)
# fails. That drift is exactly what a magic number lets through — it was WARN-only,
# so it never failed a build regardless.
_tagged=$(grep -hE 'instructed by `\$\{CLAUDE_PLUGIN_ROOT\}/profile/prompts/agents/[a-z-]+\.md' \
  profile/prompts/phases/phase-research.md profile/prompts/phases/phase-content.md 2>/dev/null \
  | grep -cE '\[(mechanical|reasoning|voice)\]')
if [ "${_tagged:-0}" = "${agents:-0}" ]; then
  note "clean — ${agents} agent files, ${_tagged} tagged dispatches (counts agree)."
else
  _disp_names=$(grep -hoE 'profile/prompts/agents/[a-z-]+\.md' \
    profile/prompts/phases/phase-research.md profile/prompts/phases/phase-content.md 2>/dev/null \
    | sed 's|.*/||' | sort -u)
  _file_names=$(ls profile/prompts/agents/*.md 2>/dev/null | sed 's|.*/||' | sort -u)
  note "FAIL: ${agents} agent file(s) but ${_tagged} tagged dispatch(es) — an agent is unwired or a dispatch is untagged."
  printf '%s\n' "$(comm -23 <(printf '%s\n' "$_file_names") <(printf '%s\n' "$_disp_names") | sed 's/^/        file with no dispatch: /')"
  printf '%s\n' "$(comm -13 <(printf '%s\n' "$_file_names") <(printf '%s\n' "$_disp_names") | sed 's/^/        dispatch with no file: /')"
  fail=1
fi

section "15. Discovery — 3-point network boundary + vendor/company + fingerprint guards"
# The whole discovery path must stay on the durable side of the line: public ATS JSON
# over plain HTTP, no browser/auth/aggregator, no LLM that could fetch. The boundary is
# a property of the WHOLE path, asserted at every place a network call can originate
# (spec docs/features/discovery/spec.md §4/§7). v1's mistake was locating it in one script.
_DF=scripts/discover-fetch.py
_DR=scripts/discover-resolve.sh
_DT=scripts/discover-triage.py
_DS=skills/discover/SKILL.md
_DW=profile.example/watchlist.md
for f in "$_DF" "$_DR" "$_DT" "$_DS" "$_DW"; do
  [ -f "$f" ] || { note "FAIL: missing discovery file $f"; fail=1; }
done

# --- Boundary point 1: discover-fetch.py host allowlist (closed) ---
if grep -q 'ALLOWED_HOSTS' "$_DF" \
   && grep -q 'boards-api.greenhouse.io' "$_DF" \
   && grep -q 'api.lever.co' "$_DF" \
   && grep -q 'api.ashbyhq.com' "$_DF" \
   && grep -q 'not in the discovery allowlist' "$_DF"; then
  note "clean — fetch host allowlist present + closed (boundary point 1)."
else note "FAIL: discover-fetch.py lost its closed host allowlist (boundary point 1)."; fail=1; fi

# --- Boundary point 2: discover-resolve.sh only ever EMITS a known ATS ---
# Behavioral + offline: a known-ATS *input* URL short-circuits without a network call
# (classify() gates emit), so these three cases never touch the network.
_dr1=$(bash "$_DR" 'https://boards.greenhouse.io/acme' 2>/dev/null)
if printf '%s' "$_dr1" | grep -qx 'ats=greenhouse' && printf '%s' "$_dr1" | grep -qx 'token=acme'; then
  note "clean — resolve emits (ats,token) for a known ATS board URL (boundary point 2)."
else note "FAIL: resolve didn't emit for a greenhouse board URL: [$_dr1]"; fail=1; fi
# A bare name (no dot/slash) must be refused, not guessed — guessing a company's domain
# is the forbidden aggregator-search path. Exit 1, no network.
bash "$_DR" 'acme' >/dev/null 2>&1
[ "$?" = 1 ] && note "clean — resolve refuses a bare name (no aggregator-search guess)." || { note "FAIL: resolve should refuse a bare name with exit 1."; fail=1; }
# Workday is recognized but deferred (spec §8) — flagged (exit 3), never emitted as fetchable.
bash "$_DR" 'https://acme.wd1.myworkdayjobs.com/careers' >/dev/null 2>&1
[ "$?" = 3 ] && note "clean — resolve flags Workday as deferred (exit 3), not emitted." || { note "FAIL: resolve should exit 3 on a Workday URL."; fail=1; }

# --- Boundary point 3: the triage step has NO network capability ---
# The single biggest stay-in-bounds risk was an LLM triage that could WebFetch a posting URL
# and bypass the fetch allowlist. The default is a pure Python ranker, so this is free —
# assert it: (a) the ranker imports no network module, (b) the ranker references no web tool
# at all, and (c) in the orchestrator skill, WebFetch of a posting stays prohibited.
# NOTE (discovery-auto, spec §4): `WebSearch` is now the SANCTIONED auto-mode Path A — it is
# scoped by allowed_domains to public ATS board hosts and used only to find first-party
# (ats,token) tokens (never as job data). So WebSearch is allowed *in the skill*, but the
# offline ranker still names neither tool, and WebFetch of a posting URL stays forbidden.
if grep -nE '^[[:space:]]*(import|from)[[:space:]]+(urllib|http|requests|socket|aiohttp|httplib)' "$_DT" >/dev/null 2>&1; then
  grep -nE '^[[:space:]]*(import|from)[[:space:]]+(urllib|http|requests|socket|aiohttp|httplib)' "$_DT"
  note "FAIL: discover-triage.py imports a network module — the ranker must be offline (boundary point 3)."; fail=1
else note "clean — discover-triage.py imports no network module (boundary point 3)."; fi
# (b) the offline ranker names a web tool ONLY inside an explicit prohibition (never as a
# capability) — neither WebFetch nor WebSearch is available to it.
_tri_web=$(grep -inE 'WebFetch|WebSearch' "$_DT" 2>/dev/null \
  | grep -ivE "never|no network|cannot|can'?t|not |without|prohibit|no web|no fetch|no .*tool")
if [ -n "$_tri_web" ]; then echo "$_tri_web"; note "FAIL: discover-triage.py references a web tool outside a prohibition — the ranker must be offline (boundary point 3)."; fail=1
else note "clean — discover-triage.py names a web tool only as a prohibition; the ranker stays offline (boundary point 3)."; fi
# (c) in the orchestrator skill, every WebFetch mention must sit inside an explicit
# prohibition (a posting URL is never WebFetched). WebSearch is the allowed auto-mode Path A.
_skill_webfetch=$(grep -inE 'WebFetch' "$_DS" 2>/dev/null \
  | grep -ivE "never|no network|cannot|can'?t|not |without|prohibit|no web|no fetch|no .*tool")
if [ -n "$_skill_webfetch" ]; then echo "$_skill_webfetch"; note "FAIL: WebFetch appears in the discovery skill outside a prohibition (boundary point 3)."; fail=1
else note "clean — WebFetch only ever appears as an explicit prohibition in the discovery skill; WebSearch is the sanctioned auto-mode Path A (boundary point 3)."; fi

# --- Vendor infra vs. target-company guard (spec §7) ---
# ATS *infrastructure* names (greenhouse/lever/ashby) are legitimately in the engine — they
# are vendors, not the user's employers — so the field/PII scans above must NOT flag them.
# But a real *company* name must never appear as an engine example.
if grep -q 'greenhouse' "$_DF" && grep -q 'lever' "$_DF" && grep -q 'ashby' "$_DF"; then
  note "clean — ATS vendor infra hosts (greenhouse/lever/ashby) allowed in the engine."
else note "FAIL: discovery lost an ATS vendor host — adapters can't resolve."; fail=1; fi
# The watchlist TEMPLATE ships zero companies: every data row's Company cell is a <…>
# placeholder. A non-placeholder Company cell = a real employer leaked into the engine.
_badrows=$(awk -F'|' '
  /^\|/ {
    c=$2; gsub(/^[[:space:]]+|[[:space:]]+$/,"",c);
    if (c=="" || c=="Company") next;       # header / spacer
    if (c ~ /^[-: ]+$/) next;              # |---|---| separator
    if (c ~ /^<.*>$/) next;                # <placeholder> — fine
    print c;                               # a real-looking company name
  }' "$_DW")
if [ -z "$_badrows" ]; then note "clean — watchlist template uses only placeholder company rows (ships no employer)."; else echo "$_badrows"; note "FAIL: watchlist template has a non-placeholder company name — the engine must ship none."; fail=1; fi

# --- Fingerprint scheme guard: sha1(ats|token|id), NOT company|id (spec §3.3) ---
# The display name is user-typed; fingerprinting on it means relabeling 'Acme'→'Acme Inc'
# resurfaces every posting. token+id is stable. Guard against a regression to company|id.
if grep -qF '{ats}|{token}|{ident}' "$_DF"; then
  note "clean — fingerprint is sha1(ats|token|id)."
else note "FAIL: discover-fetch.py fingerprint is not sha1(ats|token|id) (spec §3.3)."; fail=1; fi
if grep -qF '{company}|' "$_DF"; then
  grep -nF '{company}|' "$_DF"
  note "FAIL: discover-fetch.py builds a company|id fingerprint — relabeling a row would resurface every posting (spec §3.3)."; fail=1
else note "clean — no company|id fingerprint regression."; fi

# --- Discovery-AUTO front-end guards (spec docs/features/discovery-auto/spec.md §6) ---
# The two new front-end scripts (querygen, extract) must hold the same offline + boundary +
# field-agnostic properties as the rest of discovery. These are the step-4 assertions.
_DQ=scripts/discover-querygen.py
_DE=scripts/discover-extract.py
for f in "$_DQ" "$_DE"; do
  [ -f "$f" ] || { note "FAIL: missing discovery-auto file $f"; fail=1; }
done
# (a) querygen + extract are OFFLINE — neither imports a network module (same test as triage).
_auto_net=$(grep -nE '^[[:space:]]*(import|from)[[:space:]]+(urllib|http|requests|socket|aiohttp|httplib)' "$_DQ" "$_DE" 2>/dev/null)
if [ -n "$_auto_net" ]; then echo "$_auto_net"; note "FAIL: querygen/extract imports a network module — the front-end must be offline (spec §6)."; fail=1
else note "clean — discover-querygen.py + discover-extract.py import no network module (offline front-end, spec §6)."; fi
# (b) extract emits ONLY known-ATS tokens — behavioral negative tests (the boundary guard,
# spec §4): a non-ATS URL yields zero tokens; a denylisted token is dropped; a known ATS
# board URL IS emitted (positive control, so the test can actually fail).
_ex_nonats=$(printf '%s\n' 'https://www.linkedin.com/jobs/view/123' | python3 "$_DE" 2>/dev/null)
_ex_deny=$(printf '%s\n' 'https://jobs.lever.co/jobgether/x' | python3 "$_DE" 2>/dev/null)
_ex_ok=$(printf '%s\n' 'https://boards.greenhouse.io/acme' | python3 "$_DE" 2>/dev/null)
if printf '%s' "$_ex_nonats" | grep -q '"unique_tokens": 0' \
   && printf '%s' "$_ex_deny"   | grep -q '"unique_tokens": 0' \
   && printf '%s' "$_ex_ok"     | grep -q '"token": "acme"'; then
  note "clean — extract refuses a non-ATS URL + drops a denylisted token, but emits a known-ATS board (boundary, spec §4/§6)."
else note "FAIL: extract boundary regressed — non-ATS not refused, denylist not applied, or a real board not emitted (spec §4/§6)."; fail=1; fi
# (c) FIELD-AGNOSTIC guard on querygen: no hardcoded role/field literals in the CODE (comments
# may carry illustrative examples; terms must come from the profile at runtime — spec §4/§6).
_qg_field=$(grep -vE '^[[:space:]]*#' "$_DQ" | sed 's/#.*//' \
  | grep -inwE 'product|engineer|engineering|nurse|nursing|developer|designer|accountant|teacher|analyst|marketing|sales|finance|lawyer|recruiter|manager')
if [ -n "$_qg_field" ]; then echo "$_qg_field"; note "FAIL: discover-querygen.py hardcodes a role/field literal — queries must derive from the profile (spec §4/§6)."; fail=1
else note "clean — discover-querygen.py hardcodes no role/field literal; queries derive from the profile (field-agnostic, spec §4/§6)."; fi

# --- Honest-framing guard: the public docs must not oversell auto mode (spec §6) ---
# /coapply:help + README must carry the broad-not-exhaustive + search-provider-privacy framing
# so the boundary is stated, not hidden.
_HELP=skills/help/SKILL.md
if grep -qiE 'broad|not whole-market|not exhaustive|public ATS' "$_HELP" \
   && grep -qiE 'broad|not whole-market|not exhaustive|search provider|public ATS' README.md; then
  note "clean — help + README carry the honest auto-mode framing (broad-not-exhaustive, spec §6)."
else note "FAIL: help/README missing the honest auto-mode framing (broad-not-exhaustive / privacy note, spec §6)."; fail=1; fi

section "16. Hub boundary — local-only, read-mostly, no network, no url-hashing (spec features/hub/spec.md §5/§8)"
# The hub is a NEW visible surface (a server + a page + a launcher). It must hold the same
# stay-in-bounds line as the rest of the engine: bind loopback only, never reach the network,
# write only its three allow-listed files inside RUNS_DIR, and never recompute a fingerprint from
# a URL. GOTCHA: server.py's header COMMENTS contain the literal strings `0.0.0.0` and `sha1(url)`
# (documenting the guards it deliberately avoids) — so every assert below targets executable code
# or behavior, never a grep that a comment could satisfy.
_HS=hub/server.py
_HP=hub/index.html
_HK=skills/hub/SKILL.md
for f in "$_HS" "$_HP" "$_HK"; do
  [ -f "$f" ] || { note "FAIL: missing hub file $f"; fail=1; }
done

# (a) Loopback-only — BEHAVIORAL: launching with --host 0.0.0.0 must be refused (exit 2) before any
# bind happens. This executes the guard, so a commented-out check can't pass it.
_hub_t=$(mktemp -d)
python3 "$_HS" --runs-dir "$_hub_t" --host 0.0.0.0 >/dev/null 2>&1
if [ "$?" = 2 ]; then note "clean — server refuses a non-loopback (0.0.0.0) bind, exit 2 (boundary: local-only)."; else note "FAIL: server did not refuse a 0.0.0.0 bind — the local-only invariant is broken."; fail=1; fi
rm -rf "$_hub_t"
# Default host is loopback + the loopback allow-set is present (structural backstop).
if grep -q 'LOOPBACK_HOSTS' "$_HS" && grep -qE -- '--host", *default="127\.0\.0\.1"' "$_HS"; then
  note "clean — LOOPBACK_HOSTS allow-set present and the default host is 127.0.0.1."
else note "FAIL: server.py lost LOOPBACK_HOSTS or its 127.0.0.1 default host."; fail=1; fi

# (b) No OUTBOUND network. The hub serves a LOCAL page (http.server / socketserver are inbound and
# fine) but must never act as a network CLIENT. Ban the outbound-client signatures; allow
# urllib.parse (pure string parsing) and http.server (the local listener).
_hub_net=$(grep -nE '(^|[^.])\b(requests|aiohttp|httplib|http\.client)\b|urllib\.request|\burlopen\b|socket\.create_connection' "$_HS" "$_HP" 2>/dev/null)
if [ -n "$_hub_net" ]; then echo "$_hub_net"; note "FAIL: hub references an outbound network client — it must never leave the machine."; fail=1
else note "clean — hub imports no outbound network client (urllib.parse / http.server for the local listener only)."; fi

# (c) Writes ONLY the three allow-listed files, each path-confined to RUNS_DIR. Assert the allow-list
# constants and the realpath+startswith confinement are present (a write outside RUNS_DIR is the
# exfiltration risk; the confinement is the guard).
if grep -q 'QUEUE_FILE *= *"\.coapply_queue\.json"' "$_HS" \
   && grep -q 'HUB_STATE_FILE *= *"\.coapply_hub_state\.json"' "$_HS" \
   && grep -q 'SEEN_FILE *= *"_discovery_seen\.txt"' "$_HS" \
   && grep -q 'os\.path\.realpath' "$_HS" \
   && grep -qE 'startswith\(RUNS_DIR' "$_HS"; then
  note "clean — server writes only the 3 allow-listed files, path-confined to RUNS_DIR (realpath + startswith)."
else note "FAIL: server.py lost its write allow-list or its RUNS_DIR path confinement."; fail=1; fi

# (d) No url->fp hashing anywhere in the hub. The hub READS the stored fp/discoveryFp and VALIDATES
# its shape; it must never compute a hash (fp = sha1(ats|token|id), not sha1(url) — recomputing would
# let a relabel/URL change resurface a job). Comment-proof: the documenting comments say "sha1(...)",
# never "hashlib"/"createHash"/"subtle.digest" — those are the only ways to ACTUALLY hash in py/js.
_hub_hash=$(grep -nE 'hashlib|crypto\.subtle|subtle\.digest|createHash' "$_HS" "$_HP" 2>/dev/null)
if [ -n "$_hub_hash" ]; then echo "$_hub_hash"; note "FAIL: hub contains hashing code — it must read the stored fp, never recompute one from a URL."; fail=1
else note "clean — hub does no hashing (reads/validates the stored fp; never sha1(url))."; fi

# (e) The page is fully self-contained — NO external assets (a CDN/font fetch phones home and breaks
# both the local-only invariant and offline use; spec §6).
_hub_ext=$(grep -inE '<script[^>]+src=|<link[^>]+href="https?:|cdn\.|googleapis|tailwind|unpkg|jsdelivr|fonts\.google' "$_HP" 2>/dev/null)
if [ -n "$_hub_ext" ]; then echo "$_hub_ext"; note "FAIL: index.html pulls an external asset — it must be fully self-contained (no CDN/web fonts)."; fail=1
else note "clean — index.html is fully self-contained (no external script/style/font/CDN)."; fi

# (f) Queue consumer SHIPS (the dead-end guard, spec §7). The hub's primary action (Add to apply
# queue) is a no-op unless a gate skill consumes .coapply_queue.json. /coapply:start consumes it on
# an empty invocation — assert that wiring exists so the loop closes in this release.
if grep -q '\.coapply_queue\.json' skills/start/SKILL.md && grep -qiE 'queue' skills/start/SKILL.md; then
  note "clean — /coapply:start consumes the hub apply queue (the queue loop closes; not a dead-end)."
else note "FAIL: no skill consumes .coapply_queue.json — the hub's queue action would be a dead-end (spec §7)."; fail=1; fi

# (g) The launcher is a SKILL (commands don't substitute \${CLAUDE_PLUGIN_ROOT}) and runs the
# resolver bare (Step-0 discipline) rather than the un-allowlistable VAR="$(...)" wrapper.
if grep -q 'profile-status.sh' "$_HK" && grep -q '\${CLAUDE_PLUGIN_ROOT}/hub/server.py' "$_HK"; then
  note "clean — hub launcher is a skill that resolves paths then launches the server with the real RUNS_DIR."
else note "FAIL: hub launcher skill is missing its profile-status.sh resolve or its server launch line."; fail=1; fi

section "17. Off-function gate — seed words must stay overridable by a user's own targets"
# The off-function gate is field-agnostic only because a user's OWN target roles can protect a
# word from it (a designer targeting "Product Designer" keeps designer titles). Two ways to
# silently break that, both of which look like an obvious improvement at the time:
#   · a seed that is also a STOPWORD  → _phrase_terms() filters stopwords out of `protected`,
#     so NO user could ever claim it: the ban becomes global and un-overridable.
#   · a seed that is also a GENERIC_ROLE_WORD → the code would both strip the word as a level
#     qualifier and drop the title for naming a profession. Contradictory by construction.
# Candidates that trip this are exactly the tempting ones: assistant, coordinator, specialist,
# administrator, intern. Assert disjointness so the mistake fails the audit, not review.
_disjoint=$(python3 - <<'PY' 2>&1
import importlib.util, pathlib, sys
def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, pathlib.Path("scripts") / rel)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod
try:
    surface = load("_surf", "discover-surface.py")
    triage = load("_tri", "discover-triage.py")
except Exception as e:
    print(f"ERROR: could not import matcher scripts: {e}"); sys.exit(0)
off = set(getattr(surface, "OFF_FUNCTION_WORDS", set()))
stop = set(getattr(triage, "STOPWORDS", set()))
generic = set(getattr(surface, "GENERIC_ROLE_WORDS", set()))
bad_stop, bad_generic = sorted(off & stop), sorted(off & generic)
if bad_stop:
    print(f"FAIL: off-function seeds are also STOPWORDS (no user could ever protect them): {bad_stop}")
if bad_generic:
    print(f"FAIL: off-function seeds are also GENERIC_ROLE_WORDS (stripped AND dropped): {bad_generic}")
if not bad_stop and not bad_generic:
    print(f"OK {len(off)} seeds, disjoint from {len(stop)} stopwords and {len(generic)} generic role words")
PY
)
case "$_disjoint" in
  OK*) note "clean — ${_disjoint}." ;;
  *)   echo "$_disjoint"; note "FAIL: off-function seeds collide with stopwords/generic role words."; fail=1 ;;
esac

section "18. check-letter.sh — §1a gates, and the caveat trap it exists to survive"
# The letter checker is only worth having if it fails LOUDLY in the two ways a letter
# actually goes wrong: a banned phrase, and a claim above what the profile allows. Every
# assertion below is a way the checker could silently start passing everything.
_cl_t="$(mktemp -d)"; _cl_p="$_cl_t/profile"; mkdir -p "$_cl_p/playbooks"
# Two caveats in the shapes that broke the naive implementation: a TYPED VARIANT
# ("Jargon caveat") and a BARE negative with no caveat header at all. Only one of the
# two would be found by grepping for "Caveat for downstream agents" — which is exactly
# how a header-matching checker reports coverage while missing most of the ceilings.
cat > "$_cl_p/skills-experience.md" <<'EOF'
**Jargon caveat for downstream agents:** Don't lead with the name "Widget Engine" in external copy.
- **They have never used the Acme platform.** Never claim they are an Acme customer.
EOF
_cl_caveats=$(bash scripts/check-letter.sh --init-ceilings --profile "$_cl_p" 2>/dev/null | grep -c '^#ack ')
if [ "$_cl_caveats" = "2" ]; then note "clean — finds BOTH caveat shapes (typed variant + bare negative), not just the headered one."
else note "FAIL: --init-ceilings found $_cl_caveats of 2 caveats — the header-grep trap is back."; fail=1; fi

# A ban list is only trustworthy if it comes from the rules files at runtime. Assert a real
# banned phrase from the shipped shared rules is caught with no per-user configuration.
printf 'I have a proven track record of shipping things that work for people.\n' > "$_cl_t/bad.md"
bash scripts/check-letter.sh "$_cl_t/bad.md" --profile "$_cl_p" --words 1-1000 >/dev/null 2>&1
[ "$?" = "1" ] && note "clean — a banned phrase from the shared rules fails the letter (exit 1)." \
                || { note "FAIL: banned-phrase gate did not fail a letter containing one."; fail=1; }

# The " - " regression. humanizer-rules.md says `Use hyphens " - " for asides, never em
# dashes` under a MANDATORY heading. If extraction ever stops being heading-scoped, " - "
# enters the ban list and every letter with an aside fails. Silent, total, plausible.
printf 'We shipped it - fast - and the numbers held.\n' > "$_cl_t/aside.md"
bash scripts/check-letter.sh "$_cl_t/aside.md" --profile "$_cl_p" --words 1-1000 >/dev/null 2>&1
[ "$?" != "1" ] && note "clean — a hyphen aside is not treated as a banned phrase." \
                || { note "FAIL: ban extraction is no longer heading-scoped — \" - \" got banned."; fail=1; }

printf 'We shipped it fast and the numbers held.\n' > "$_cl_t/clean.md"
# Undeclared ceilings must NEVER read as a pass. Exit 3 (INCOMPLETE) is the whole point:
# a green check that skipped the claim gate is worse than no check at all.
bash scripts/check-letter.sh "$_cl_t/clean.md" --profile "$_cl_p" --words 1-1000 >/dev/null 2>&1
[ "$?" = "3" ] && note "clean — undeclared caveats exit 3 (INCOMPLETE), never 0." \
               || { note "FAIL: a letter with undeclared caveats did not report INCOMPLETE."; fail=1; }

# With every caveat declared and nothing violated, it must actually pass — a checker that
# can't reach 0 gets ignored, and an ignored gate is a removed gate.
_cl_ids=$(bash scripts/check-letter.sh --init-ceilings --profile "$_cl_p" 2>/dev/null | sed -n 's/^#ack //p')
{ printf 'words 1-1000\n'; for _i in $_cl_ids; do printf 'ack %s\n' "$_i"; done; } > "$_cl_t/ceil"
bash scripts/check-letter.sh "$_cl_t/clean.md" --profile "$_cl_p" --ceilings "$_cl_t/ceil" >/dev/null 2>&1
[ "$?" = "0" ] && note "clean — a clean letter with all caveats declared exits 0." \
               || { note "FAIL: a clean, fully-declared letter did not pass."; fail=1; }

# And a declared ceiling must bite.
{ printf 'words 1-1000\n'; for _i in $_cl_ids; do printf 'ack %s\n' "$_i"; printf 'forbid %s Acme customer\n' "$_i"; done; } > "$_cl_t/ceil2"
printf 'I was an Acme customer for years.\n' > "$_cl_t/claim.md"
bash scripts/check-letter.sh "$_cl_t/claim.md" --profile "$_cl_p" --ceilings "$_cl_t/ceil2" >/dev/null 2>&1
[ "$?" = "1" ] && note "clean — a declared forbid pattern fails the letter." \
               || { note "FAIL: a declared ceiling did not catch a claim that violates it."; fail=1; }

bash scripts/check-letter.sh "$_cl_t/nope.md" --profile "$_cl_p" >/dev/null 2>&1
[ "$?" = "2" ] && note "clean — unreadable input exits 2 (distinct from a real failure)." \
               || { note "FAIL: missing letter file did not exit 2."; fail=1; }
rm -rf "$_cl_t"

# A human-judgment gate the script CAN'T verify. Printed every run so it can't be skipped.
section "19. Shipped decisions that nothing guarded — gate, watermark, docx, run-tier"
# Everything here was decided, shipped, and then protected by nothing. Each line is a
# decision that could silently reverse in a later edit with no test noticing.
_ma=profile/prompts/master-apply.md
# (a) The four non-negotiable invariants must stay stated where the orchestrator reads
#     them. PRINCIPLES.md holding them is not enough — the orchestrator must carry them.
for _inv in 'human gate' 'never fabricate' 'never auto-submit'; do
  grep -qi "$_inv" "$_ma" || { note "FAIL: master-apply.md no longer states the invariant '$_inv'."; fail=1; }
done
# (b) The gate is a hard stop, and the expensive wave stays behind it.
grep -qi 'MANDATORY GATE' "$_ma" || { note "FAIL: the mandatory gate heading is gone from master-apply.md."; fail=1; }
grep -qi 'do NOT run Wave A2 yet' "$_ma" || { note "FAIL: the expensive wave is no longer explicitly held behind the gate."; fail=1; }
# (c) The tier chosen AT the gate must be recorded to the run record. render-receipt.sh
#     reads that record (§6); if the orchestrator stops writing it, the receipt silently
#     reverts to reporting a stale standing tier and nothing else would catch it.
grep -qiE '_run\.json\.tier|Record it in .*tier' "$_ma" \
  || { note "FAIL: master-apply.md no longer records the gate-time tier to _run.json — the receipt would go stale silently."; fail=1; }
# (d) .docx generation was removed (0.12.0) and the import path refuses to parse it
#     (onboarding spec: paste / PDF / text only, no-deps). Both directions must hold.
# (audit.sh is excluded: it is the auditor, and its own pattern string would match.)
_docx_gen=$(grep -rniE '(write|generate|create|produce|export|convert).{0,24}\.docx' skills/ profile/prompts/ scripts/ 2>/dev/null \
  | grep -v '^scripts/audit\.sh:')
[ -z "$_docx_gen" ] || { note "FAIL: something instructs generating a .docx — it was removed in 0.12.0 (no-deps)."; printf '%s\n' "$_docx_gen"; fail=1; }
grep -qi 'docx' profile/prompts/onboarding/import-resume.md \
  || { note "FAIL: the resume import no longer tells the user it can't read Word files — it will try and silently corrupt."; fail=1; }
# (e) The generated-content watermark: written on the way out, checked on the way in.
#     This is what stops the tool from learning its own voice back as a user example.
grep -q 'coapply:generated' "$_ma" || { note "FAIL: master-apply.md no longer watermarks generated artifacts."; fail=1; }
grep -q 'coapply:generated' skills/add/SKILL.md || { note "FAIL: /coapply:add no longer screens for CoApply's own output."; fail=1; }
# (f) The letter slot: both agents exist and exactly one fills the slot per run. If the
#     mode ever stops selecting, the run either writes two letters or none.
for _la in cover-letter letter-prompt; do
  [ -f "profile/prompts/agents/$_la.md" ] || { note "FAIL: missing letter agent profile/prompts/agents/$_la.md."; fail=1; }
done
grep -q 'LETTER_MODE' "$_ma" || { note "FAIL: master-apply.md no longer resolves \$LETTER_MODE — the letter slot has no selector."; fail=1; }
grep -qi 'never both' profile/prompts/phases/phase-content.md \
  || { note "FAIL: phase-content.md no longer states that exactly one letter agent runs."; fail=1; }
# (g) Config writes must merge, never replace. A whole-file write silently deletes every
#     other setting the user has - the tracker ID, the letter mode, anything added later.
_cfg_clobber=$(grep -rn '> *"\${PROFILE_DIR}/coapply\.config\.json"' skills/ profile/ 2>/dev/null)
[ -z "$_cfg_clobber" ] || { note "FAIL: a skill writes coapply.config.json whole-file — use scripts/config-set.sh (it merges)."; printf '%s\n' "$_cfg_clobber"; fail=1; }
[ -f scripts/config-set.sh ] || { note "FAIL: scripts/config-set.sh is missing — config writes have no merge path."; fail=1; }
[ "$fail" = 0 ] && note "clean — gate, invariants, run-tier record, docx removal, watermark, letter slot, and config merge all intact."

section "Manual gate — confirm before you ship (not automatable)"
note "[ ] Dogfooded every new/changed skill on a REALISTIC input — including a vague one — and read the output."
note "[ ] Premise check on anything user-facing (CoApply never fabricates, never acts for the user):"
note "      - Does it put words in the user's mouth / add content they didn't give?"
note "      - Does it act for the user (submit / send / decide) instead of letting them decide?"
note "      - Does it use or expose their private material beyond what's shown to them?"
note "    Any 'yes' = not ready. Fix it before shipping."

section "Result"
if [ "$fail" = 0 ]; then echo "PASS (automated) — now clear the manual gate above before releasing."; exit 0; else echo "FAIL — fix the items above before releasing."; exit 1; fi
