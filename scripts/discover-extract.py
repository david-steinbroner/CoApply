#!/usr/bin/env python3
# CoApply — discovery-auto extract (build step 2 of
# docs/features/discovery-auto/spec.md §9).
#
# Sits between the search and the EXISTING fetch spine: takes the raw result URLs a
# WebSearch (Path A) returned for the querygen strings, and distills them to the unique
# (ats, token) pairs of the companies whose first-party ATS boards surfaced. Those
# tokens become an ephemeral, in-memory watchlist the orchestrator feeds straight into
# discover-fetch.py → discover-triage.py → gate — unchanged from 0.7.1.
#
# DETERMINISTIC and OFFLINE: no network, no LLM (the same property the audit asserts
# for triage — spec §6). We never treat a search snippet/title as job data; a result is
# only ever a *source of a token*, and we then fetch the company's own board. To keep
# this script genuinely offline (not offline-by-convention), it parses URLs with plain
# string ops and imports NO urllib/http/socket module — exactly how discover-resolve.sh
# classifies a URL with parameter expansion. (Importing discover-fetch.py for its
# fp_from_url would pull network-capable code into scope; the boundary is about
# capability, so we mirror its host→ats map and path rules here instead, and the
# step-4 audit pins the two together with a cross-check on a sample URL.)
#
# THE BOUNDARY (spec §4): two guards live here.
#   1. ATS-only — emit ONLY tokens on a known public ATS board host (greenhouse /
#      lever / ashby). A result pointing anywhere else is silently dropped, so a
#      generic web index can never feed a non-first-party URL into fetch.
#   2. Noise denylist — a tiny, generic, user-overridable set of known reposter /
#      staffing tokens (e.g. jobgether) that operate an ATS board but aggregate other
#      employers' jobs. Infrastructure-level, NOT a curated company blocklist — the
#      same shape as the vendor allowlist (spec §3.2 / caveat 2).
#
# Usage:
#   discover-extract.py [--urls FILE]            # default: read URLs from stdin
#                       [--denylist FILE]        # extra reposter tokens (one/line)
#                       [--no-default-denylist]  # start from an empty denylist
#
#   Input is newline-delimited result URLs (blank lines and #comments ignored). Each
#   line is scanned for the first http(s):// URL, so a "title — https://…" line from a
#   search receipt is tolerated.
#
# Stdout (JSON, mirrors fetch/triage/querygen style):
#   {"tokens": [{"ats","token","url"}, …], "allowed_hosts": [...], "receipt": {…}}
#     - tokens : unique (ats, token) pairs, first-seen order; `url` is the first
#                source URL that yielded it (legibility/debug only).
# Stderr: a short human "what came in / what I kept" receipt (spec §3.4 legibility).
# Exit:   0 normally, including a zero-token result (an empty/no-ATS search is a valid
#         outcome, not an error — mirrors querygen). Non-zero (2) only on un-runnable
#         input: an unreadable --urls or --denylist file.

import argparse
import json
import re
import sys

# --- host → ATS for the FRONT-FACING board/posting hosts a public web index returns
# (NOT the api.* hosts discover-fetch.py GETs). This MIRRORS discover-fetch.py's
# fp_from_url host map and discover-querygen.py's ATS_BOARD_HOSTS; the step-4 audit
# cross-checks extract against `discover-fetch.py --fp-from-url` on a sample URL so the
# two parses can't drift. Corpus, not field: the same GH/Lever/Ashby vendors the rest
# of discovery already scopes to. ---
BOARD_HOST_ATS = {
    "boards.greenhouse.io": "greenhouse",
    "job-boards.greenhouse.io": "greenhouse",
    "jobs.lever.co": "lever",
    "jobs.ashbyhq.com": "ashby",
}

# Greenhouse serves a few non-company first path segments (the embeddable widget lives
# at /embed/…). Skip them so they never masquerade as a board token. Structural, not a
# company judgement — distinct from the reposter denylist below.
GH_RESERVED_FIRST_SEG = {"embed"}

# --- noise guard (spec §3.2): a TINY, generic, user-overridable default. These are
# reposters/aggregators that run their own ATS board but list other employers' jobs, so
# their token is never a real first-party employer. Infrastructure-level — kept
# deliberately minimal (not a curated company list); users extend it with --denylist. ---
DEFAULT_DENYLIST = {"jobgether"}

# First http(s):// URL on a line, read up to whitespace — tolerates a result line that
# carries a title/snippet alongside the URL.
_URL_RE = re.compile(r"https?://\S+")


def die(msg):
    """Un-runnable input — fail loud and stop (mirrors the other discovery scripts)."""
    sys.stderr.write(f"discover-extract: error: {msg}\n")
    sys.exit(2)


def split_url(url):
    """(host, [path segments]) from a URL with pure string ops — no urllib, so this
    script stays provably offline (boundary, spec §6). Strips scheme, userinfo, port,
    query and fragment. Returns None if there's no scheme (a bare host is ambiguous and
    we'd rather drop than guess)."""
    if "://" not in url:
        return None
    rest = url.split("://", 1)[1]
    host, _, path = rest.partition("/")
    host = host.split("@")[-1]        # strip any user:pass@
    host = host.split(":")[0].lower()  # strip :port, normalize case
    path = path.split("?", 1)[0].split("#", 1)[0]  # drop query/fragment
    segs = [s for s in path.split("/") if s]
    return host, segs


