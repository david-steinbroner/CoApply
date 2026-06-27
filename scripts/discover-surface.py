#!/usr/bin/env python3
# CoApply — discovery SURFACE (the hub's data spine; discover Step 4.5).
#
# Curates the run's ranked triage `kept` list into the accumulating, deduped ledger
# the hub renders: RUNS_DIR/surfaced.json. It runs on EVERY discover check (both
# watchlist and auto mode), independent of what the user picks at the gate — the
# ledger is the "surfaced universe," not just the jobs someone engaged.
#
# Why a separate deterministic script (not "the hub reads triage")?  A real auto run
# kept 1151 of 6885 postings, with 699 from ONE company and a matched-terms array
# polluted by stopwords — rendering `triage.kept` raw is the #1 failure mode every
# review lens flagged. This script is the CURATION layer: dedup+accumulate on the
# fingerprint, a per-company cap, a field-agnostic category lane derived from the user's
# own target-role phrases, and a RELEVANCE GATE that drops off-target function-noise — a
# title triage kept on a stray prose fragment (a "Full-Stack Engineer" matching "full"
# from the user's "full-stack PM") never reaches the ledger, where it would otherwise
# pollute every seniority band. It is the SAME discipline as triage — pure, no LLM,
# no network — so it inherits triage's two guarantees: no fabrication surface (every
# stored field is a real fetch field or a deterministic derivation, never model prose)
# and no network surface (it only reads/writes local JSON). See docs/features/hub/spec.md
# §4.1 for the schema and curation rules.
#
# Single-writer invariant (spec §3): discover is the ONLY writer of surfaced.json.
# Status is NOT stored here — the hub derives it read-time from the run folder + queue
# + dismiss cache (spec §4.4). Storing status would clobber-race a concurrent discover
# run. This script writes ONLY the fetch-real + first/last-seen fields.
#
# Usage:
#   discover-surface.py --triage FILE --targets "<USER_TARGETS text>"
#                       --surfaced PATH [--mode watchlist|auto]
#
# --triage:   the Step-4 output (.discovery_triage.json) — its ranked `kept` array.
# --targets:  the user's $USER_TARGETS free-text, for deriving the category lane.
# --surfaced: path to surfaced.json (read existing ledger, merge, write back atomically).
# --mode:     "watchlist" (default) | "auto" — recorded as each job's surfacedBy and the
#             ledger's lastRun.mode.
# Stdout: nothing (the artifact is the file). Stderr: a human receipt (new/updated/lanes).
# Exit:   0 normally (incl. "nothing kept" — a valid empty merge); non-zero only on an
#         un-runnable input (bad JSON, an unreadable/unwritable path).

import argparse
import importlib.util
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone

SCHEMA_VERSION = 1

# Per-company cap per run (spec §4.1): admit at most this many of a company's jobs into
# the ledger per check, by rank; the rest are counted as `moreAtCompany` overflow but
# not stored. Fixes the 699-from-one-company explosion. Already-surfaced jobs always
# re-merge (they were admitted under the cap in a prior run) and count toward the budget.
COMPANY_CAP = 8


def die(msg):
    sys.stderr.write(f"discover-surface: error: {msg}\n")
    sys.exit(2)


# ------------------------------------------------------------- shared tokenization
# Reuse discover-triage's word/stopword machinery so category matching and triage's
# title matching never drift on what counts as a "word" (same lesson as triage
# importing fetch's watchlist parser — one source of truth for a shared rule).
def _load_triage_module():
    triage_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               "discover-triage.py")
    spec = importlib.util.spec_from_file_location("discover_triage", triage_path)
    if spec is None or spec.loader is None:
        die(f"cannot locate discover-triage.py next to this script ({triage_path})")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_T = _load_triage_module()


# ------------------------------------------------------------------ category lanes
# A lane LABEL must read like a short role bucket ("UX design", "Senior PM", "data
# analyst"), not a sentence. Real profiles often write Target roles as PROSE, not a
# tidy list (the dogfood field is a full paragraph), so naively splitting on commas
# yields 30-word sentence-fragment "lanes" — the #1 thing the spec says NOT to render.
# The guard is purely STRUCTURAL (length + leading-conjunction/negation trim), so it
# stays field-agnostic: it never looks for role words, only for phrase shape.
MAX_LANE_WORDS = 5
_LEAD_DROP = {"and", "or", "also", "the", "a", "an", "plus", "with"}  # trim from the front
_NEG_LEAD = {"not", "non", "no", "never", "except", "excluding"}      # exclusion → skip the chunk


