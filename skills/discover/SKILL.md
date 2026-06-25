---
name: discover
description: Surface roles worth applying to, as a pick-list — you decide what flows into an application. Two modes. Watchlist mode checks each company on your list's public job board for openings that match your target roles. Auto mode (`--auto`) needs no list: it turns your target roles into web searches scoped to public ATS boards, finds companies hiring, and runs them through the same pick-list. Also adds companies to the watchlist. Triggers on "find me jobs", "find me jobs anywhere", "search for <role> roles", "check my watchlist", "what's open at the companies I'm watching", "discover roles", "add <company> to my watchlist".
argument-hint: "[--auto | add <company careers URL or ATS board URL>]"
---

# CoApply — Discover (company watchlist monitor)

This surfaces roles, it does not apply to them. It checks each company on the user's
**watchlist** (their list, never ours), filters to titles that match their target roles,
and presents a ranked shortlist **as a gate**. The user picks; each pick is handed back as
a ready-to-run `/coapply:start` command they run at their own pace. No expensive agent runs
here, nothing auto-submits, and the only network calls go to public ATS JSON boards over
plain HTTP (the deterministic scripts enforce that — see `docs/features/discovery/spec.md`).

**Be honest about what this is.** Two modes, neither is whole-market search:
- **Watchlist mode** (default) finds openings at companies the user already chose to watch.
- **Auto mode** (`--auto`) needs no list: it turns the user's target roles into web searches
  **scoped to the public ATS board domains** (Greenhouse / Lever / Ashby), finds companies
  hiring there, and runs them through the same pick-list. It is **broad, not exhaustive** —
  it surfaces what a general web index already has indexed on those public boards — and is
  **strongest for tech/startup roles**, because that ATS corpus skews that way (a corpus
  limitation, not an engine bias). It is **not** LinkedIn/Indeed and never will be; that
  aggregator category is the boundary it deliberately rejects.

If the user expects "search every job everywhere," say plainly that auto mode is broad-not-
exhaustive (public ATS boards a web index has indexed) and watchlist mode watches a list they
curate — and offer the one that fits.

## Step 0 — Resolve paths and identity (do this first)

Run this **bare** — don't capture it in `VAR="$(…)"` (that can't be allowlisted and would
prompt every run). It resolves the saved profile folder and probes readiness:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/profile-status.sh"
```

It prints `PROFILE_DIR=… RUNS_DIR=… WRITABLE=… IDENTITY=… SKILLS=… RESUME=… PLACEHOLDERS=…`.
Use the printed `PROFILE_DIR` and `RUNS_DIR` as absolute paths from here on. Apply the same
first-run **warm route** as `/coapply:start`, mapping the flags to one `STATE`:

- `PROFILE_DIR` empty → **`not-set`**: walk them into setup (make an empty folder → `/plugin` →
  CoApply → set **Profile folder** → `/coapply:setup`), then stop.
- `WRITABLE=no` → **`bad-path`**: their saved folder isn't there/writable — re-point it via
  `/plugin`, then stop.
- `IDENTITY=no` (no `identity.md`, so no target roles to match against) → **`not-ready`**: run
  `/coapply:setup` first so there's a profile + target roles, then re-run `/coapply:discover`.
  Stop.
- otherwise → **`ok`**, continue.

Then read `${PROFILE_DIR}/identity.md` and resolve **`$USER_TARGETS`** = the `Target roles`
field. This is what triage ranks titles against. If it's empty, discovery still runs but will
show *everything* that passes the per-company filters (triage says so in its reasons) — mention
that and suggest setting target roles in `identity.md` for a useful ranking.

Paths used below:
- Watchlist (user-authored): `${PROFILE_DIR}/watchlist.md`
- Optional synonyms (user-authored, engine ships none): `${PROFILE_DIR}/discover-synonyms.txt`
- Optional auto-mode reposter denylist (user-authored, engine ships a tiny default in-script):
  `${PROFILE_DIR}/discover-denylist.txt`
- Derived dismiss cache: `${RUNS_DIR}/_discovery_seen.txt`

## Step 0.5 — Route by mode

After Step 0, pick the branch from `$ARGUMENTS` (and the user's phrasing):
- `$ARGUMENTS` begins with `add` → **Step 1** (`add` sub-flow — register a company).
- `$ARGUMENTS` contains `--auto`, **or** the user asked to search without a list ("find me jobs
  anywhere", "search for `<role>` roles", "what's hiring", "look across the web") → **Step A**
  (auto mode), then converge at Step 3.
- otherwise → **Step 2** (watchlist mode).

## Step 1 — `add` sub-flow (if `$ARGUMENTS` begins with `add`)

If `$ARGUMENTS` is `add <something>`, the user is registering a company, not running a search.
Take the rest of the argument as a company careers URL or ATS board URL and resolve it. Run
**bare**:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/discover-resolve.sh" "<the URL or text after 'add'>"
```

