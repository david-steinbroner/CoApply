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
for s in start resume list help setup tier add feedback; do
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

section "Result"
if [ "$fail" = 0 ]; then echo "PASS — safe to release."; exit 0; else echo "FAIL — fix the items above before releasing."; exit 1; fi