def target_phrases(targets):
    """Split the free-text $USER_TARGETS into short, human-readable role PHRASES usable
    as lane labels. Field-agnostic: the phrases are whatever discipline the user typed.
    Split on list/sentence punctuation AND parentheticals, trim leading conjunctions,
    and keep only phrases short enough to read as a bucket — longer chunks are prose,
    not labels, and are dropped (their titles fall to "uncategorized")."""
    phrases = []
    for raw in re.split(r"[,/\n;.&()—–]", targets or ""):  # em/en dash, not hyphen (hyphen joins words)
        p = raw.strip().strip('"').strip("'").strip()
        words = p.split()
        # a chunk that OPENS with a negation is an exclusion ("not a backlog PM"), not a lane
        if words and words[0].lower().strip(",.;:") in _NEG_LEAD:
            continue
        # trim a leading conjunction/article so "and builder roles" → "builder roles"
        while words and words[0].lower().strip(",.;:") in _LEAD_DROP:
            words = words[1:]
        p = " ".join(words)
        if not p or len(words) > MAX_LANE_WORDS:
            continue
        if p not in phrases:
            phrases.append(p)
    return phrases


def _phrase_terms(phrase):
    """Significant (non-stopword) singularized words of a phrase — the words that, if
    present in a title, mean the title belongs to that lane."""
    return [w for w in _T._words(phrase)
            if w not in _T.STOPWORDS and len(w) >= 2]


# Generic org / seniority / structure words. These describe a job's LEVEL or shape in
# EVERY discipline — they never name the discipline itself ("manager", "senior", "lead"
# fit a nurse, an accountant, or a PM alike). They are field-agnostic by construction:
# the list contains no role NOUN (no "product", "nursing", "sales"). We strip them from a
# lane phrase before matching so a title can only join a lane on a CONTENT word — the part
# that names the actual function. Without this, "Vulnerability Management Engineer" lands
# in a "...management..." lane on the bare word "management", and every "Senior X" title
# matches every "Senior …" phrase. (Same structural-guard philosophy as MAX_LANE_WORDS:
# we look at word ROLE, never at field.) Seeds run through the same _words() pipeline that
# produces phrase terms, so the singularized forms line up for membership tests.
_GENERIC_SEEDS = (
    "senior sr junior jr entry lead leads principal staff associate intern internship "
    "graduate apprentice trainee chief head executive officer president vice vp svp evp "
    "director directors manager managers management supervisor coordinator specialist "
    "generalist administrator assistant deputy "
    "role roles position positions opening openings opportunity team teams group groups "
    "global regional national member members level"
).split()
GENERIC_ROLE_WORDS = {w for s in _GENERIC_SEEDS for w in _T._words(s)}


def _content_terms(phrase):
    """The discipline-naming (content) words of a phrase: its significant words minus the
    generic org/seniority words above. These are what a title must share to belong to the
    lane. Falls back to ALL significant words when a phrase is entirely generic (e.g. a
    user who literally typed "senior manager"), so such a phrase still matches something."""
    sig = _phrase_terms(phrase)
    content = [w for w in sig if w not in GENERIC_ROLE_WORDS]
    return content or sig


def categorize(title, phrase_terms_by_phrase):
    """Best-matching target-role phrase for a title (spec §4.1, decision §11.2), or
    "uncategorized". Score = count of a phrase's significant words present in the title
    (word-boundary, via triage's `_present`). Most words wins; ties → the more specific
    (more-significant-word) phrase, then the earliest listed. Default "uncategorized"
    when nothing overlaps — never invents a field."""
    t_words = set(_T._words(title))
    t_join = " ".join(_T._words(title))
    best_label, best_score, best_specificity = "uncategorized", 0, 0
    for label, terms in phrase_terms_by_phrase:
        if not terms:
            continue
        score = sum(1 for term in terms if _T._present(term, t_words, t_join))
        if score == 0:
            continue
        if score > best_score or (score == best_score and len(terms) > best_specificity):
            best_label, best_score, best_specificity = label, score, len(terms)
    return best_label


