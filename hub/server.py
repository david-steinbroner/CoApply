#!/usr/bin/env python3
# CoApply — the HUB server (the funnel's persistent visual surface; docs/features/hub/spec.md §5).
#
# A thin, read-mostly lens over the user's single-writer ledgers. It joins the curated
# discover ledger (surfaced.json) to the run folder (runs/<slug>/_run.json) by fingerprint,
# derives each surfaced job's status READ-TIME (never persisted — that would clobber-race a
# concurrent discover run), and serves one self-contained page (hub/index.html).
#
# Hard boundaries (each is an invariant the audit asserts — see PRINCIPLES.md, spec §8):
#   • LOCAL ONLY. Binds 127.0.0.1 (loopback) — never 0.0.0.0. A LAN bind would expose the
#     user's private job pipeline + profile-derived data = exfiltration = a hard fail.
#   • NO NETWORK. stdlib only; no outbound calls, no third-party imports, no telemetry.
#   • READ-MOSTLY, PATH-CONFINED WRITES. Reads surfaced.json, runs/*/_run.json, and the
#     version files. Writes EXACTLY three allow-listed files, all inside RUNS_DIR:
#       .coapply_queue.json   (intent — a shopping list, consumed at the human gate)
#       .coapply_hub_state.json (lastVisitedAt — powers "N new since last visit")
#       _discovery_seen.txt   (append-only; the SAME dismiss cache the chat flow appends to)
#   • NEVER auto-submits, never runs an agent, never recomputes a fingerprint. The hub reads
#     the stored fp / discoveryFp; it never hashes a URL (fp = sha1(ats|token|id), not sha1(url)).
#   • Tolerant reads: a file caught mid-write returns last-good, never a 500/blank.
#
# Usage (launched by skills/hub/SKILL.md, which resolves RUNS_DIR to an absolute path):
#   python3 hub/server.py --runs-dir <ABS RUNS_DIR> [--host 127.0.0.1] [--port 7878]
#
# Single-writer-per-file is the load-bearing invariant: discover owns surfaced.json, start/resume
# own _run.json, the hub owns the three files above. No file has two writers.

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

SCHEMA_VERSION = 1

# A run is "live" if its _run.json was touched within this window (spec §4.4): not-done +
# fresh mtime → "running"; not-done + stale → "in-progress".
LIVE_WINDOW_S = 10 * 60

# Application statuses that mean "this run is not a live, committed application" — a run that
# ended in one of these resolves to "no-go" regardless of phase (spec §4.4).
NO_GO_STATUSES = {"rejected", "abandoned", "no_go", "no-go", "declined"}

# fp / discoveryFp are sha1 hex digests (fp = sha1("<ats>|<token>|<id>"), discover-fetch.py).
# Validated on every endpoint — also blocks path traversal via an fp parameter.
FP_RE = re.compile(r"^[0-9a-f]{40}$")

# The ONLY basenames the hub may write, each resolved inside RUNS_DIR before writing (spec §5).
QUEUE_FILE = ".coapply_queue.json"
HUB_STATE_FILE = ".coapply_hub_state.json"
SEEN_FILE = "_discovery_seen.txt"

# Loopback hosts only. Anything else is refused at startup (defense in depth + audit clarity).
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}

# Resolved at startup in main(); the handler reads these module globals.
RUNS_DIR = ""          # absolute, realpath'd
PLUGIN_ROOT = ""       # the plugin repo root (parent of this hub/ dir), for version files
HUB_DIR = os.path.dirname(os.path.abspath(__file__))
VISIT_BASELINE = None  # ISO date string of the PREVIOUS visit, frozen at startup → "N new"


# --------------------------------------------------------------------------- paths
def confined(*parts):
    """Resolve a path inside RUNS_DIR and assert it cannot escape (spec §5). Every write
    path and every per-slug run read goes through here, so a crafted slug/basename can never
    reach outside the runs folder."""
    p = os.path.realpath(os.path.join(RUNS_DIR, *parts))
    if p != RUNS_DIR and not p.startswith(RUNS_DIR + os.sep):
        raise ValueError(f"path escapes RUNS_DIR: {parts!r}")
    return p


