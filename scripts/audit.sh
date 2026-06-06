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
for s in start resume list help setup tier; do
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

section "Result"
if [ "$fail" = 0 ]; then echo "PASS — safe to release."; exit 0; else echo "FAIL — fix the items above before releasing."; exit 1; fi
