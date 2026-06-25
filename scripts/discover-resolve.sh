#!/usr/bin/env bash
# CoApply — discovery resolve (build step 3 of docs/features/discovery/spec.md §10).
#
# Turns a company careers URL (or a direct ATS board URL) into a watchlist row's
# (ats, board-id) pair, so `/coapply:discover add` can append it without the user
# hand-decoding ATS hosts. Deterministic, no LLM (spec §3.2).
#
# THE BOUNDARY, POINT 2 OF 3 (spec §4): resolve is itself a network call to an
# ARBITRARY user-supplied host (a careers page can redirect anywhere). So the
# security property is not "what we fetch" but "what we EMIT": we follow redirects
# with a HEAD request only, then **validate that the FINAL resolved host matches a
# known ATS pattern** and refuse otherwise. We never read job data here (that's the
# fetch script, with its own allowlist) — resolve only inspects where a URL lands.
#
# Usage:
#   discover-resolve.sh <careers-URL | ATS-board-URL>
#
# Stdout on success (machine-parseable, KEY=value — mirrors profile-status.sh):
#   ats=greenhouse
#   token=acme
#   url=https://boards.greenhouse.io/acme
# Stderr: a one-line human note.
# Exit: 0 = detected a supported ATS; 1 = no ATS detected / not a usable URL /
#       network failure (the skill should then ask for the board URL); 3 = detected
#       Workday, which is recognized but deferred (spec §8) — not yet fetchable.

set -uo pipefail

UA="CoApply-discovery/0.1 (+https://github.com/david-steinbroner/CoApply)"

err() { printf 'discover-resolve: %s\n' "$1" >&2; }

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
  err "usage: discover-resolve.sh <careers-URL | ATS-board-URL>"
  exit 1
fi

raw="$1"

# --- normalize input into something curl can follow -------------------------------
# Accept: a full URL; a scheme-less URL/host ("boards.greenhouse.io/acme",
# "acme.com/careers"); reject a bare name with no dot+no slash (we can't guess a
# company's domain without searching, and searching is the forbidden aggregator path
# — ask for the URL instead).
case "$raw" in
  http://*|https://*) url="$raw" ;;
  *)
    case "$raw" in
      *.*/*|*.*) url="https://$raw" ;;   # looks like a host/domain → assume https
      *)
        err "couldn't detect an ATS from '$raw' — paste the company's careers URL or its Greenhouse/Lever/Ashby board URL"
        exit 1 ;;
    esac ;;
esac

# classify <url> → parse one URL's host + first path segment, and match the host
# against the known-ATS allowlist. On a match, sets R_ATS/R_TOKEN/R_HOST/R_URL and
# returns 0; else returns 1. Pure parameter expansion — no python/jq dependency.
R_ATS=""; R_TOKEN=""; R_HOST=""; R_URL=""
classify() {
  local u="$1" ns h p tok
  case "$u" in http://*|https://*) ;; *) return 1 ;; esac
  ns="${u#*://}"
  h="${ns%%/*}"; h="${h%%:*}"      # host, minus any :port
  p="${ns#"$h"}"; p="${p#/}"       # path, minus leading slash
  tok="${p%%/*}"                   # first path segment …
  tok="${tok%%\?*}"; tok="${tok%%#*}"   # … minus query/fragment
  case "$h" in
    boards.greenhouse.io|job-boards.greenhouse.io|boards-api.greenhouse.io) R_ATS=greenhouse ;;
    jobs.lever.co|api.lever.co) R_ATS=lever ;;
    jobs.ashbyhq.com|api.ashbyhq.com) R_ATS=ashby ;;
    *.myworkdayjobs.com) R_ATS=workday ;;
    *) return 1 ;;
  esac
  R_TOKEN="$tok"; R_HOST="$h"; R_URL="$u"
  return 0
}

emit() {  # emit using R_ATS/R_TOKEN/R_HOST/R_URL
  if [ "$R_ATS" = "workday" ]; then
    err "detected Workday ($R_HOST) — recognized but not yet supported (deferred, spec §8). Skipping."
    exit 3
  fi
  if [ -z "$R_TOKEN" ]; then
    err "landed on $R_HOST but found no board id in the path ($R_URL) — paste the full board URL"
    exit 1
  fi
  printf 'ats=%s\n' "$R_ATS"
  printf 'token=%s\n' "$R_TOKEN"
  printf 'url=%s\n' "$R_URL"
  err "detected $R_ATS board '$R_TOKEN' ($R_HOST)"
  exit 0
}

# 1) If the INPUT URL is already a known ATS host, trust it directly — no network
# call needed, and this is robust to branded boards that redirect AWAY to a company
# domain (e.g. boards.greenhouse.io/<id> now 302s to <company>.com, which would
# defeat final-host-only matching).
if classify "$url"; then emit; fi

# 2) Otherwise the input is a generic careers URL — follow redirects (HEAD only) and
# look for an ATS host ANYWHERE in the chain: the input, every Location: hop, and the
# final landing URL. We only ever EMIT an ATS board, so an arbitrary careers host can
# never be registered as one (the boundary's refusal gate, spec §4 point 2). curl's
# --proto bounds redirects to http/https.
dump="$(curl -sIL \
  --proto '=http,https' --proto-redir '=http,https' \
  --max-time 20 --max-redirs 10 \
  -A "$UA" \
  -w '\nurl_effective: %{url_effective}\n' \
  "$url" 2>/dev/null)"
rc=$?
if [ "$rc" -ne 0 ] || [ -z "$dump" ]; then
  err "couldn't reach '$url' (curl exit $rc) — check the URL, or paste the ATS board URL directly"
  exit 1
fi

# Candidate URLs, in chain order: each Location: redirect target, then the final
# effective URL. grep -i (not awk IGNORECASE — BSD awk silently ignores it) keeps the
# header-name match case-insensitive; sed strips the header name and trailing CR.
# Only absolute http(s) targets carry a host for classify() to match.
candidates="$(printf '%s\n' "$dump" \
  | grep -iE '^(location|url_effective):' \
  | sed -E 's/^[A-Za-z_]+:[[:space:]]*//; s/'$'\r''$//')"

while IFS= read -r cand; do
  [ -n "$cand" ] || continue
  if classify "$cand"; then emit; fi
done <<EOF
$candidates
EOF

# 3) Nothing in the chain was a known ATS → refuse (the spec's fallback message).
err "couldn't detect a supported ATS — '$url' didn't lead to a known Greenhouse/Lever/Ashby board. Paste the company's board URL (e.g. boards.greenhouse.io/<id>)."
exit 1