# ------------------------------------------------------------------- tolerant I/O
def safe_read_json(path):
    """Read JSON, returning None on any failure (missing, unreadable, or caught mid-write).
    The ledger/run files are written incrementally by other processes; a poll must never crash
    on a torn read — it shows last-good instead (apply dashboard's `safeReadJson` discipline)."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError, ValueError):
        return None


def atomic_write_json(path, obj):
    """tmp + os.replace so a concurrent hub poll reads either the old file or the new one,
    never a half-written one (mirrors discover-surface.py's writer)."""
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)


def now_iso():
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


# ----------------------------------------------------------------------- version
def current_version():
    """Version for the footer badge (project rule: source of truth is plugin.json). Falls back
    to the top CHANGELOG entry if plugin.json is unreadable. Read-only, plugin-root-confined."""
    pj = safe_read_json(os.path.join(PLUGIN_ROOT, ".claude-plugin", "plugin.json"))
    if isinstance(pj, dict) and isinstance(pj.get("version"), str):
        return pj["version"]
    try:
        with open(os.path.join(PLUGIN_ROOT, "CHANGELOG.md"), "r", encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"^##\s*\[?v?([0-9][0-9.]*)", line)
                if m:
                    return m.group(1)
    except OSError:
        pass
    return None


# ----------------------------------------------------------------- the run folder
def derive_run_status(raw, mtime_s, now_s):
    """One status for a run, by the spec §4.4 precedence (most-committed wins). Returns one of:
    "done" | "no-go" | "running" | "in-progress"."""
    phase = str(raw.get("phase") or "").lower()
    status = str(raw.get("applicationStatus") or raw.get("status") or "").lower()
    aborted = phase == "aborted" or bool(raw.get("abortReason") or raw.get("abandoned_reason"))

    if phase == "done" and status not in NO_GO_STATUSES:
        return "done"
    if aborted or status in NO_GO_STATUSES:
        return "no-go"
    if (now_s - mtime_s) < LIVE_WINDOW_S:
        return "running"
    return "in-progress"


def normalize_run(raw, slug, mtime_s, now_s):
    """Flatten a _run.json into the shape the page renders. Tolerant of missing fields; an
    orphan run (no discoveryFp — pasted-JD or pre-discover) is normal, rendered unjoined."""
    fp = raw.get("discoveryFp")
    fp = fp if isinstance(fp, str) and FP_RE.match(fp) else None
    fit = raw.get("fitScore")
    if not isinstance(fit, (int, float)):
        try:
            fit = float(fit)
        except (TypeError, ValueError):
            fit = None
    artifacts = []
    for a in (raw.get("artifacts") or []):
        if isinstance(a, dict):
            artifacts.append({"name": a.get("name"), "status": a.get("status"),
                              "path": a.get("path")})
    return {
        "slug": slug,
        "discoveryFp": fp,                       # join key back to a surfaced job (or null = orphan)
        "company": raw.get("company"),
        "role": raw.get("role"),
        "jdUrl": raw.get("jdUrl"),
        "source": raw.get("source"),
        "mode": raw.get("mode"),
        "tier": raw.get("tier"),
        "phase": raw.get("phase"),
        "fitScore": fit,                         # bare number (no denominator — spec §11.1); page labels it
        "positioningModeChosen": raw.get("positioningModeChosen"),
        "applicationStatus": raw.get("applicationStatus"),
        "applicationStatusNote": raw.get("applicationStatusNote"),  # the human pickup note
        "abortReason": raw.get("abortReason"),
        "startedAt": raw.get("startedAt"),
        "completedAt": raw.get("completedAt"),
        "artifacts": artifacts,
        "derivedStatus": derive_run_status(raw, mtime_s, now_s),
        "mtime": mtime_s,
    }


def load_runs(now_s):
    """All runs under RUNS_DIR/runs (skip dotfiles/dirs — same as apply's loadRuns and the
    /coapply:list scanner). Reads ONLY each run's _run.json — never the multi-MB triage/fetch
    ledgers, which are discover-surface.py's inputs, not the hub's."""
    runs_root = confined("runs")
    if not os.path.isdir(runs_root):
        return []
    out = []
    try:
        entries = sorted(os.listdir(runs_root))
    except OSError:
        return []
    for name in entries:
        if name.startswith("."):
            continue
        run_json = os.path.join(runs_root, name, "_run.json")
        if not os.path.isfile(run_json):
            continue
        raw = safe_read_json(run_json)
        if not isinstance(raw, dict):
            continue
        try:
            mtime_s = os.stat(run_json).st_mtime
        except OSError:
            mtime_s = 0
        out.append(normalize_run(raw, name, mtime_s, now_s))
    # newest first by startedAt, falling back to the date-prefixed slug
    out.sort(key=lambda r: (r.get("startedAt") or r["slug"]), reverse=True)
    return out