def classify(url):
    """A public ATS board/posting URL → {ats, token}, else None. Mirrors
    discover-fetch.py fp_from_url's host map and path rules, but only needs (ats,
    token): the board id is always the first path segment, whether the URL is a board
    root (/<token>) or a deep posting link.

      greenhouse  board /<token>  ·  posting /<token>/jobs/<id>
      lever       /<token>[/<id>[/apply]]
      ashby       /<token>[/<id>]

    For greenhouse we keep fp_from_url's `jobs` discrimination so an /embed/job_app
    widget URL (token hidden in a ?for= query we deliberately don't read) is dropped
    rather than emitted as the bogus token 'embed'/'job_app'. Lever and Ashby always
    lead the path with the token, so the first segment is taken directly."""
    parsed = split_url(url)
    if parsed is None:
        return None
    host, segs = parsed
    ats = BOARD_HOST_ATS.get(host)
    if ats is None or not segs:        # non-ATS host, or no board id in the path
        return None

    if ats == "greenhouse":
        if len(segs) == 1 and segs[0] not in GH_RESERVED_FIRST_SEG:
            token = segs[0]            # board root
        elif len(segs) >= 3 and segs[1] == "jobs":
            token = segs[0]            # posting
        else:
            return None                # embed / unrecognized shape
    else:                              # lever / ashby — token leads the path
        token = segs[0]

    token = token.strip()
    return {"ats": ats, "token": token} if token else None


def load_denylist(path, use_default):
    """Reposter/staffing token denylist: the generic default (unless suppressed) plus
    any user-supplied tokens (one per line, blanks/#comments ignored). Lowercased for
    case-insensitive matching against a board token."""
    deny = set(DEFAULT_DENYLIST) if use_default else set()
    if path:
        try:
            with open(path, "r", encoding="utf-8") as fh:
                for ln in fh:
                    t = ln.strip()
                    if t and not t.startswith("#"):
                        deny.add(t.lower())
        except FileNotFoundError:
            die(f"denylist file not found: {path}")
        except OSError as e:
            die(f"cannot read denylist {path}: {e}")
    return {t.lower() for t in deny}


def read_urls(path):
    """Newline-delimited URLs from a file or stdin. Each non-blank, non-#comment line
    is scanned for its first http(s):// URL (tolerates 'title — https://…' lines)."""
    if path:
        try:
            with open(path, "r", encoding="utf-8") as fh:
                lines = fh.readlines()
        except FileNotFoundError:
            die(f"urls file not found: {path}")
        except OSError as e:
            die(f"cannot read urls {path}: {e}")
    else:
        lines = sys.stdin.readlines()

    urls = []
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = _URL_RE.search(line)
        if m:
            urls.append(m.group(0))
    return urls


def main():
    ap = argparse.ArgumentParser(
        add_help=True, description="CoApply discovery-auto extract (step 2)")
    ap.add_argument("--urls", default="",
                    help="file of newline-delimited result URLs (default: stdin)")
    ap.add_argument("--denylist", default="",
                    help="file of extra reposter/staffing tokens to drop (one/line)")
    ap.add_argument("--no-default-denylist", action="store_true",
                    help="start from an empty denylist (drop the built-in default)")
    args = ap.parse_args()

    denylist = load_denylist(args.denylist, not args.no_default_denylist)
    urls = read_urls(args.urls)

    tokens, seen = [], set()
    classified = dropped_non_ats = 0
    denied = []  # [(ats, token)] dropped by the denylist (deduped)
    denied_seen = set()

    for url in urls:
        info = classify(url)
        if info is None:
            dropped_non_ats += 1       # boundary guard 1: non-ATS / unparseable → drop
            continue
        classified += 1
        key = (info["ats"], info["token"])
        if info["token"].lower() in denylist:   # boundary guard 2: reposter noise
            if key not in denied_seen:
                denied_seen.add(key)
                denied.append({"ats": info["ats"], "token": info["token"]})
            continue
        if key in seen:
            continue                   # dedup (ats, token)
        seen.add(key)
        tokens.append({"ats": info["ats"], "token": info["token"], "url": url})

    receipt = {
        "urls_in": len(urls),
        "classified": classified,
        "dropped_non_ats": dropped_non_ats,
        "denylisted": denied,
        "unique_tokens": len(tokens),
        "denylist": sorted(denylist),
    }

    json.dump({"tokens": tokens,
               "allowed_hosts": sorted(BOARD_HOST_ATS),
               "receipt": receipt}, sys.stdout, indent=2)
    sys.stdout.write("\n")

    # --- human receipt to stderr (spec §3.4) ---
    er = sys.stderr.write
    er("\n— discovery-auto extract —\n")
    er(f"urls in: {len(urls)}    on a known ATS board: {classified}    "
       f"dropped (non-ATS): {dropped_non_ats}\n")
    for t in tokens:
        er(f"  → {t['ats']}/{t['token']}\n")
    for d in denied:
        er(f"  – {d['ats']}/{d['token']}: dropped (reposter denylist)\n")
    er(f"unique tokens: {len(tokens)}\n")


if __name__ == "__main__":
    main()
