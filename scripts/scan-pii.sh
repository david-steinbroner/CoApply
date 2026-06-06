#!/usr/bin/env bash
# CoApply — best-effort lint for TRUE SECRETS in content the user wants to store.
#
# Philosophy (spec v3 §21.B/E): everyday personal facts — salary/comp, city,
# work-authorization status, phone — are NOT secrets. They belong in facts.md and
# are sent to the AI like the rest of the profile. This lint does NOT flag them.
# It flags only things that should never be stored or sent: SSNs, card/bank/account
# numbers, passwords, API keys/tokens, IBANs, and exact street addresses.
#
# It is BEST-EFFORT, not a guarantee — it will miss formats it doesn't know. It is
# a courtesy guard so a user doesn't accidentally drop a secret into a profile file
# that gets sent every run; it is not a privacy boundary. The README says so.
#
# Output: redacted flags only — TYPE + line number, NEVER the matched value (no
# digits, ever). Exit 3 if any secret-like content is found, 0 if clean.
#
# Usage: scan-pii.sh <file>
set -uo pipefail
F="${1:-}"
[ -f "$F" ] || exit 0

found=0
flag() { printf 'possible %s (line %s)\n' "$1" "$2"; found=1; }

ln=0
while IFS= read -r line || [ -n "$line" ]; do
  ln=$((ln + 1))
  low="$(printf '%s' "$line" | tr 'A-Z' 'a-z')"

  # SSN (dashed) — bare 9-digit numbers are intentionally NOT flagged (too many
  # false positives; salary/order numbers). Best-effort by design.
  printf '%s' "$line" | grep -Eq '(^|[^0-9])[0-9]{3}-[0-9]{2}-[0-9]{4}([^0-9]|$)' && flag "SSN" "$ln"

  # Card number — 13-16 digits, optionally grouped by spaces/dashes. Phone (<=11)
  # and salary (<=7) don't reach 13.
  printf '%s' "$line" | grep -Eq '(^|[^0-9])([0-9][ -]?){13,16}([^0-9]|$)' && flag "card number" "$ln"

  # IBAN
  printf '%s' "$line" | grep -Eq '\b[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}\b' && flag "bank/IBAN" "$ln"

  # AWS access key id
  printf '%s' "$line" | grep -Eq '\bAKIA[0-9A-Z]{16}\b' && flag "API key" "$ln"

  # Common secret token shapes
  printf '%s' "$line" | grep -Eq 'sk-[A-Za-z0-9]{16,}' && flag "API key/token" "$ln"
  case "$low" in
    *"api key"*|*"api_key"*|*"apikey"*|*"secret key"*|*"access token"*|*"bearer "*) flag "API key/token" "$ln" ;;
    *password*|*passwd*|*passphrase*) flag "password" "$ln" ;;
    *"routing number"*|*"account number"*|*"acct number"*|*"account #"*) flag "bank account" "$ln" ;;
  esac

  # Exact street address — require a number + 1-3 Capitalized words + a street
  # suffix. The capitalization requirement kills false positives like
  # "got 3 offers the same way".
  printf '%s' "$line" | grep -Eq '(^|[^0-9])[0-9]{1,6}[[:space:]]+([A-Z][a-zA-Z]+[[:space:]]+){1,3}(Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Way|Place|Pl|Terrace|Circle|Cir)\b' && flag "street address" "$ln"
done < "$F"

[ "$found" = 1 ] && exit 3 || exit 0
