#!/usr/bin/env bash
# CoApply — best-effort lint for TRUE SECRETS in content the user wants to store.
#
# Philosophy (spec v3 §21.B/E): everyday personal facts — salary/comp, city,
# work-authorization status, phone — are NOT secrets. They belong in facts.md and
# are sent to the AI like the rest of the profile. This lint does NOT flag them.
# It flags only things that should never be stored or sent: SSNs, card/bank/account
# numbers, passwords, API keys/tokens, private keys, IBANs, and exact street addresses.
#
# It is BEST-EFFORT, not a guarantee — it will miss formats it doesn't know. It is
# a courtesy guard so a user doesn't accidentally drop a secret into a profile file
# that gets sent every run; it is not a privacy boundary. The README says so.
#
# Output: redacted flags only — TYPE + line number(s), NEVER the matched value
# (no digits, ever). Exit 3 if any secret-like content is found, 0 if clean.
#
# Implementation notes:
# - One grep pass per pattern over the whole file (not a per-line subprocess loop)
#   — fast even on large pastes.
# - LC_ALL=C: byte-wise matching, deterministic, and robust to invalid UTF-8.
# - Output is built from `grep -n` LINE NUMBERS only (cut to field 1); the matched
#   text never leaves grep, so no secret value can leak into stdout.
#
# Usage: scan-pii.sh <file>
set -uo pipefail
export LC_ALL=C LANG=C
F="${1:-}"
[ -f "$F" ] || exit 0

found=0
# Print "possible <type> (line N, M)" using only line numbers from grep -n.
flag() { # <type> <ERE> [grep-flags]
  local type="$1" re="$2" gf="${3:-}"
  local lines
  # -e so a pattern beginning with '-' (e.g. PEM headers) isn't parsed as options.
  lines=$(grep -n $gf -E -e "$re" "$F" 2>/dev/null | cut -d: -f1 | paste -sd, - 2>/dev/null)
  if [ -n "$lines" ]; then
    printf 'possible %s (line %s)\n' "$type" "$lines"
    found=1
  fi
}

# --- SSN (dashed). Bare 9-digit numbers are intentionally NOT flagged. ----------
flag "SSN" '(^|[^0-9])[0-9]{3}-[0-9]{2}-[0-9]{4}([^0-9]|$)'

# --- Card / PAN. Two shapes, tuned to avoid year/measurement false positives: ---
#   (a) a contiguous run of 13-19 digits (ISO/IEC 7812 PAN length), or
#   (b) grouped 4-4-4(-1..4) where the FIRST group starts 3-6 (real card BINs),
#       which excludes "2019 2020 2021 2022" (year runs start with 1-2).
flag "card number" '(^|[^0-9])[0-9]{13,19}([^0-9]|$)'
flag "card number" '(^|[^0-9])[3-6][0-9]{3}[ -][0-9]{4}[ -][0-9]{4}([ -][0-9]{1,4})?([^0-9]|$)'

# --- IBAN: 2 letters + 2 digits + 11-30 alnum, on a token boundary. -------------
flag "bank/IBAN" '(^|[^A-Za-z0-9])[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}([^A-Za-z0-9]|$)'

# --- API keys / tokens (common modern shapes). Case-sensitive prefixes. ---------
flag "API key/token" '(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|sk-proj-[A-Za-z0-9_-]{16,}|sk-[A-Za-z0-9]{16,}|sk_live_[A-Za-z0-9]{16,}|pk_live_[A-Za-z0-9]{16,}|rk_live_[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|ghu_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{16,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+)'

# --- Private key blocks (PEM). Zero false-positive signature. --------------------
flag "private key" '-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----'

# --- Secret-ish keywords, on word boundaries (no \b — portable boundary classes).
flag "password"     '(^|[^A-Za-z])(password|passwd|passphrase)([^A-Za-z]|$)' '-i'
flag "API key/token" '(^|[^A-Za-z])(api[ _-]?key|secret[ ]+key|access[ ]+token)([^A-Za-z]|$)' '-i'
flag "bank account" '(^|[^A-Za-z])(routing|account|acct)[ ]+(number|#)' '-i'

# --- Exact street address: number + 1-3 Capitalized words + a street suffix. -----
flag "street address" '(^|[^0-9])[0-9]{1,6}[ ]+([A-Z][a-zA-Z]+[ ]+){1,3}(Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Way|Place|Pl|Terrace|Circle|Cir)([^a-zA-Z]|$)'

[ "$found" = 1 ] && exit 3 || exit 0
