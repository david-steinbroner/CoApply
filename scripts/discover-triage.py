#!/usr/bin/env python3
# CoApply — discovery triage (build step 2 of docs/features/discovery/spec.md §10).
#
# Reads step-1's normalized posting JSON, ranks each posting by how well its TITLE
# matches the user's target roles, applies the watchlist row's optional Filters, and
# emits a KEEP/DROP verdict with a purely DESCRIPTIVE reason that quotes real fields
# only. The orchestrator (step 4) renders the KEEP list as the human go/no-go gate.
#
# This is the spec's DETERMINISTIC default (§5): no LLM, no network. Both brains-trust
# reviewers judged an LLM triage over-engineered — the data in hand is mostly titles,
# and title-matching is not "the unknown." A pure ranker also has **no fabrication
# surface** (no model writing "great fit for your background") and **no network
# surface** (point 3 of the 3-point boundary, §4 — a script that can't WebFetch).
# Its honest limit (missing exotic title aliasing, e.g. an unusual name for a common
# role) is exactly the dogfood signal that would justify the opt-in LLM re-rank (§8).
#
# Matching (§5):
#   - Tokenize $USER_TARGETS into significant terms (seniority/filler words dropped),
#     match each case-insensitively on a word boundary against the title.
#   - Optionally expand via a user-extensible synonyms file (the engine ships NONE —
#     synonyms are field-specific, so they stay profile-side and field-agnostic here).
#   - Apply the row's Filters: `location:` substring-gates the posting location,
#     `keywords:` OR-gates the title. A failed gate is a DROP with a field-quoting why.
#   - KEEP needs at least one target match AND all row gates passed. Rank KEEPs by the
#     number of distinct target terms matched, then recency.
#
# Usage:
#   discover-triage.py --targets "<USER_TARGETS text>" [--postings FILE|-]
#                      [--watchlist PATH] [--synonyms PATH]
#
# Stdin/--postings: step-1 output ({"postings":[…]}) or a bare list of postings.
# Stdout: {"kept":[…ranked…], "dropped":[…], "summary":{…}}.
# Stderr: a light human summary (mirrors fetch's receipt, spec §3.4).
# Exit:   0 normally; non-zero only on un-runnable input (no targets, bad JSON, an
#         unreadable file) — never on "nothing matched" (that's a valid empty result).

import argparse
import importlib.util
import json
import os
import re
import sys

# --- target tokenization: words to drop so the FIELD terms survive (spec §5) -------
# Seniority + filler + generic job-posting nouns. These are field-agnostic: stripping
# them from "<level> <field> roles" leaves the discipline terms that actually match a
# title. Role nouns that can BE the discipline (manager, director, engineer, …) are
# deliberately NOT here — they earn matches.
STOPWORDS = {
    "senior", "sr", "junior", "jr", "mid", "midlevel", "entry", "level", "lead",
    "principal", "staff", "associate", "intern", "internship", "trainee",
    "vp", "svp", "evp", "chief", "head", "exec", "executive",
    "role", "roles", "position", "positions", "job", "jobs", "opening", "openings",
    "opportunity", "opportunities", "career", "careers",
    "the", "a", "an", "and", "or", "of", "for", "in", "to", "with", "at", "on",
    "my", "your", "any", "some", "ideal", "preferred", "eg", "etc", "ie",
}

# Words on a title or target are compared after this light, field-neutral fold so
# trivial plurals line up ("managers"~"manager", "analysts"~"analyst"). Intentionally
# NOT a stemmer — bridging deeper morphology (manage/manager/management) is exactly
# the aliasing the spec leaves to the opt-in LLM re-rank (§5 "honest limit").
def _singular(word):
    if len(word) > 3 and word.endswith("s") and not word.endswith("ss"):
        return word[:-1]
    return word


_WORD_RE = re.compile(r"[a-z0-9]+")


def _words(text):
    """Lowercase → list of singularized word tokens (word-boundary by construction)."""
    return [_singular(w) for w in _WORD_RE.findall((text or "").lower())]


def _present(term, word_set, joined):
    """Is `term` (already normalized) present? Single word → set membership; multi-word
    phrase → word-boundary search over the joined, singularized title string."""
    if " " in term:
        pat = r"\b" + r"\s+".join(re.escape(t) for t in term.split()) + r"\b"
        return re.search(pat, joined) is not None
    return term in word_set


def die(msg):
    sys.stderr.write(f"discover-triage: error: {msg}\n")
    sys.exit(2)


