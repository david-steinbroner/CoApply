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
SCAN_PATHS=(skills profile profile.example .claude-plugin README.md PRINCIPLES.md SECURITY.md CLAUDE.md CHANGELOG.md)

section "1. Personal-data leak scan"
# Anything personally identifying should never appear in the engine.
# (Author attribution in LICENSE / plugin.json / README "How this was built" is expected and excluded.)
# Note: the author's name is fine as attribution (LICENSE / plugin.json / README). The real
# leak risk is personal *experience/proof* data, personal *paths*, and account IDs.
PII='/Users/david|Projects/apply|24f6373b491f809|joinmosaic|\bFold\b|\bMosaic\b|Spin Wheel|Friends of Fold|Flash Stacks|Sensor Tower|Smilebooth'
hits=$(grep -rInE "$PII" "${SCAN_PATHS[@]}" 2>/dev/null | grep -viE 'run-folder|scaffold')
if [ -n "$hits" ]; then echo "$hits"; note "FAIL: personal-data tokens found in the engine."; fail=1; else note "clean — no personal-data tokens."; fi

section "2. Field-assumption scan (engine must be field-agnostic)"
# High-signal tells that the engine assumes the user is a PM / in tech.
FIELD='Growth PM|Compliance PM|product manager|product-manager|pm-builder|pm-growth|fintech\b'
hits=$(grep -rInE "$FIELD" skills profile profile.example .claude-plugin README.md 2>/dev/null)
if [ -n "$hits" ]; then echo "$hits"; note "FAIL: field/PM assumptions found — genericize them."; fail=1; else note "clean — no PM/field assumptions."; fi

section "3. Stray absolute paths / unresolved engine vars"
hits=$(grep -rInE '/Users/|/Projects/apply' skills profile profile.example 2>/dev/null)
if [ -n "$hits" ]; then echo "$hits"; note "FAIL: hardcoded absolute paths found."; fail=1; else note "clean — no hardcoded absolute paths."; fi

section "4. Structure & invariants"
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json profile/prompts/master-apply.md PRINCIPLES.md LICENSE; do
  [ -f "$f" ] || { note "FAIL: missing $f"; fail=1; }
done
for s in start resume list help setup tier add feedback discover; do
  [ -f "skills/$s/SKILL.md" ] || { note "FAIL: missing skills/$s/SKILL.md"; fail=1; }
done
[ -d commands ] && { note "FAIL: commands/ exists — entry points must be skills (\${CLAUDE_PLUGIN_ROOT} doesn't resolve in commands)."; fail=1; }
grep -q '"name": "coapply"' .claude-plugin/plugin.json || { note "FAIL: plugin name is not 'coapply'."; fail=1; }
# Count the employee-mode agents (expect 13).
agents=$(ls profile/prompts/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$agents" = "13" ] || note "WARN: expected 13 agents, found $agents."
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
# Sanity: count tagged dispatches (expect 13 across the two phase files).
_tagged=$(grep -hE 'instructed by `\$\{CLAUDE_PLUGIN_ROOT\}/profile/prompts/agents/[a-z-]+\.md' \
  profile/prompts/phases/phase-research.md profile/prompts/phases/phase-content.md 2>/dev/null \
  | grep -cE '\[(mechanical|reasoning|voice)\]')
[ "${_tagged:-0}" = "13" ] && note "clean — 13 agent dispatches tagged." || note "WARN: expected 13 tagged dispatches, found ${_tagged:-0}."

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

# A human-judgment gate the script CAN'T verify. Printed every run so it can't be skipped.
section "Manual gate — confirm before you ship (not automatable)"
note "[ ] Dogfooded every new/changed skill on a REALISTIC input — including a vague one — and read the output."
note "[ ] Premise check on anything user-facing (CoApply never fabricates, never acts for the user):"
note "      - Does it put words in the user's mouth / add content they didn't give?"
note "      - Does it act for the user (submit / send / decide) instead of letting them decide?"
note "      - Does it use or expose their private material beyond what's shown to them?"
note "    Any 'yes' = not ready. Fix it before shipping."

section "Result"
if [ "$fail" = 0 ]; then echo "PASS (automated) — now clear the manual gate above before releasing."; exit 0; else echo "FAIL — fix the items above before releasing."; exit 1; fi
