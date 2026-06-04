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
for s in start resume list help; do
  [ -f "skills/$s/SKILL.md" ] || { note "FAIL: missing skills/$s/SKILL.md"; fail=1; }
done
[ -d commands ] && { note "FAIL: commands/ exists — entry points must be skills (\${CLAUDE_PLUGIN_ROOT} doesn't resolve in commands)."; fail=1; }
grep -q '"name": "coapply"' .claude-plugin/plugin.json || { note "FAIL: plugin name is not 'coapply'."; fail=1; }
# Count the employee-mode agents (expect 13).
agents=$(ls profile/prompts/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$agents" = "13" ] || note "WARN: expected 13 agents, found $agents."
[ "$fail" = 0 ] && note "structure OK."

section "Result"
if [ "$fail" = 0 ]; then echo "PASS — safe to release."; exit 0; else echo "FAIL — fix the items above before releasing."; exit 1; fi