# ------------------------------------------------------------------ targets/synonyms
def target_terms(targets):
    """Significant, singularized terms from the free-text $USER_TARGETS string."""
    terms = []
    for w in _words(targets):
        if w in STOPWORDS or len(w) < 2:
            continue
        if w not in terms:
            terms.append(w)
    return terms


def load_synonyms(path):
    """Optional user-extensible synonym groups (engine ships none — field-agnostic).
    Each non-blank, non-# line is a comma-separated group of equivalent terms; any
    member appearing in the title counts as matching the group when a (possibly
    different) member also appears in $USER_TARGETS. Terms may be multi-word."""
    if not path:
        return []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
    except FileNotFoundError:
        die(f"synonyms file not found: {path}")
    except OSError as e:
        die(f"cannot read synonyms file {path}: {e}")
    groups = []
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        members = []
        for part in line.split(","):
            norm = " ".join(_words(part))  # singularize each word in the phrase
            if norm and norm not in members:
                members.append(norm)
        if len(members) >= 2:
            groups.append(members)
    return groups


# ------------------------------------------------------------------ row filters
def parse_filters(text):
    """Parse the watchlist Filters cell: free-text `key: value; key: value` (spec §3.1).
    Recognized keys: `location:` (one substring) and `keywords:` (OR'd list). Unknown
    keys are ignored (lenient). Returns {"location": str|None, "keywords": [terms]}."""
    out = {"location": None, "keywords": []}
    for clause in (text or "").split(";"):
        clause = clause.strip()
        if ":" not in clause:
            continue
        key, _, value = clause.partition(":")
        key, value = key.strip().lower(), value.strip()
        if not value:
            continue
        if key == "location":
            out["location"] = value
        elif key in ("keyword", "keywords"):
            out["keywords"] = [t for t in re.split(r"[,\s]+", value.lower()) if t]
    return out


def load_watchlist_filters(path):
    """Map (ats, token) → parsed-filters, reusing step-1's lenient/fail-loud watchlist
    parser so the two scripts never drift on what a valid row is (spec §3.3's
    one-source-of-truth lesson, applied to the parser). Optional: no watchlist → no
    per-row filters, just target matching."""
    if not path:
        return {}
    fetch_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "discover-fetch.py")
    spec = importlib.util.spec_from_file_location("discover_fetch", fetch_path)
    if spec is None or spec.loader is None:
        die(f"cannot locate discover-fetch.py next to this script ({fetch_path})")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    rows = mod.parse_watchlist(path)  # fails loud on a bad row, exactly as fetch does
    return {(r["ats"], r["token"]): parse_filters(r["filters"]) for r in rows}


# ------------------------------------------------------------------ the ranker
def match_title(title, terms, syn_groups, targets_words, targets_join):
    """Distinct, descriptive labels matched in `title` — target terms first, then any
    synonym groups whose membership straddles both the targets and the title."""
    t_words = set(_words(title))
    t_join = " ".join(_words(title))
    matched = []
    for t in terms:
        if _present(t, t_words, t_join) and t not in matched:
            matched.append(t)
    for group in syn_groups:
        in_targets = any(_present(m, targets_words, targets_join) for m in group)
        if not in_targets:
            continue
        if any(_present(m, t_words, t_join) for m in group):
            label = group[0]  # canonical = first listed member
            if label not in matched:
                matched.append(label)
    return matched


