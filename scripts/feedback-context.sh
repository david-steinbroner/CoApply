#!/usr/bin/env bash
# CoApply — gather reviewable context for a /coapply:feedback issue, and build a
# prefilled GitHub "new issue" URL. These are the two jobs the agent shouldn't
# spend tokens on (and would get wrong): reading version/run state, and
# percent-encoding a URL.
#
# Philosophy: NO silent diagnostics. Everything this prints is shown to the user
# before anything is sent. It NEVER reads profile contents or letter text — only
# the tool's own version/config and a run's structural state (phase, which step
# failed). Best-effort: anything it can't determine is omitted, never guessed.
#
# Usage:
#   feedback-context.sh context [profile_dir] [run_slug]
#       Print a human-readable context block: CoApply version, Claude Code
#       version, OS, tier — and, only if run_slug is given and valid, that run's
#       phase + failed step.
#   feedback-context.sh url <title> <labels> <body_file>
#       Print a percent-encoded .../issues/new?title=&labels=&body= URL. The body
#       is read from a file to avoid shell-quoting hazards with multi-line markdown.
#   feedback-context.sh repo
#       Print the repository URL (for the plain "file an issue" link).
#
# Always exits 0 (best-effort). LC_ALL=C for deterministic, byte-wise encoding.
set -uo pipefail
export LC_ALL=C LANG=C

ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
PLUGIN_JSON="$ROOT/.claude-plugin/plugin.json"

# Value of a top-level "key": "value" string from a JSON file (best-effort, no jq).
json_str() { # <key> <file>
  [ -f "$2" ] || return 0
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" 2>/dev/null | head -1 \
    | sed 's/.*:[[:space:]]*"//; s/"$//'
}

repo_url() {
  local r; r="$(json_str repository "$PLUGIN_JSON")"
  [ -n "$r" ] || r="$(json_str homepage "$PLUGIN_JSON")"
  printf '%s' "${r%.git}"
}

# RFC 3986 percent-encode, byte-wise. Unreserved chars stay literal.
urlencode() { # <string>
  local s="$1" i c out=""
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out="$out$c" ;;
      *) out="$out$(printf '%%%02X' "$(( $(printf '%d' "'$c") & 0xFF ))")" ;;
    esac
  done
  printf '%s' "$out"
}

cmd="${1:-context}"; shift 2>/dev/null || true

case "$cmd" in
  repo)
    repo_url; printf '\n'
    ;;

  url)
    title="${1:-}"; labels="${2:-}"; body_file="${3:-}"
    body=""
    [ -n "$body_file" ] && [ -f "$body_file" ] && body="$(cat "$body_file")"
    printf '%s/issues/new?title=%s&labels=%s&body=%s\n' \
      "$(repo_url)" "$(urlencode "$title")" "$(urlencode "$labels")" "$(urlencode "$body")"
    ;;

  context)
    profile_dir="${1:-}"; run_slug="${2:-}"
    ver="$(json_str version "$PLUGIN_JSON")"; [ -n "$ver" ] || ver="unknown"
    cc="$(claude --version 2>/dev/null | head -1 | tr -d '\n')"; [ -n "$cc" ] || cc="unknown"
    os="$(uname -sr 2>/dev/null)"; [ -n "$os" ] || os="unknown"
    tier="unknown"
    if [ -n "$profile_dir" ] && [ -f "$profile_dir/coapply.config.json" ]; then
      t="$(json_str tier "$profile_dir/coapply.config.json")"; [ -n "$t" ] && tier="$t"
    fi
    printf -- '- CoApply version: %s\n' "$ver"
    printf -- '- Claude Code: %s\n' "$cc"
    printf -- '- OS: %s\n' "$os"
    printf -- '- Tier: %s\n' "$tier"
    if [ -n "$run_slug" ] && [ -n "$profile_dir" ]; then
      rj="$profile_dir/runs/$run_slug/_run.json"
      if [ -f "$rj" ]; then
        phase="$(json_str phase "$rj")"; [ -n "$phase" ] || phase="unknown"
        # Name of the first artifact whose status is "failed". RS="}" makes each
        # artifact object its own record, so this is correct whether _run.json is
        # pretty-printed or compact single-line.
        failed="$(awk 'BEGIN{RS="}"}
          /"status"[[:space:]]*:[[:space:]]*"failed"/ &&
          match($0,/"name"[[:space:]]*:[[:space:]]*"[^"]*"/){
            s=substr($0,RSTART,RLENGTH);sub(/.*"name"[[:space:]]*:[[:space:]]*"/,"",s);sub(/".*/,"",s);print s;exit
          }' "$rj" 2>/dev/null)"
        printf -- '- Run: %s (phase: %s' "$run_slug" "$phase"
        [ -n "$failed" ] && printf ', failed step: %s' "$failed"
        printf ')\n'
      fi
    fi
    ;;

  *)
    printf 'usage: feedback-context.sh {context|url|repo} ...\n' >&2
    ;;
esac
exit 0