# --------------------------------------------------------------- status derivation
# Most-committed wins when more than one run links to the same surfaced fp (rare).
_RUN_STATUS_RANK = {"done": 4, "running": 3, "in-progress": 2, "no-go": 1}


def derive_job_status(fp, run_by_fp, queued_fps, seen_fps):
    """The one status the hub shows for a surfaced job (spec §4.4 precedence):
       a linked run's state  >  queued  >  dismissed  >  new.
    Returns (status, runSlug|None). A queued job that has since gained a run auto-resolves to
    the run state — which is exactly why status can't be stored in surfaced.json."""
    runs = run_by_fp.get(fp)
    if runs:
        best = max(runs, key=lambda r: _RUN_STATUS_RANK.get(r["derivedStatus"], 0))
        return best["derivedStatus"], best["slug"]
    if fp in queued_fps:
        return "queued", None
    if fp in seen_fps:
        return "dismissed", None
    return "new", None


def load_queue():
    """The hub-written intent file. Returns (items_list, fps_set). Tolerant: a torn/missing
    file is an empty queue."""
    data = safe_read_json(confined(QUEUE_FILE))
    items = data.get("items") if isinstance(data, dict) else None
    if not isinstance(items, list):
        return [], set()
    fps = {it.get("fp") for it in items if isinstance(it, dict) and isinstance(it.get("fp"), str)}
    return items, fps


def load_seen():
    """The dismiss cache (_discovery_seen.txt): one fp per line, shared with the chat dismiss
    flow. Returns the set of dismissed fps. Tolerant of a missing file (nothing dismissed)."""
    out = set()
    try:
        with open(confined(SEEN_FILE), "r", encoding="utf-8") as fh:
            for line in fh:
                tok = line.strip()
                if FP_RE.match(tok):
                    out.add(tok)
    except OSError:
        pass
    return out


def state_mtime():
    """A single integer cache token = the newest st_mtime_ns across exactly the files that can
    change what /api/state returns: surfaced.json, the queue, the seen cache, and every
    _run.json. Used for cheap conditional polling (304 when unchanged). Deliberately excludes
    the giant triage/fetch ledgers — the hub never reads them, so they can't affect the page."""
    token = 0
    paths = [confined("surfaced.json"), confined(QUEUE_FILE), confined(SEEN_FILE)]
    runs_root = confined("runs")
    if os.path.isdir(runs_root):
        try:
            for name in os.listdir(runs_root):
                if not name.startswith("."):
                    paths.append(os.path.join(runs_root, name, "_run.json"))
        except OSError:
            pass
    for p in paths:
        try:
            token = max(token, os.stat(p).st_mtime_ns)
        except OSError:
            continue
    return token


def build_state():
    """Join surfaced jobs ↔ runs ↔ queue ↔ dismiss-cache and derive every job's status. This is
    the whole read model the page renders — assembled fresh each request (status is never stored)."""
    now_s = time.time()
    surfaced = safe_read_json(confined("surfaced.json"))
    if not isinstance(surfaced, dict):
        surfaced = {}
    jobs = surfaced.get("jobs") if isinstance(surfaced.get("jobs"), list) else []

    runs = load_runs(now_s)
    run_by_fp = {}
    for r in runs:
        if r.get("discoveryFp"):
            run_by_fp.setdefault(r["discoveryFp"], []).append(r)

    queue_items, queued_fps = load_queue()
    seen_fps = load_seen()

    out_jobs = []
    new_since = 0
    for j in jobs:
        if not isinstance(j, dict) or not isinstance(j.get("fp"), str):
            continue
        status, run_slug = derive_job_status(j["fp"], run_by_fp, queued_fps, seen_fps)
        jj = dict(j)
        jj["derivedStatus"] = status
        jj["runSlug"] = run_slug                 # draws the funnel thread to its run row
        out_jobs.append(jj)
        # "N new since last visit": firstSeenAt is date-granular, so the marker is too (spec §4.3).
        if VISIT_BASELINE and isinstance(j.get("firstSeenAt"), str) and j["firstSeenAt"] > VISIT_BASELINE:
            new_since += 1

    return {
        "schemaVersion": SCHEMA_VERSION,
        "version": current_version(),
        "mtime": str(state_mtime()),
        "generatedAt": surfaced.get("generatedAt"),
        "lastRun": surfaced.get("lastRun"),
        "categories": surfaced.get("categories") or {},
        "jobs": out_jobs,
        "runs": runs,
        "queue": queue_items,
        "newSinceLastVisit": new_since,
    }