def triage(postings, terms, syn_groups, filters_by_key):
    targets_words = set(terms)
    targets_join = " ".join(terms)
    targets_label = ", ".join(terms) if terms else "(none set)"
    kept, dropped = [], []
    n_loc, n_kw, n_target = 0, 0, 0

    for p in postings:
        title = p.get("title", "")
        location = p.get("location", "") or ""
        flt = filters_by_key.get((p.get("ats"), p.get("token")),
                                 {"location": None, "keywords": []})

        # --- hard gates first: a row Filter is an explicit user signal (spec §3.1) ---
        loc_filter = flt.get("location")
        if loc_filter and loc_filter.lower() not in location.lower():
            n_loc += 1
            shown = f'"{location}"' if location else "no location listed"
            dropped.append({**p, "verdict": "DROP", "matched": [],
                            "reason": f'{shown} does not match your '
                                      f'"{loc_filter}" location filter'})
            continue

        kw_filter = flt.get("keywords") or []
        if kw_filter:
            tw = set(_words(title))
            tj = " ".join(_words(title))
            if not any(_present(_singular(k), tw, tj) for k in kw_filter):
                n_kw += 1
                dropped.append({**p, "verdict": "DROP", "matched": [],
                                "reason": f'title "{title}" matches none of the row '
                                          f'keywords ({", ".join(kw_filter)})'})
                continue

        # --- target/synonym title match ---
        matched = match_title(title, terms, syn_groups, targets_words, targets_join)
        if not terms:
            # No targets configured: don't silently drop everything — surface all that
            # cleared the row gates and let the human decide (engine never invents one).
            kept.append({**p, "verdict": "KEEP", "matched": [],
                         "reason": "no target roles set — showing all postings that "
                                   "passed the row filters"})
            continue
        if not matched:
            n_target += 1
            dropped.append({**p, "verdict": "DROP", "matched": [],
                            "reason": f'title "{title}" matches none of your target '
                                      f'terms ({targets_label})'})
            continue

        reason = f'title "{title}" matches your target term(s) {", ".join(matched)}'
        if loc_filter:
            reason += f'; location "{location}" matches your "{loc_filter}" filter'
        kept.append({**p, "verdict": "KEEP", "matched": matched, "reason": reason})

    # rank: most target terms matched first, then most-recent first (empty date last)
    kept.sort(key=lambda p: (p.get("posted") or ""), reverse=True)
    kept.sort(key=lambda p: len(p.get("matched", [])), reverse=True)
    for i, p in enumerate(kept, 1):
        p["rank"] = i

    summary = {
        "targets": terms,
        "kept": len(kept),
        "dropped": len(dropped),
        "dropped_by_location_filter": n_loc,
        "dropped_by_keyword_filter": n_kw,
        "dropped_no_target_match": n_target,
        "total": len(postings),
    }
    return {"kept": kept, "dropped": dropped, "summary": summary}


# ------------------------------------------------------------------ I/O
def load_postings(path):
    """Read step-1 output from a file or stdin. Accepts the {"postings":[…]} object or
    a bare list. Fail loud on unparseable JSON — that's an un-runnable input."""
    try:
        if path in ("", "-", None):
            raw = sys.stdin.read()
        else:
            with open(path, "r", encoding="utf-8") as fh:
                raw = fh.read()
    except FileNotFoundError:
        die(f"postings file not found: {path}")
    except OSError as e:
        die(f"cannot read postings {path}: {e}")
    if not raw.strip():
        die("no postings input (empty stdin/file) — run discover-fetch.py first")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        die(f"postings input is not valid JSON: {e}")
    if isinstance(data, dict):
        data = data.get("postings", [])
    if not isinstance(data, list):
        die("postings JSON must be a list or an object with a 'postings' list")
    return data


def main():
    ap = argparse.ArgumentParser(add_help=True,
                                 description="CoApply discovery triage (step 2)")
    ap.add_argument("--targets", required=True,
                    help="the user's $USER_TARGETS free-text (target roles)")
    ap.add_argument("--postings", default="-",
                    help="step-1 JSON file, or '-' for stdin (default)")
    ap.add_argument("--watchlist", default="",
                    help="path to profile/watchlist.md (for per-row Filters; optional)")
    ap.add_argument("--synonyms", default="",
                    help="path to a user synonyms file (optional; engine ships none)")
    args = ap.parse_args()

    postings = load_postings(args.postings)
    terms = target_terms(args.targets)
    syn_groups = load_synonyms(args.synonyms)
    filters_by_key = load_watchlist_filters(args.watchlist)

    result = triage(postings, terms, syn_groups, filters_by_key)

    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")

    # --- light human summary to stderr (mirrors fetch's receipt, spec §3.4) ---
    s, er = result["summary"], sys.stderr.write
    er("\n— discovery triage —\n")
    er(f"targets: {', '.join(s['targets']) or '(none set)'}\n")
    er(f"kept: {s['kept']}   dropped: {s['dropped']} "
       f"(location-filtered {s['dropped_by_location_filter']}, "
       f"keyword-filtered {s['dropped_by_keyword_filter']}, "
       f"no-match {s['dropped_no_target_match']})\n")
    for p in result["kept"][:10]:
        tags = f" [matched: {', '.join(p['matched'])}]" if p["matched"] else ""
        loc = f" ({p['location']})" if p.get("location") else ""
        er(f"  {p['rank']:>2}. {p.get('company', '?')} — {p.get('title', '?')}{loc}{tags}\n")
    if s["kept"] > 10:
        er(f"  … and {s['kept'] - 10} more\n")


if __name__ == "__main__":
    main()