- **Exit 0** — it prints `ats=…`, `token=…`, `url=…`. Append a row to `${PROFILE_DIR}/watchlist.md`.
  Read the file, then use **Edit** to add the row as the last row of the markdown table:
  `| <Company> | <ats> | <token> |  |`. For `<Company>`, use a readable title-cased version of
  the token (e.g. token `acme-corp` → `Acme Corp`) and tell the user they can rename it in
  `watchlist.md` — the display name is cosmetic (dedup keys on `ats|token`, not the name). If the
  table currently holds only the example placeholder rows (cells containing `<` … `>`, like
  `<board-id>`), **replace** those placeholder rows with this real one rather than appending below
  them. Confirm: "Added **<Company>** (<ats>/<token>) to your watchlist." Then offer: "Want me to
  check your watchlist now?" — if yes, continue at Step 2; if no, stop.
- **Exit 3** — Workday detected (recognized but deferred). Tell the user Workday boards aren't
  supported yet and ask for a Greenhouse/Lever/Ashby board URL instead. Don't write a row. Stop.
- **Exit 1** — no ATS detected. Relay the script's stderr note and ask them to paste the
  company's Greenhouse/Lever/Ashby board URL directly. Don't write a row. Stop.

If `$ARGUMENTS` is empty or anything other than an `add …`, fall through to Step 2 (run a check).

## Step A — Auto mode (`--auto`): search the web for matching boards

This replaces the watchlist requirement with a search: profile target roles → ATS-scoped web
searches → first-party `(ats, token)` tokens → an **ephemeral watchlist** that feeds the
*exact same* fetch → triage → gate spine. Nothing downstream changes.

**A0 — Say what's about to happen (privacy, named not hidden).** Before searching, tell the
user once, plainly: this sends your **target-role and location keywords** (not personal data)
to a web search provider — a third party watchlist mode never touches — and then fetches each
company's **own** public board. Results are a source of *companies to check*, never job data
themselves. It's broad, not exhaustive, and strongest for tech/startup roles.

**A1 — Generate the queries (deterministic, no network).**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/discover-querygen.py" --targets "<$USER_TARGETS text>" > "${RUNS_DIR}/.discovery_auto_queries.json"
```

Substitute the real `$USER_TARGETS` string (quoted). If the user named a **location** ("remote",
"NYC") or extra **keywords** in their request, add `--location "<loc>"` and/or `--keywords "<a, b>"`
— terms must come from the user/profile, never invented. The script prints a "what I'll search"
receipt to **stderr**; surface it. Then **Read** `${RUNS_DIR}/.discovery_auto_queries.json` and
take its `queries` array and its `allowed_domains` array.

**A2 — Run each query through WebSearch (Path A).** For **each** string in `queries`, call the
**WebSearch** tool with that string as `query` and `allowed_domains` set to the `allowed_domains`
array from the querygen JSON (this is what scopes results to the public ATS board hosts). Collect
**every result URL** across all queries.

- **If the WebSearch tool is not available** in this environment: stop the auto flow and say so
  plainly — auto mode (Path A) needs Claude Code's built-in web search. Offer the fallbacks:
  watchlist mode (`/coapply:discover add <careers URL>` to build a list) or the documented Path B
  external SERP API (off by default, not built in v1). Do not fabricate results.

**A3 — Extract first-party tokens (deterministic, no network).** Write the collected URLs, one
per line, to `${RUNS_DIR}/.discovery_auto_urls.txt` with the **Write** tool, then:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/discover-extract.py" --urls "${RUNS_DIR}/.discovery_auto_urls.txt" > "${RUNS_DIR}/.discovery_auto_tokens.json"
```

