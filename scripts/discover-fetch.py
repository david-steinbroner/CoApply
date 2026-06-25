#!/usr/bin/env python3
# CoApply — discovery spine (build step 1 of docs/features/discovery/spec.md §10).
#
# Reads the user's profile/watchlist.md, GETs each company's PUBLIC ATS board over
# plain HTTP (no browser, no auth, no aggregator scraping), paginates where the ATS
# requires it, normalizes every posting to one schema, drops anything already seen,
# and prints the result as JSON on stdout. A short human "what went out / what came
# back" receipt goes to stderr (spec §3.4) so a CLI dogfood is legible without
# parsing the JSON.
#
# This is the DETERMINISTIC spine: it has no LLM, and every network call is forced
# through a hardcoded host allowlist (point 1 of the 3-point boundary, spec §4).
# Triage/ranking is a separate script (step 2); this one only fetches.
#
# Why Python (not bash): four JSON schemas + a pagination loop + fingerprinting is a
# ~250-line Python job and a bash nightmare (spec §9 decision 5). Stdlib only — the
# project keeps a no-extra-deps stance.
#
# Usage:
#   discover-fetch.py --watchlist <path/to/watchlist.md> [--seen <ledger.txt>]
#                     [--timeout SECONDS] [--max-pages N]
#
# Stdout: {"postings": [ {company,ats,token,title,location,url,id,posted,fp}, … ],
#          "receipt":  { … inline summary, spec §3.4 … }}
# Stderr: the human-readable receipt block.
# Exit:   0 normally (a dead token / 404 / one bad board does NOT kill the run — it
#         is reported in the receipt). Non-zero only on an un-runnable input: no
#         watchlist file, an unparseable row, or a host-allowlist violation (which
#         would be an internal regression, never user input).

import argparse
import hashlib
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

# --- the boundary, point 1 of 3 (spec §4): the ONLY hosts this script may touch ---
ALLOWED_HOSTS = {
    "boards-api.greenhouse.io",
    "api.lever.co",
    "api.ashbyhq.com",  # listed now; the Ashby adapter itself lands in step 5
}

# ATSes this script knows. greenhouse+lever (step 1) and ashby (step 5) are
# implemented; workday (deferred, spec §8) is recognized-but-not-yet-fetched so a
# watchlist row for it is skipped-with-a-note rather than treated as a typo.
IMPLEMENTED = {"greenhouse", "lever", "ashby"}
PENDING = {"workday": "deferred (spec §8)"}

USER_AGENT = "CoApply-discovery/0.1 (+https://github.com/david-steinbroner/CoApply)"


def die(msg):
    """Un-runnable input — fail loud and stop."""
    sys.stderr.write(f"discover-fetch: error: {msg}\n")
    sys.exit(2)


# --------------------------------------------------------------------------- HTTP
def http_get_json(url, timeout):
    """GET a URL and parse JSON. Enforces the host allowlist on EVERY call (incl.
    pagination), so the boundary can't be bypassed by a constructed-URL regression."""
    host = urllib.parse.urlsplit(url).hostname or ""
    if host not in ALLOWED_HOSTS:
        # Internal guard: URLs are built from fixed templates below, so this only
        # trips on a code change that introduces a new host — make it loud.
        die(f"host '{host}' is not in the discovery allowlist (boundary violation)")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT,
                                               "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8", "replace")
    return json.loads(raw)


# ---------------------------------------------------------------- normalization
def _fp(ats, token, ident):
    """Fingerprint = sha1(ats|token|id) — NOT company|id. The display name is
    user-typed; fingerprinting on it means relabeling a row resurfaces every
    posting (spec §3.3). token+id is stable across edits."""
    return hashlib.sha1(f"{ats}|{token}|{ident}".encode("utf-8")).hexdigest()