# ------------------------------------------------------------------- write actions
def write_queue(fps):
    """Add fps to the queue (idempotent on fp). Each fp must be a valid digest AND exist in
    surfaced.json — the hub never queues a job it can't see (spec §5). Denormalized with
    url/company/title so the gate consumer acts without re-reading surfaced.json."""
    surfaced = safe_read_json(confined("surfaced.json")) or {}
    by_fp = {j["fp"]: j for j in surfaced.get("jobs", [])
             if isinstance(j, dict) and isinstance(j.get("fp"), str)}
    items, existing = load_queue()
    added = []
    for fp in fps:
        if fp in existing or fp not in by_fp:
            continue
        j = by_fp[fp]
        items.append({"fp": fp, "url": j.get("url", ""), "company": j.get("company", ""),
                      "title": j.get("title", ""), "queuedAt": now_iso(), "source": "hub"})
        existing.add(fp)
        added.append(fp)
    atomic_write_json(confined(QUEUE_FILE),
                      {"schemaVersion": SCHEMA_VERSION, "updatedAt": now_iso(), "items": items})
    return added


def remove_from_queue(fps):
    """Un-queue. Reversible before the gate consumes it (spec §7)."""
    drop = set(fps)
    items, _ = load_queue()
    kept = [it for it in items if it.get("fp") not in drop]
    removed = [it["fp"] for it in items if it.get("fp") in drop]
    atomic_write_json(confined(QUEUE_FILE),
                      {"schemaVersion": SCHEMA_VERSION, "updatedAt": now_iso(), "items": kept})
    return removed


def append_dismiss(fps):
    """Append fps to _discovery_seen.txt — the SAME cache the chat dismiss flow writes
    (discover/SKILL.md). Append-only and deduped against existing lines so it never bloats; a
    dismissed job stops resurfacing on the next discover check."""
    already = load_seen()
    new = [fp for fp in fps if fp not in already]
    if new:
        with open(confined(SEEN_FILE), "a", encoding="utf-8") as fh:
            for fp in new:
                fh.write(fp + "\n")
    return new


# ---------------------------------------------------------------------- HTTP layer
class HubHandler(BaseHTTPRequestHandler):
    server_version = "CoApplyHub"
    protocol_version = "HTTP/1.1"

    # -- helpers ----------------------------------------------------------------
    def _send_json(self, obj, code=200, extra_headers=None):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra_headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _send_status(self, code):
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _read_fps(self):
        """Parse {"fps": [...]} from a POST body, keeping only valid sha1 digests. A bad body
        yields an empty list (the action becomes a no-op, never a crash)."""
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return []
        if length <= 0 or length > 1_000_000:
            return []
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return []
        fps = data.get("fps") if isinstance(data, dict) else None
        if not isinstance(fps, list):
            return []
        seen, out = set(), []
        for fp in fps:
            if isinstance(fp, str) and FP_RE.match(fp) and fp not in seen:
                seen.add(fp)
                out.append(fp)
        return out

    def _serve_page(self):
        """Serve the one self-contained page. If it isn't built yet, a tiny placeholder keeps
        the server independently testable (this build step ships server.py before index.html)."""
        path = os.path.join(HUB_DIR, "index.html")
        try:
            with open(path, "rb") as fh:
                body = fh.read()
        except OSError:
            body = (b"<!doctype html><meta charset=utf-8><title>CoApply hub</title>"
                    b"<body style='font:14px system-ui;background:#0b0d10;color:#e6e6e6;"
                    b"padding:3rem'><h1>CoApply hub</h1><p>Server is up. "
                    b"<code>hub/index.html</code> is not built yet.</p>"
                    b"<p>Try <code>/api/state</code> or <code>/api/health</code>.</p>")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    # -- routes -----------------------------------------------------------------
    def do_GET(self):
        route = urlparse(self.path)
        p = route.path
        if p in ("/", "/index.html"):
            return self._serve_page()
        if p == "/api/health":
            return self._send_json({"ok": True, "version": current_version()})
        if p == "/api/version":
            return self._send_json({"version": current_version()})
        if p == "/api/state":
            # Conditional poll: 304 when nothing the page reads has changed since the client's
            # token, so a 4s poll is nearly free and never clobbers in-flight UI on a no-op.
            qs = parse_qs(route.query)
            since = (qs.get("since") or [None])[0]
            token = str(state_mtime())
            if since is not None and since == token:
                return self._send_status(304)
            return self._send_json(build_state(), extra_headers={"X-Hub-Mtime": token})
        return self._send_json({"error": "not found"}, code=404)

    def do_POST(self):
        p = urlparse(self.path).path
        if p == "/api/queue":
            return self._send_json({"ok": True, "added": write_queue(self._read_fps())})
        if p == "/api/queue/remove":
            return self._send_json({"ok": True, "removed": remove_from_queue(self._read_fps())})
        if p == "/api/dismiss":
            return self._send_json({"ok": True, "dismissed": append_dismiss(self._read_fps())})
        return self._send_json({"error": "not found"}, code=404)

    def log_message(self, fmt, *args):  # quiet: one concise line to stderr, no access spam
        sys.stderr.write("hub: %s\n" % (fmt % args))