If `${PROFILE_DIR}/discover-denylist.txt` exists, add `--denylist "${PROFILE_DIR}/discover-denylist.txt"`.
The script keeps **only** tokens on a known ATS board (greenhouse/lever/ashby) and drops reposter
noise; it prints a "what came in / what I kept" receipt to **stderr** — surface it. Then **Read**
`${RUNS_DIR}/.discovery_auto_tokens.json` and take its `tokens` array (`{ats, token, url}` each).

If `tokens` is **empty**: tell the user the search surfaced no first-party ATS boards this time
(results were non-ATS, or all reposter noise), and suggest broadening `Target roles` in
`identity.md`, trying different keywords, or running again later. Stop.

**A4 — Build the ephemeral watchlist (union with the manual list).** Read
`${PROFILE_DIR}/watchlist.md` and collect any **real** data rows (per Step 2's test). With the
**Write** tool, create `${RUNS_DIR}/.discovery_auto_watchlist.md` as a markdown table:

```
| Company | ATS | Board id | Filters |
|---|---|---|---|
```

Then one row per **auto** token — `| <Company> | <ats> | <token> |  |`, where `<Company>` is a
readable title-cased version of the token (e.g. `acme-corp` → `Acme Corp`) — followed by the
manual real rows verbatim. **Dedup on `<ats>|<token>` (lowercased)** so a company already on the
watchlist isn't fetched twice; the manual row wins (keep its display name/filters).

Then **continue at Step 3**, but pass this file as the watchlist:
`--watchlist "${RUNS_DIR}/.discovery_auto_watchlist.md"`. Fetch, triage, the gate, dedup against
the single ledger — all **unchanged**. (At Step 6, auto mode also offers "save to watchlist" — see
there.)

## Step 2 — Ensure a usable watchlist

Read `${PROFILE_DIR}/watchlist.md`. It's usable only if it has at least one **real** data row —
a `|`-row that is not the header, not the `|---|` separator, and not an example placeholder (no
`<…>` tokens in its cells). If the file is missing, or has zero real rows:

> Your watchlist is empty. Add a company and I'll start watching its job board:
> **`/coapply:discover add <company careers URL or ATS board URL>`** — paste a careers page or a
> Greenhouse/Lever/Ashby board link and I'll detect the rest. You can also edit
> `watchlist.md` by hand.

Then stop. (Don't fabricate companies — the list is the user's, the engine ships none.)

## Step 3 — Build the dedup ledger, then fetch

**One authoritative ledger (spec §3.3).** A job is "already seen" if it was acted on (its
fingerprint is stored in some run's `_run.json.discoveryFp` — written by `/coapply:start`) **or**
explicitly dismissed (in the derived cache `_discovery_seen.txt`). Build the union into a
transient file, then fetch:

In **watchlist mode** the watchlist is `${PROFILE_DIR}/watchlist.md`. In **auto mode** (arrived
from Step A) it is the ephemeral `${RUNS_DIR}/.discovery_auto_watchlist.md` you just built — use
that path for `--watchlist` everywhere below (Step 4's triage too). Everything else is identical.

```bash
{ grep -rhoE '"discoveryFp"[[:space:]]*:[[:space:]]*"[0-9a-f]{40}"' --include='_run.json' "${RUNS_DIR}" 2>/dev/null | grep -oE '[0-9a-f]{40}' ; cat "${RUNS_DIR}/_discovery_seen.txt" 2>/dev/null ; } | sort -u > "${RUNS_DIR}/.discovery_seen_union.txt"
"${CLAUDE_PLUGIN_ROOT}/scripts/discover-fetch.py" --watchlist "<watchlist path for the mode>" --seen "${RUNS_DIR}/.discovery_seen_union.txt" > "${RUNS_DIR}/.discovery_fetch.json"
```

The fetch script prints a human receipt to **stderr** (hosts hit, per-company counts, any board
that errored/404'd, schema-drift flags, totals) — surface that to the user as the "what went out /
what came back" summary. A dead token or a 404 on one board does **not** kill the run; it's
reported and the rest proceed. (The `.`-prefixed temp files stay out of `/coapply:list`, which
ignores dotfiles.)

If the receipt shows **0 new** postings: tell the user nothing new is open across the watched
boards right now (everything either didn't match or was already seen/acted-on), and stop. Offer
`add` if their list is short.

## Step 4 — Rank (deterministic triage, no LLM, no network)

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/discover-triage.py" --targets "<$USER_TARGETS text>" --postings "${RUNS_DIR}/.discovery_fetch.json" --watchlist "<watchlist path for the mode>" > "${RUNS_DIR}/.discovery_triage.json"
```

Substitute the real `$USER_TARGETS` string (quoted). If `${PROFILE_DIR}/discover-synonyms.txt`
exists, add `--synonyms "${PROFILE_DIR}/discover-synonyms.txt"`. Triage is pure title-matching
against the target terms + the per-row filters; its reasons quote real fields only (no model-written
"great fit" — there is no fabrication surface here). Then **Read** `${RUNS_DIR}/.discovery_triage.json`
to render the gate.

## Step 5 — The gate (a stop — the human decides)

From the triage `kept` array (already ranked: most target terms matched, then most recent), render
a compact markdown table, one row per kept posting, columns:

| # | Match | Company | Title | Location | Reason | Link |

`#` = `rank`; `Match` = the `matched` terms joined; `Reason` = the descriptive `reason`; `Link` =
the `url`. If `kept` is empty, say nothing matched the target roles this time (point at the triage
stderr summary, which counts what was filtered out and why), and suggest either broadening
`Target roles` in `identity.md`/the row filters, or adding companies. Then stop.

Then ask the user to choose — make all three moves explicit:
- **Apply** to one or more (e.g. "1 and 3") → Step 6 hand-off.
- **Dismiss** one or more (e.g. "dismiss 2, 4") → so they stop resurfacing.
- **None** → stop, nothing changes.

This is the go/no-go gate: do not run `/coapply:start`, do not call any agent, do not write
anything except the dismiss cache. The user runs the apply commands themselves.

## Step 6 — Hand-off (emit commands) + dismiss

**For each posting the user chose to apply to**, print a ready, copy-pasteable line — one per
posting, so each application stays a separate, deliberate, gated spend (no batch auto-routing):

```
/coapply:start <url>
```

Use the posting's `url` from the triage JSON. Tell them: run these one at a time when ready; each
starts a fresh, gated application, and `/coapply:start` records the job so it won't resurface here.

**For each posting the user chose to dismiss**, append its `fp` (from the triage JSON) to the
derived cache, one fingerprint per line:

```bash
printf '%s\n' "<fp1>" "<fp2>" >> "${RUNS_DIR}/_discovery_seen.txt"
```

Confirm what you dismissed by company/title. Dismissed jobs won't reappear on the next check (a
repost under a *new* id is a new fingerprint and may resurface — accepted: over-showing an active
listing beats hiding it).

**Auto mode only — offer "save to watchlist" (compounding list seam).** A company surfaced by a
search is ephemeral; if the user applied to (or liked) one, offer to add it to their **real**
watchlist so it's watched on every future run: "Want me to save **<Company>** to your watchlist so
I check it every time?" For each one they say yes to, append a row to `${PROFILE_DIR}/watchlist.md`
the same way Step 1's `add` does — `| <Company> | <ats> | <token> |  |`, using the `ats`/`token`
from the triage JSON, **skipping any `<ats>|<token>` already present** (read the file first; replace
example placeholder rows rather than appending below them). This is the only profile write auto mode
makes, and only on explicit yes. Don't auto-save every result — that would recreate the curation the
list is meant to be.

Close with one forward line: **Next:** run an emitted `/coapply:start` line when ready, or
`/coapply:discover --auto` / `/coapply:discover` again later, or `/coapply:discover add <url>` to
widen the list by hand.

## Notes / failure handling

- **Stay in bounds.** Every network call here is a deterministic script with its own guard: fetch
  has a hardcoded host allowlist, resolve validates the final redirect host, triage has no network
  capability at all. Never WebFetch a posting URL from this skill. In **auto mode** the only added
  network is the `WebSearch` calls — scoped by `allowed_domains` to the public ATS board hosts, used
  only to find first-party `(ats, token)` tokens. `discover-extract.py` then keeps **only** known-ATS
  tokens, so a stray non-ATS result is dropped, never fetched. A search snippet is never treated as
  job data — it's a source of a token, and we fetch the company's own board.
- **Don't hand a subagent a `${…}` literal** — there are no subagents in this flow, but if you ever
  add one, pass resolved absolute paths.
- **Watchlist parse error** (a malformed row) — `discover-fetch.py` exits non-zero pointing at the
  offending line. Relay that line to the user to fix in `watchlist.md`; don't paper over it.