def fp_from_url(url):
    """Recover (ats, token, id, fp) from a public ATS *posting* URL — the inverse of
    the normalize_*() url fields. This is the ONE place `start` reuses to stamp a run's
    `discoveryFp` (spec §3.3 single-ledger dedup): start sees only the posting URL the
    discover gate emitted, so it recomputes the SAME `sha1(ats|token|id)` here rather
    than maintaining a parallel fp scheme that could drift from fetch's.

    Posting-URL shapes (the `absolute_url`/`hostedUrl`/`jobUrl` fetch emits):
      greenhouse  boards.greenhouse.io/<token>/jobs/<id>      (also job-boards.…)
      lever       jobs.lever.co/<token>/<id>
      ashby       jobs.ashbyhq.com/<token>/<id>
    Returns a dict on a confident match, or None (a non-ATS / branded / malformed URL —
    such a run simply carries no discoveryFp, which is correct: it didn't come from the
    watchlist gate, so it shouldn't be deduped against it)."""
    parts = urllib.parse.urlsplit(url)
    host = (parts.hostname or "").lower()
    segs = [s for s in parts.path.split("/") if s]
    ats = ident = None
    if host in ("boards.greenhouse.io", "job-boards.greenhouse.io"):
        ats = "greenhouse"
        if len(segs) >= 3 and segs[1] == "jobs":   # <token>/jobs/<id>
            token, ident = segs[0], segs[2]
    elif host == "jobs.lever.co":
        ats = "lever"
        if len(segs) >= 2:                          # <token>/<id>
            token, ident = segs[0], segs[1]
    elif host == "jobs.ashbyhq.com":
        ats = "ashby"
        if len(segs) >= 2:                          # <token>/<id>
            token, ident = segs[0], segs[1]
    if ats is None or ident is None:
        return None
    ident = ident.split("?")[0]  # defensive: drop a stray query the splitter kept off path
    return {"ats": ats, "token": token, "id": ident, "fp": _fp(ats, token, ident)}


def _iso_date(value):
    """Best-effort 'YYYY-MM-DD' from the heterogeneous date fields ATSes return:
    an ISO-8601 string (Greenhouse updated_at) or epoch-millis (Lever createdAt)."""
    if value is None or value == "":
        return ""
    if isinstance(value, (int, float)):  # epoch millis
        try:
            return datetime.fromtimestamp(value / 1000, tz=timezone.utc).date().isoformat()
        except (ValueError, OSError, OverflowError):
            return ""
    s = str(value)
    m = re.match(r"(\d{4}-\d{2}-\d{2})", s)  # ISO-8601 prefix
    return m.group(1) if m else ""


class SchemaDrift(Exception):
    """A required field (title/id/url) was missing — a schema change, not a row to
    silently emit empty (spec §3.3 'fail loud on schema drift')."""


def _require(value, field, company):
    s = "" if value is None else str(value).strip()
    if not s:
        raise SchemaDrift(f"{company}: posting missing required field '{field}'")
    return s


def normalize_greenhouse(jobs, company, token):
    """Greenhouse /jobs → list[posting]. location.name may be null (spec §3.3)."""
    out = []
    for j in jobs:
        loc = j.get("location") or {}
        location = (loc.get("name") if isinstance(loc, dict) else "") or ""
        ident = _require(j.get("id"), "id", company)
        out.append({
            "company": company, "ats": "greenhouse", "token": token,
            "title": _require(j.get("title"), "title", company),
            "location": location,
            "url": _require(j.get("absolute_url"), "url", company),
            "id": ident,
            "posted": _iso_date(j.get("updated_at")),
            "fp": _fp("greenhouse", token, ident),
        })
    return out


def normalize_lever(jobs, company, token):
    """Lever postings → list[posting]. categories may be absent (spec §3.3)."""
    out = []
    for j in jobs:
        cats = j.get("categories") or {}
        location = (cats.get("location") if isinstance(cats, dict) else "") or ""
        ident = _require(j.get("id"), "id", company)
        out.append({
            "company": company, "ats": "lever", "token": token,
            "title": _require(j.get("text"), "title", company),
            "location": location,
            "url": _require(j.get("hostedUrl"), "url", company),
            "id": ident,
            "posted": _iso_date(j.get("createdAt")),
            "fp": _fp("lever", token, ident),
        })
    return out


def normalize_ashby(jobs, company, token):
    """Ashby /posting-api/job-board → list[posting]. `location` is a top-level string
    (spec §3.3). Ashby is the fetch *source* that's fragile (404 if the org didn't
    enable the public API, handled in fetch_ashby) — but once we DO have JSON, the
    schema is held to the same fail-loud standard as the others (a missing
    title/id/url is still drift, not a row to emit empty)."""
    out = []
    for j in jobs:
        ident = _require(j.get("id"), "id", company)
        out.append({
            "company": company, "ats": "ashby", "token": token,
            "title": _require(j.get("title"), "title", company),
            "location": (j.get("location") or ""),
            "url": _require(j.get("jobUrl"), "url", company),
            "id": ident,
            "posted": _iso_date(j.get("publishedAt")),
            "fp": _fp("ashby", token, ident),
        })
    return out


# ------------------------------------------------------------------- adapters
def fetch_greenhouse(token, timeout):
    """Greenhouse returns all jobs in one payload — no pagination (spec §2)."""
    url = f"https://boards-api.greenhouse.io/v1/boards/{urllib.parse.quote(token)}/jobs"
    data = http_get_json(url, timeout)
    jobs = data.get("jobs", []) if isinstance(data, dict) else []
    return jobs, [url]