# ------------------------------------------------------------------ I/O (tolerant)
def load_triage_kept(path):
    """Read Step-4's ranked `kept` array. Fail loud on unparseable JSON (un-runnable)."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except FileNotFoundError:
        die(f"triage file not found: {path} — run discover-triage.py first")
    except OSError as e:
        die(f"cannot read triage file {path}: {e}")
    if not raw.strip():
        die(f"triage file is empty: {path}")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        die(f"triage file is not valid JSON: {e}")
    kept = data.get("kept") if isinstance(data, dict) else None
    if not isinstance(kept, list):
        die("triage JSON must be an object with a 'kept' list")
    return kept


def load_ledger(path):
    """Read the existing surfaced.json if present. TOLERANT: a missing file is a fresh
    ledger; a corrupt/half-written file is reported and treated as fresh rather than
    crashing a discover run (we never want surfacing to be what fails a check). The
    pre-existing jobs are still preserved whenever the file parses."""
    if not os.path.exists(path):
        return {"jobs": []}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        sys.stderr.write(f"discover-surface: warning: could not read existing "
                         f"{os.path.basename(path)} ({e}); starting a fresh ledger\n")
        return {"jobs": []}
    if not isinstance(data, dict) or not isinstance(data.get("jobs"), list):
        sys.stderr.write("discover-surface: warning: existing ledger has an unexpected "
                         "shape; starting a fresh ledger\n")
        return {"jobs": []}
    return data


def write_atomic(path, obj):
    """Write JSON atomically (tmp + os.replace) so a hub poll never reads a half-written
    ledger — it sees either the old file or the new one, never a torn one (spec §3, §5)."""
    tmp = f"{path}.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(obj, fh, indent=2)
            fh.write("\n")
        os.replace(tmp, path)
    except OSError as e:
        die(f"cannot write surfaced ledger {path}: {e}")


# ------------------------------------------------------------------ the merge
def merge(kept, existing_ledger, phrase_terms, mode, now):
    """Dedup+accumulate the ranked `kept` list into the ledger (spec §4.1 curation)."""
    today = now.date().isoformat()
    run_id = now.isoformat(timespec="seconds")

    existing = {}
    for j in existing_ledger.get("jobs", []):
        fp = j.get("fp")
        if isinstance(fp, str):
            existing[fp] = j
    # The ledger ACCUMULATES, but it is CURATED, not a dump: a surfaced role must match at
    # least one of the user's target-role phrases on a content word (categorize != it falls
    # to "uncategorized"). Off-target titles — triage kept them on a stray prose fragment
    # ("full" from "full-stack", "builder", "matter") and they otherwise pollute every
    # seniority band — are NOT surfaced. So we build the result from scratch and gate each
    # admission, rather than carrying the whole prior ledger forward verbatim. This is the
    # relevance gate (spec §4.1); it is field-agnostic — the only inputs are the user's own
    # phrases and the generic-word list. n_dropped is reported in the receipt (no silent cut).
    result = {}
    seen_in_run = set()        # fps handled by this check (so pass B skips them)
    n_dropped = 0              # off-target roles not surfaced (this run + tidied legacy)

    by_company = defaultdict(list)
    for j in kept:
        if not isinstance(j.get("fp"), str):
            continue  # a fetch-real job always has an fp; skip anything malformed
        by_company[j.get("company", "")].append(j)

    n_new = n_updated = 0
    capped = []  # (company, overflow) for the receipt

    # Pass A — this check's ranked `kept`, per company under the cap, through the gate.
    for company, jobs in by_company.items():
        jobs.sort(key=lambda j: j.get("rank", 1 << 30))  # rank 1 = best
        already = [j for j in jobs if j["fp"] in existing]
        fresh = [j for j in jobs if j["fp"] not in existing]
        slots = max(0, COMPANY_CAP - len(already))
        admit_fresh = fresh[:slots]
        overflow = len(fresh) - len(admit_fresh)
        if overflow:
            capped.append((company, overflow))

        for j in already + admit_fresh:
            seen_in_run.add(j["fp"])
            category = categorize(j.get("title", ""), phrase_terms)
            if category == "uncategorized":
                n_dropped += 1
                continue  # off-target — matched no target-role phrase; do not surface
            prior = existing.get(j["fp"])
            if prior is None:
                result[j["fp"]] = {
                    "fp": j["fp"],
                    "company": j.get("company", ""),
                    "ats": j.get("ats", ""),
                    "token": j.get("token", ""),
                    "id": j.get("id", ""),
                    "title": j.get("title", ""),
                    "location": j.get("location", "") or "",
                    "url": j.get("url", ""),
                    "posted": j.get("posted"),
                    "category": category,
                    "matched": j.get("matched", []),
                    "rankAtLastSeen": j.get("rank"),
                    "surfacedBy": mode,
                    "firstSeenAt": today,
                    "lastSeenAt": today,
                    "timesSeen": 1,
                    "lastSeenRunId": run_id,
                    "moreAtCompany": overflow,
                    "openState": "open",
                }
                n_new += 1
            else:
                # Preserve unknown/forward-compat fields + firstSeenAt + surfacedBy.
                rec = dict(prior)
                rec.update({
                    "company": j.get("company", rec.get("company", "")),
                    "title": j.get("title", rec.get("title", "")),
                    "location": j.get("location", "") or "",
                    "url": j.get("url", rec.get("url", "")),
                    "posted": j.get("posted", rec.get("posted")),
                    "category": category,
                    "matched": j.get("matched", []),
                    "rankAtLastSeen": j.get("rank"),
                    "lastSeenAt": today,
                    "timesSeen": int(rec.get("timesSeen", 1)) + 1,
                    "lastSeenRunId": run_id,
                    "moreAtCompany": overflow,
                    "openState": "open",
                })
                result[j["fp"]] = rec
                n_updated += 1

    # Pass B — carry forward previously-surfaced jobs this check didn't touch, re-gated
    # under the CURRENT logic. This tidies legacy noise: a job that only ever matched on a
    # generic word (or a prose fragment) is now dropped, and a carried job's lane is
    # refreshed so a stricter categorization takes effect across the whole ledger.
    for fp, j in existing.items():
        if fp in seen_in_run:
            continue
        category = categorize(j.get("title", ""), phrase_terms)
        if category == "uncategorized":
            n_dropped += 1
            continue
        carried = dict(j)
        carried["category"] = category
        result[fp] = carried

    jobs_out = list(result.values())
    # Lane counts over the WHOLE ledger, for the hub's lane headers (spec §4.1).
    categories = defaultdict(int)
    for j in jobs_out:
        categories[j.get("category", "uncategorized")] += 1

    ledger = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": run_id,
        "lastRun": {
            "at": run_id,
            "mode": mode,
            # boardsFetchedOK / boardsErrored are recorded once openState close-
            # reconciliation lands (spec §9, v1.1). v1 surfaces open/unknown only.
            "boardsFetchedOK": [],
            "boardsErrored": [],
        },
        "categories": dict(categories),
        "jobs": jobs_out,
    }
    stats = {"new": n_new, "updated": n_updated, "total": len(jobs_out),
             "capped": capped, "dropped": n_dropped, "categories": dict(categories)}
    return ledger, stats


def main():
    ap = argparse.ArgumentParser(add_help=True,
                                 description="CoApply discovery surface (Step 4.5)")
    ap.add_argument("--triage", required=True,
                    help="Step-4 output (.discovery_triage.json) with the 'kept' array")
    ap.add_argument("--targets", required=True,
                    help="the user's $USER_TARGETS free-text (for category lanes)")
    ap.add_argument("--surfaced", required=True,
                    help="path to surfaced.json (read + merge + write back)")
    ap.add_argument("--mode", default="watchlist", choices=["watchlist", "auto"],
                    help="how these were surfaced (recorded as surfacedBy / lastRun.mode)")
    args = ap.parse_args()

    kept = load_triage_kept(args.triage)
    phrases = target_phrases(args.targets)
    # Match on each phrase's CONTENT words (discipline-naming), not its generic org words,
    # so a title joins a lane only on the part that names the function (see _content_terms).
    phrase_terms = [(p, _content_terms(p)) for p in phrases]
    existing_ledger = load_ledger(args.surfaced)
    now = datetime.now(timezone.utc).astimezone()  # local tz, ISO offset (spec examples)

    ledger, stats = merge(kept, existing_ledger, phrase_terms, args.mode, now)
    write_atomic(args.surfaced, ledger)

    # --- human receipt to stderr (mirrors the other discover scripts, spec §3.4) ---
    er = sys.stderr.write
    er("\n— discovery surface —\n")
    er(f"mode: {args.mode}   merged: {stats['new']} new, {stats['updated']} updated   "
       f"ledger now holds {stats['total']} surfaced job(s)\n")
    if stats["dropped"]:
        er(f"  · dropped {stats['dropped']} off-target role(s) "
           f"(matched no target-role phrase on a content word)\n")
    if stats["capped"]:
        for company, overflow in sorted(stats["capped"], key=lambda c: -c[1]):
            er(f"  · capped {company}: +{overflow} more not surfaced "
               f"(showing top {COMPANY_CAP})\n")
    lanes = sorted(stats["categories"].items(), key=lambda kv: -kv[1])
    if lanes:
        er("  lanes: " + ", ".join(f"{label} ({n})" for label, n in lanes) + "\n")
    er(f"wrote {args.surfaced}\n")


if __name__ == "__main__":
    main()
