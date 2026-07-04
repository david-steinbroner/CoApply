#!/usr/bin/env bash
# CoApply — standalone hub launcher (no Claude Code, no tokens).
#
# `/coapply:hub` starts the hub via the Claude skill, which spends tokens every time. This does the
# same three things straight from your terminal — resolve your runs folder, start the local server,
# open the browser — with zero Claude involvement. From the repo root: `make hub` (or `bash
# scripts/hub.sh`).
#
# It reuses the existing resolver (scripts/profile-status.sh -> resolve-profile-dir.sh), which reads
# the flat ~/.coapply_profile_path file that `/coapply:setup` writes — pure shell, no python needed
# to find your profile. The server itself binds 127.0.0.1 ONLY (loopback); this launcher never
# passes any other host. Runs in the FOREGROUND — Ctrl-C to stop.
#
# Optional overrides (for people who haven't run /coapply:setup):
#   bash scripts/hub.sh --runs-dir /abs/path/to/runs
#   bash scripts/hub.sh --profile-dir /abs/path/to/profile   # runs dir = <profile>/runs
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"   # repo root (this script lives in scripts/)
SCRIPTS="$HERE/scripts"
URL="http://127.0.0.1:7878/"

# --- parse optional overrides ------------------------------------------------------------------
OVERRIDE_RUNS="" ; OVERRIDE_PROFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --runs-dir)    OVERRIDE_RUNS="${2:-}" ; shift 2 || { echo "hub: --runs-dir needs a path" >&2; exit 1; } ;;
    --profile-dir) OVERRIDE_PROFILE="${2:-}" ; shift 2 || { echo "hub: --profile-dir needs a path" >&2; exit 1; } ;;
    -h|--help)     echo "usage: bash scripts/hub.sh [--runs-dir <path> | --profile-dir <path>]" ; exit 0 ;;
    *)             echo "hub: unknown argument: $1" >&2 ; exit 1 ;;
  esac
done

# --- resolve the runs dir ----------------------------------------------------------------------
if [ -n "$OVERRIDE_RUNS" ]; then
  RUNS_DIR="$OVERRIDE_RUNS"
elif [ -n "$OVERRIDE_PROFILE" ]; then
  RUNS_DIR="${APPLY_RUNS_DIR:-$OVERRIDE_PROFILE/runs}"
else
  # Reuse the same resolver the skill uses; it prints a line-per-field block and always exits 0.
  status="$("$SCRIPTS/profile-status.sh" 2>/dev/null)"
  PROFILE_DIR="$(printf '%s\n' "$status" | sed -n 's/^PROFILE_DIR=//p')"
  RUNS_DIR="$(printf '%s\n'   "$status" | sed -n 's/^RUNS_DIR=//p')"
  if [ -z "$PROFILE_DIR" ]; then
    echo "hub: no CoApply profile is configured yet." >&2
    echo "     Run /coapply:setup in Claude Code once, then 'make hub' works with no arguments." >&2
    echo "     (Or point this run at a folder: bash scripts/hub.sh --profile-dir /path/to/profile)" >&2
    exit 1
  fi
fi

# --- preconditions -----------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  echo "hub: the hub needs Python 3, which isn't on your PATH." >&2
  exit 1
fi
mkdir -p "$RUNS_DIR" 2>/dev/null || { echo "hub: cannot create runs folder: $RUNS_DIR" >&2; exit 1; }

# --- open the browser shortly after the server comes up ----------------------------------------
open_browser() {
  if   command -v open     >/dev/null 2>&1; then open "$URL"      # macOS
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"  # Linux
  fi
}
( sleep 1; open_browser >/dev/null 2>&1 ) &

echo "CoApply hub → $URL   (runs: $RUNS_DIR)"
echo "Ctrl-C to stop."

# --- start the server (foreground, loopback only) ----------------------------------------------
python3 "$HERE/hub/server.py" --runs-dir "$RUNS_DIR" --host 127.0.0.1
rc=$?
# exit 1 = port already bound → a hub is already running; that's a reuse, not an error.
if [ "$rc" -eq 1 ]; then
  echo "hub: a hub already appears to be running at $URL — reusing it (opened in your browser)."
  exit 0
fi
exit "$rc"