def fetch_lever(token, timeout, max_pages):
    """Lever is paginated via ?skip=&limit= and will SILENTLY under-fetch a big
    board without the loop (spec §2/§3.3). Loop until a short/empty page."""
    limit = 100
    all_jobs, hosts_hit = [], []
    for page in range(max_pages):
        skip = page * limit
        url = (f"https://api.lever.co/v0/postings/{urllib.parse.quote(token)}"
               f"?mode=json&skip={skip}&limit={limit}")
        hosts_hit.append(url)
        page_jobs = http_get_json(url, timeout)
        if not isinstance(page_jobs, list):
            page_jobs = []
        all_jobs.extend(page_jobs)
        if len(page_jobs) < limit:  # last page
            break
    else:
        sys.stderr.write(f"discover-fetch: warning: hit --max-pages={max_pages} "
                         f"on lever/{token}; may be truncated\n")
    return all_jobs, hosts_hit


class AshbyUnavailable(Exception):
    """Ashby's public posting API returned 404 — the org never enabled it and the
    board is JS-rendered (spec §2: Ashby is the v1 fragility hotspot, shipped as
    'best effort, may 404'). This is the EXPECTED outcome for most orgs, not a
    failure: it's surfaced as a soft note in the receipt, never added to errors[],
    and never kills the run."""


def fetch_ashby(token, timeout):
    """Ashby returns all jobs in one payload — no pagination (spec §2). The public
    JSON API only responds if the org turned it on; otherwise it 404s (the board is
    JS-rendered). A 404 is therefore treated as 'not available' (→ AshbyUnavailable,
    a soft note), distinct from a real error like a 5xx or a JSON parse failure, which
    propagate to the generic handler (spec §2/§3.3, best-effort, 404 → skip + flag)."""
    url = f"https://api.ashbyhq.com/posting-api/job-board/{urllib.parse.quote(token)}"
    try:
        data = http_get_json(url, timeout)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            raise AshbyUnavailable(
                f"Ashby public API not enabled for '{token}' (404) — board is "
                f"JS-rendered, not reachable over plain HTTP; skipped")
        raise
    jobs = data.get("jobs", []) if isinstance(data, dict) else []
    return jobs, [url]


