#!/usr/bin/env python3
# CoApply — discovery-auto querygen (build step 1 of
# docs/features/discovery-auto/spec.md §9).
#
# Turns the user's profile target roles (+ optional location/keyword filters) into a
# small, bounded list of web-search query strings. The orchestrator skill runs each
# query through WebSearch (Path A) scoped to the public ATS board domains this script
# also emits, then extracts (ats, token) pairs from the result URLs (step 2) and feeds
# them into the EXISTING fetch → triage → gate spine.
#
# This is a DETERMINISTIC front-end: no network, no LLM (same offline property the
# audit asserts for triage — spec §6). It only assembles strings.
#
# FIELD-AGNOSTIC BY CONSTRUCTION (spec §4): every search term comes from the caller's
# --targets / --location / --keywords. Nothing role- or field-specific is hardcoded —
# not in the data, not in the comments. The only literals here are generic
# job-posting nouns to strip ("roles", "positions", …) and the ATS vendor board hosts
# (a corpus property, the same vendors the rest of discovery already allowlists). The
# audit asserts this script carries no field/role literals (spec §6).
#
# Usage:
#   discover-querygen.py --targets "<USER_TARGETS text>"
#                        [--location "<text>"] [--keywords "<a, b>"]
#                        [--filters "<watchlist Filters cell>"]
#                        [--max-queries N] [--site-operators]
#
# Stdout (JSON, mirrors fetch/triage style):
#   {"queries": [...], "allowed_domains": [...], "receipt": {...}}
#   - queries        : the search strings to run (deduped, capped).
#   - allowed_domains: the ATS board hosts the skill scopes Path A WebSearch to.
# Stderr: a short human "what I'll search" receipt (spec §3.4 legibility).
# Exit:   0 normally; non-zero only on un-runnable input (no --targets, or targets
#         that reduce to zero role terms after stripping generic nouns) — never on a
#         small/empty filter result.

import argparse
import importlib.util
import json
import os
import re
import sys

# --- the ATS board hosts a public web index actually returns (the spike's
# allowed_domains, validated 2026-06-25). These are the FRONT-FACING posting hosts a
# SERP surfaces — distinct from the api.* hosts discover-fetch.py later GETs. Corpus,
# not field: the same Greenhouse/Lever/Ashby vendors discovery already scopes to. ---
ATS_BOARD_HOSTS = [
    "boards.greenhouse.io",
    "job-boards.greenhouse.io",
    "jobs.lever.co",
    "jobs.ashbyhq.com",
]

# --- generic, field-NEUTRAL job-posting nouns to drop so the discipline terms in
# --targets survive into the query. Stripping these from "<level> <discipline> roles"
# leaves "<level> <discipline>", which is what a SERP should match. Seniority words
# (senior/lead/…) are deliberately NOT here — they are useful, field-agnostic search
# terms and the spec's own example keeps them. None of these is a field literal. ---
GENERIC_NOUNS = {
    "role", "roles", "position", "positions", "job", "jobs",
    "opening", "openings", "opportunity", "opportunities",
    "career", "careers", "vacancy", "vacancies", "posting", "postings",
    "hiring", "work", "employment",
}

# Targets may list several roles; these are unambiguous list delimiters (a comma,
# slash, semicolon, pipe, or newline). We do NOT split on "and"/"or" — those are
# ambiguous inside a single discipline name and a SERP ignores them anyway.
_SPLIT_RE = re.compile(r"[,/;|\n]+")
_WORD_RE = re.compile(r"[a-z0-9+#]+")


def die(msg):
    """Un-runnable input — fail loud and stop (mirrors the other discovery scripts)."""
    sys.stderr.write(f"discover-querygen: error: {msg}\n")
    sys.exit(2)


def _load_parse_filters():
    """Reuse discover-triage.py's parse_filters so the Filters-cell vocabulary
    (`location:` / `keywords:`) has ONE definition across discovery and can't drift
    (the same importlib reuse triage does for fetch's watchlist parser). Triage is
    offline, so importing it keeps this script offline too."""
    triage_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               "discover-triage.py")
    spec = importlib.util.spec_from_file_location("discover_triage", triage_path)
    if spec is None or spec.loader is None:
        die(f"cannot locate discover-triage.py next to this script ({triage_path})")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.parse_filters


def clean_phrase(chunk):
    """One target chunk → a space-joined search phrase with generic job-posting nouns
    removed, lowercased, original word order preserved. Returns "" if nothing is left
    (e.g. the chunk was only filler like "roles")."""
    words = [w for w in _WORD_RE.findall(chunk.lower()) if w not in GENERIC_NOUNS]
    return " ".join(words).strip()