# --------------------------------------------------------------------------- visit
def open_visit():
    """Freeze the PREVIOUS visit's date as the baseline for "N new since last visit", then
    record this visit. lastVisitedAt is a dotfile so /coapply:list (which scans run *directories*)
    ignores it. 'Last visit' = the last time the hub server was launched against this profile."""
    global VISIT_BASELINE
    prev = safe_read_json(confined(HUB_STATE_FILE))
    if isinstance(prev, dict) and isinstance(prev.get("lastVisitedAt"), str):
        VISIT_BASELINE = prev["lastVisitedAt"][:10]  # date portion (firstSeenAt is date-granular)
    try:
        atomic_write_json(confined(HUB_STATE_FILE),
                          {"schemaVersion": SCHEMA_VERSION, "lastVisitedAt": now_iso()})
    except OSError as e:
        sys.stderr.write(f"hub: warning: could not write hub state ({e})\n")


# ---------------------------------------------------------------------------- main
def main():
    global RUNS_DIR, PLUGIN_ROOT
    ap = argparse.ArgumentParser(description="CoApply hub server (local, read-mostly)")
    ap.add_argument("--runs-dir", required=True,
                    help="absolute path to the user's RUNS_DIR (resolved by skills/hub/SKILL.md)")
    ap.add_argument("--host", default="127.0.0.1", help="bind host (loopback only)")
    ap.add_argument("--port", type=int, default=7878, help="bind port (0 = pick a free port)")
    args = ap.parse_args()

    # Loopback-only guard. Refuse a non-loopback bind outright — the local-only invariant is not
    # negotiable, and a typo'd 0.0.0.0 must fail loudly rather than quietly expose the LAN.
    if args.host not in LOOPBACK_HOSTS:
        sys.stderr.write(f"hub: error: refusing non-loopback host {args.host!r}; "
                         f"the hub binds 127.0.0.1 only (local-only invariant)\n")
        sys.exit(2)

    RUNS_DIR = os.path.realpath(os.path.expanduser(args.runs_dir))
    if not os.path.isdir(RUNS_DIR):
        sys.stderr.write(f"hub: error: --runs-dir is not a directory: {RUNS_DIR}\n")
        sys.exit(2)
    PLUGIN_ROOT = os.path.dirname(HUB_DIR)

    open_visit()

    try:
        httpd = ThreadingHTTPServer((args.host, args.port), HubHandler)
    except OSError as e:
        # Likely the port is already taken — the launcher treats that as "reuse the running hub."
        sys.stderr.write(f"hub: error: cannot bind {args.host}:{args.port} ({e})\n")
        sys.exit(1)
    host, port = httpd.server_address[0], httpd.server_address[1]
    url = f"http://{host}:{port}/"
    sys.stderr.write(f"CoApply hub  ->  {url}  (runs: {RUNS_DIR})\n")
    print(url, flush=True)  # stdout = the URL, for the launcher to open
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("\nhub: stopped\n")


if __name__ == "__main__":
    main()