# ------------------------------------------------------------------ watchlist
def parse_watchlist(path):
    """Lenient markdown-table parse, fail loud on a bad row pointing at the line
    (spec §3.1). Returns list of dicts: {line, company, ats, token, filters}."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
    except FileNotFoundError:
        die(f"watchlist not found: {path}")
    except OSError as e:
        die(f"cannot read watchlist {path}: {e}")

    rows = []
    for n, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line.startswith("|"):
            continue  # prose, headings, blank lines
        cells = [c.strip() for c in line.strip("|").split("|")]
        joined = "".join(cells).lower()
        if set(joined) <= set("-: "):
            continue  # the |---|---| separator row
        if joined.startswith("company") and "ats" in joined:
            continue  # the header row
        if len(cells) < 3:
            die(f"watchlist line {n}: expected 'Company | ATS | Board id | Filters', "
                f"got {len(cells)} column(s): {line!r}")
        company, ats, token = cells[0], cells[1].lower(), cells[2]
        filters = cells[3] if len(cells) > 3 else ""
        if not company:
            die(f"watchlist line {n}: empty Company")
        if not token:
            die(f"watchlist line {n}: empty Board id for '{company}'")
        if ats not in IMPLEMENTED and ats not in PENDING:
            die(f"watchlist line {n}: unknown ATS '{ats}' for '{company}' "
                f"(expected one of: greenhouse, lever, ashby, workday)")
        rows.append({"line": n, "company": company, "ats": ats,
                     "token": token, "filters": filters})
    return rows


def load_seen(path):
    """Derived-cache ledger of already-seen fingerprints (spec §3.3). One fp per
    line; blanks/#comments ignored. Missing file = empty set (not an error). The
    union with run-folder fps is wired in step 4."""
    if not path:
        return set()
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return {ln.strip() for ln in fh
                    if ln.strip() and not ln.lstrip().startswith("#")}
    except FileNotFoundError:
        return set()
    except OSError as e:
        die(f"cannot read seen-ledger {path}: {e}")


# ----------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(add_help=True, description="CoApply discovery fetch (step 1)")
    ap.add_argument("--watchlist", help="path to profile/watchlist.md")
    ap.add_argument("--seen", default="", help="path to _discovery_seen.txt (optional)")
    ap.add_argument("--timeout", type=float, default=20.0, help="per-request timeout (s)")
    ap.add_argument("--max-pages", type=int, default=50, help="Lever pagination safety cap")
    ap.add_argument("--fp-from-url", metavar="URL",
                    help="utility mode: print ats/token/id/fp for an ATS posting URL "
                         "and exit (no network). Used by /coapply:start to stamp a "
                         "run's discoveryFp for single-ledger dedup (spec §3.3).")
    args = ap.parse_args()

    # --- utility mode: URL → fingerprint (no network, no watchlist) -------------------
    if args.fp_from_url is not None:
        info = fp_from_url(args.fp_from_url)
        if info is None:
            sys.stderr.write("discover-fetch: not a recognized ATS posting URL "
                             "(no fingerprint)\n")
            sys.exit(1)
        for k in ("ats", "token", "id", "fp"):
            sys.stdout.write(f"{k}={info[k]}\n")
        sys.exit(0)

    if not args.watchlist:
        die("--watchlist is required (or use --fp-from-url URL for fingerprint mode)")

    rows = parse_watchlist(args.watchlist)
    seen = load_seen(args.seen)

    postings, hosts, company_reports, skipped, errors = [], set(), [], [], []

    for row in rows:
        company, ats, token = row["company"], row["ats"], row["token"]
        if ats in PENDING:
            skipped.append({"company": company, "ats": ats, "reason": PENDING[ats]})
            continue
        try:
            if ats == "greenhouse":
                jobs, urls = fetch_greenhouse(token, args.timeout)
                norm = normalize_greenhouse(jobs, company, token)
            elif ats == "lever":
                jobs, urls = fetch_lever(token, args.timeout, args.max_pages)
                norm = normalize_lever(jobs, company, token)
            elif ats == "ashby":
                jobs, urls = fetch_ashby(token, args.timeout)
                norm = normalize_ashby(jobs, company, token)
            else:  # unreachable (parse_watchlist gates ats), kept for safety
                continue
        except AshbyUnavailable as e:
            # Expected for most orgs (404 = public API off) — a soft note, NOT an
            # error, so the receipt reads honestly and the run isn't flagged failed.
            company_reports.append({"company": company, "ats": ats, "fetched": 0,
                                    "new": 0, "note": str(e)})
            continue
        except SchemaDrift as e:
            company_reports.append({"company": company, "ats": ats, "fetched": 0,
                                    "new": 0, "schema_drift": str(e)})
            errors.append(str(e))
            continue
        except urllib.error.HTTPError as e:
            note = f"{company} ({ats}/{token}): HTTP {e.code}"
            company_reports.append({"company": company, "ats": ats, "fetched": 0,
                                    "new": 0, "error": note})
            errors.append(note)
            continue
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as e:
            note = f"{company} ({ats}/{token}): {type(e).__name__}: {e}"
            company_reports.append({"company": company, "ats": ats, "fetched": 0,
                                    "new": 0, "error": note})
            errors.append(note)
            continue

        for u in urls:
            hosts.add(urllib.parse.urlsplit(u).hostname or "")
        fetched = len(norm)
        fresh = [p for p in norm if p["fp"] not in seen]
        # de-dup within this run too (a paginated board can repeat a row across pages)
        uniq, run_seen = [], set()
        for p in fresh:
            if p["fp"] in run_seen:
                continue
            run_seen.add(p["fp"])
            uniq.append(p)
        postings.extend(uniq)
        company_reports.append({"company": company, "ats": ats,
                                "fetched": fetched, "new": len(uniq)})

    total_fetched = sum(c.get("fetched", 0) for c in company_reports)
    receipt = {
        "hosts": sorted(h for h in hosts if h),
        "companies": company_reports,
        "skipped_unsupported": skipped,
        "errors": errors,
        "total_fetched": total_fetched,
        "total_new": len(postings),
        "deduped": total_fetched - len(postings),
    }

    json.dump({"postings": postings, "receipt": receipt}, sys.stdout, indent=2)
    sys.stdout.write("\n")

    # --- human receipt to stderr (spec §3.4) ---
    er = sys.stderr.write
    er("\n— discovery fetch —\n")
    er(f"hosts hit: {', '.join(receipt['hosts']) or '(none)'}\n")
    for c in company_reports:
        if "schema_drift" in c:
            er(f"  ! {c['company']} ({c['ats']}): schema drift — {c['schema_drift']}\n")
        elif "error" in c:
            er(f"  ! {c['company']} ({c['ats']}): {c['error']}\n")
        elif "note" in c:
            er(f"  ~ {c['company']} ({c['ats']}): {c['note']}\n")
        else:
            er(f"  · {c['company']} ({c['ats']}): {c['fetched']} fetched, {c['new']} new\n")
    for s in skipped:
        er(f"  – {s['company']} ({s['ats']}): skipped — {s['reason']}\n")
    er(f"total: {total_fetched} fetched, {len(postings)} new "
       f"({receipt['deduped']} already seen)\n")


if __name__ == "__main__":
    main()