def role_phrases(targets):
    """Free-text --targets → ordered, de-duplicated list of role phrases."""
    phrases = []
    for chunk in _SPLIT_RE.split(targets or ""):
        phrase = clean_phrase(chunk)
        if phrase and phrase not in phrases:
            phrases.append(phrase)
    return phrases


def build_queries(phrases, location, keywords, max_queries, site_operators):
    """Assemble one search query per role phrase, appending the location and any
    keyword terms (the user's explicit narrowing signal). Dedup, then cap.

    Returns (queries, dropped_over_cap). The site-operator wrap (Path B seam, spec §2)
    is applied last so it never affects dedup."""
    loc = (location or "").strip().lower()
    kws = [k for k in keywords if k]

    queries = []
    for phrase in phrases:
        terms = [phrase]
        if loc:
            terms.append(loc)
        terms.extend(kws)
        q = " ".join(t for t in terms if t).strip()
        if q and q not in queries:
            queries.append(q)

    dropped = queries[max_queries:]
    queries = queries[:max_queries]

    if site_operators:
        site_clause = "(" + " OR ".join(f"site:{h}" for h in ATS_BOARD_HOSTS) + ")"
        queries = [f"{q} {site_clause}" for q in queries]

    return queries, len(dropped)


def main():
    ap = argparse.ArgumentParser(
        add_help=True, description="CoApply discovery-auto querygen (step 1)")
    ap.add_argument("--targets", required=True,
                    help="the $USER_TARGETS free-text string from identity.md")
    ap.add_argument("--location", default="",
                    help="optional location term appended to each query (e.g. remote)")
    ap.add_argument("--keywords", default="",
                    help="optional comma/space-separated extra query terms")
    ap.add_argument("--filters", default="",
                    help="optional watchlist-style Filters cell "
                         "('location: …; keywords: …'); explicit --location/--keywords "
                         "override the parsed values")
    ap.add_argument("--max-queries", type=int, default=6,
                    help="cap on number of queries (default 6; spec §3.1 3–6 range)")
    ap.add_argument("--site-operators", action="store_true",
                    help="Path B seam: wrap each query with site: ATS-host operators "
                         "instead of relying on the skill's allowed_domains")
    args = ap.parse_args()

    if args.max_queries < 1:
        die("--max-queries must be at least 1")

    # Filters cell (if any) seeds location/keywords using the shared vocabulary;
    # explicit flags win so the skill can pass them directly.
    parse_filters = _load_parse_filters()
    parsed = parse_filters(args.filters)

    location = args.location.strip() or (parsed.get("location") or "")
    if args.keywords.strip():
        keywords = [k for k in re.split(r"[,\s]+", args.keywords.lower()) if k]
    else:
        keywords = parsed.get("keywords") or []

    phrases = role_phrases(args.targets)
    if not phrases:
        die("no role terms in --targets after removing generic words "
            "(set 'Target roles' in identity.md to your discipline, e.g. "
            "'<level> <discipline> roles')")

    queries, dropped_over_cap = build_queries(
        phrases, location, keywords, args.max_queries, args.site_operators)

    receipt = {
        "role_phrases": phrases,
        "location": location or None,
        "keywords": keywords,
        "max_queries": args.max_queries,
        "site_operators": args.site_operators,
        "generated": len(queries),
        "dropped_over_cap": dropped_over_cap,
    }

    json.dump({"queries": queries,
               "allowed_domains": ATS_BOARD_HOSTS,
               "receipt": receipt}, sys.stdout, indent=2)
    sys.stdout.write("\n")

    # --- human receipt to stderr (spec §3.4) ---
    er = sys.stderr.write
    er("\n— discovery-auto querygen —\n")
    er(f"role phrases: {', '.join(phrases)}\n")
    er(f"location: {location or '(none)'}    "
       f"keywords: {', '.join(keywords) or '(none)'}\n")
    er(f"scoped to: {', '.join(ATS_BOARD_HOSTS)}"
       f"{' (via site: operators)' if args.site_operators else ' (via allowed_domains)'}\n")
    for q in queries:
        er(f"  → {q}\n")
    if dropped_over_cap:
        er(f"  … {dropped_over_cap} more role phrase(s) dropped to respect "
           f"--max-queries={args.max_queries}\n")
    er(f"total: {len(queries)} quer{'y' if len(queries) == 1 else 'ies'}\n")


if __name__ == "__main__":
    main()
