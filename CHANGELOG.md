# Changelog

All notable changes to CoApply. Versioned on the `plugin.json` version line.

## [0.9.3] — 2026-06-26 — Hub seniority axis + collapsible lens

Role titles carry many names for the same level, and grouping by the fuzzy `surfaced.json` category
lanes ("Senior product management roles", "growth", "uncategorized") made it hard to tell *what
seniority* you were looking at. This adds a **seniority axis** to the hub and makes the lens panel
collapse. Spec: `docs/features/hub/spec.md §13`. **Pure `hub/index.html` change** — seniority is derived
client-side from the title, so no `server.py`, API/contract, `surfaced.json` schema, or `audit.sh` change.

- **Seniority ladder (field-agnostic)** — each role is placed on a generic rank ladder keyed *only* off
  seniority qualifiers, never a job noun, so it holds for any field (a nurse, an accountant): `Associate /
  Junior < Individual Contributor (no qualifier) < Senior < Lead / Staff / Principal < Director < VP <
  C-suite`. A plain "Product Manager" correctly lands as IC, below "Senior PM".
- **Group by Seniority (new default) or Lane** — a `Group` segmented control above the surfaced field.
  Roles now cluster into clear ladder bands instead of fuzzy category lanes; switch back to Lane anytime.
- **Level filter + Seniority sort** — multi-select `Level` chips in the lens (pick any bands), plus a new
  *Seniority* sort (senior-most first). Both share the one `seniorityOf(title)` derivation.
- **Collapsible lens (bug fix)** — the filter panel was *built* to collapse (`filtersOpen` defaults false)
  but a `.lens-panel { display: grid }` rule overrode the `[hidden]` attribute, so it was always open and
  ate the viewport. Added `.lens-panel[hidden] { display: none }` — it now defaults collapsed behind the
  **Filters** button; search · group · sort · result pill stay in the always-visible bar.

## [0.9.2] — 2026-06-26 — Hub filter & sort (the lens controls)

The accumulating surfaced ledger outgrew scan-only. At a few hundred rows in one lane (Senior PM = 183
of 263), you need to *narrow and reorder*. This adds **the lens** — filter + sort controls above the
surfaced field. Spec: `docs/features/hub/spec.md §13`. **Pure `hub/index.html` change** — no `server.py`,
no API/contract, no `surfaced.json` schema, no `audit.sh` change. Every control derives from metadata
already in `/api/state`, so it's a mechanical lens (zero judgment) and stays field-agnostic: lanes,
matched terms, sources, and locations all come from the payload, nothing hardcoded.

- **Filters** — Status (New · Queued · Has-run · Dismissed; *default hides Dismissed*), Remote-only,
  Recurring (`timesSeen ≥ 2`), Lane, Source (`watchlist`/`auto`), Matched-term chips (union of `matched[]`,
  top-24 by frequency), free-text Region (over `location`) and Search (over title/company). An active-filter
  count badge on **Filters**, a one-click **Clear**, and an **N of M shown** result pill.
- **Sorts** — Relevance (`rankAtLastSeen`, default) · Freshest (`posted`) · Recently seen (`lastSeenAt`)
  · Most persistent (`timesSeen`) · Company A–Z · Status priority (new → queued → has-run → dismissed).
- **Scope = the surfaced field only** (spec §13.4) — the gate band and runs stay unfiltered; company
  clusters + lane counts recompute against the filtered set. **`openState` filter is intentionally omitted**
  (it's monotone `"open"` in v1 — it unlocks with the §9 close-reconciliation, never shipped as a dead control).
- **FE discipline preserved:** filter/sort state lives in `App.ui` (not the poll-replaced `App.state`), the
  lens DOM rebuilds only when option sets change (so search/region focus + caret survive every 4s poll),
  and the multi-select `Set` survives filtering. Verified with a Playwright pass (each filter/sort + persisted
  selection across a re-render); zero console errors. Audit still **PASSES** unchanged.

## [0.9.1] — 2026-06-26 — Hub readability pass

The hub shipped too small to read comfortably. This is a pure `hub/index.html` type + contrast pass —
no server, API, or contract change (`server.py` and `audit.sh` untouched).

- **Type scale bumped ~15%** across the board: base body 14→16px, content rows / lane + company names
  13→15px, secondary meta text floored at 12px (was 10–11px), micro all-caps labels at 10–11px. Body
  line-height 1.45→1.55 for looser, more scannable rows.
- **Contrast lifted** on the two low-contrast text tokens (`--txt-dim`, `--txt-faint`) so secondary
  meta (locations, dates, counts) is legible on the dark canvas.

## [0.9.0] — 2026-06-26 — The hub: CoApply's returnable home

CoApply gets its first **persistent visual surface**. Until now its only surface was an ephemeral
chat: you ran discover, saw a table, it scrolled away. **The hub** is a local, single-page command
center that renders the whole funnel in one returnable place — **discover (surfaced roles) → the
gate → runs** — joined by the `fp`/`discoveryFp` fingerprint. It is a **thin lens over durable
files**: it reads the curated discover ledger (`surfaced.json`) and your run folder, joins them,
derives status read-time, and writes exactly one thing — a queue the human gate picks up. It
**binds `127.0.0.1` only**, makes **no network calls**, runs **no agent**, and **never submits**.
Spec: `docs/features/hub/spec.md` (6-lens audited).

**The face, not the heart.** The gate, the honest fit-check, and the no-fabrication writing are
still the soul — the hub just makes the funnel *legible so it compounds*. It is read-mostly by
design and stays a thin projector: zero engine judgment lives in the page.

### Added
- **`scripts/discover-surface.py` + discover Step 4.5** *(shipped 0.8.x branch, the hub's data
  spine)* — deterministic, offline curation of triage output into `surfaced.json`: dedup + accumulate
  on `fp`, per-company cap (N=8) with `moreAtCompany` overflow, category lanes from the profile's
  target-role phrases, `firstSeen`/`lastSeen`/`timesSeen`. No LLM, no network — inherits triage's
  no-fabrication/no-network guarantees. Runs on **every** check, both modes, pre-gate.
- **`hub/server.py`** — stdlib `http.server`, **binds `127.0.0.1` only** (refuses a non-loopback bind
  outright), zero network imports. Reads `surfaced.json` + `runs/*/_run.json` (never the multi-MB
  triage/fetch inputs) + `plugin.json` for the version badge; tolerant reads. Writes **only** three
  allow-listed, path-confined files (`.coapply_queue.json`, `.coapply_hub_state.json`, an append to
  `_discovery_seen.txt`). `GET /api/state?since=` (full join + derived status, `304` on unchanged
  mtime), `POST /api/queue[/remove]`, `POST /api/dismiss`, health/version. `fp` validated
  `^[0-9a-f]{40}$` on every endpoint.
- **`hub/index.html`** — one self-contained page (all CSS/JS inline, **zero external assets**),
  instrument-panel identity (near-black canvas, one iris accent, tabular numerals, conic fit gauge
  labeled `/10`). The **layout is the funnel**: wide surfaced field (category lanes → collapsible
  company clusters → dense one-line rows, "new" dots) → an always-present staging **gate** band →
  committed runs (fit gauge + done/no-go badge + expand to pickup note + artifact grid). One
  `state` + idempotent `render()`, event delegation, selection in a `Set` that survives polls,
  conditional ~4s `304` polling, three field-agnostic empty states that each name their chat command.
- **`skills/hub/SKILL.md`** — the launcher. Resolves paths via `profile-status.sh` (bare), warm-routes
  a not-set/bad-path profile, then starts the server (start-or-reuse) bound to `127.0.0.1` and opens
  `http://127.0.0.1:7878/`. A skill (not a command) because `${CLAUDE_PLUGIN_ROOT}` only substitutes
  in skills.
- **Queue consumer at the gate** — `/coapply:start` **with no argument** now reads
  `.coapply_queue.json`, lists the staged roles, and emits one copy-paste `/coapply:start <url>` per
  job, then **stops**. It is **read-only** (the hub stays the single writer of the queue) and runs
  **zero agents** — each emitted command hits its own fit gate. This closes the loop so the hub's
  primary action isn't a dead-end.

### Changed
- **`scripts/audit.sh`** — `hub` added to the personal-data / field-assumption / stray-path scans and
  the skill-presence list; a new **§16 hub-boundary section** asserts (behaviorally where it matters):
  the server refuses a `0.0.0.0` bind (exit 2), imports no outbound network client, writes only its
  three path-confined files, does **no** url→fp hashing, ships a fully self-contained page, and that a
  skill actually consumes the queue. Comment-proof: server.py's header documents `0.0.0.0`/`sha1(url)`
  as guards it *avoids*, so the asserts target executable code and behavior, never those strings.

## [0.8.0] — 2026-06-25 — Discovery-Auto: zero-curation, profile-driven discovery

Roadmap follow-up to Discovery 0.7.1. `/coapply:discover` gains an **`--auto` mode** that needs
**no watchlist**: it turns your profile's target roles (+ optional location/keywords) into web
searches **scoped to the public ATS board domains** (Greenhouse / Lever / Ashby), extracts the
`(ats, token)` of each company that surfaces, and feeds those tokens into the **existing** fetch →
triage → gate pipeline. One command, no list. The expensive spine is reused intact; the only new
surface area is the search front-end. Spec: `docs/features/discovery-auto/spec.md` (feasibility
spike PASS, 2026-06-25).

**Named honestly:** still **not** whole-market search. It surfaces what a general web index already
has indexed on public ATS boards — **broad, not exhaustive** — and is **strongest for tech/startup
roles** because that ATS *corpus* skews that way (a corpus limitation, not an engine bias). It is
not, and will not be, LinkedIn/Indeed. **Privacy, named not hidden:** auto mode sends your
target-role/location keywords (not personal data) to a search provider — a third party watchlist
mode never touches. The help text + README say all of this rather than overselling.

### Added
- **`scripts/discover-querygen.py`** — deterministic, offline, field-agnostic: profile targets +
  filters → a small (3–6, capped) list of ATS-scoped query strings + the `allowed_domains` to scope
  them. Every term comes from the profile; nothing role/field-specific is hardcoded.
- **`scripts/discover-extract.py`** — deterministic, offline: result URLs → unique `(ats, token)`
  pairs. **Boundary guard:** emits **only** known-ATS tokens (drops anything else); a tiny, generic,
  user-overridable reposter denylist (`jobgether`) drops aggregator noise. Mirrors fetch's URL
  classifier so the parse can't drift.
- **`skills/discover/SKILL.md` `--auto` mode** — `/coapply:discover --auto` (and natural language:
  "find me jobs anywhere", "search for `<role>` roles"): querygen → **WebSearch** loop (Path A,
  `allowed_domains`-scoped) → extract → an **ephemeral watchlist** (unioned with any manual rows,
  deduped on `ats|token`) → the unchanged fetch/triage/**gate**/emit/dismiss spine. On a pick it
  offers to **save the company to your watchlist**, so the list compounds over time.

### Boundary / audit
- **`WebSearch` is the sanctioned auto-mode Path A** — scoped by `allowed_domains` to public ATS
  hosts, used only to find first-party tokens (never as job data). `audit.sh` boundary-point-3 now
  allows WebSearch *in the skill* while keeping the ranker offline and **WebFetch of a posting
  forbidden**.
- **New `audit.sh` asserts (spec §6):** querygen + extract import no network module; extract refuses
  a non-ATS URL and drops a denylisted token (behavioral negative tests, with a positive control);
  querygen hardcodes no role/field literal (field-agnostic guard); help + README carry the
  broad-not-exhaustive + search-provider-privacy framing.

### Deferred (named, not dropped — spec §7)
- Path B external SERP API (Brave / Serper) as a built default — seam kept, not built.
- Scheduled/recurring watch · full feedback-learning (active/promising/backoff) · more ATS adapters
  (Workday / iCIMS) · optional LLM re-rank.

## [0.7.1] — 2026-06-25 — Discovery: zsh-safe first-run dedup ledger

Patch found by dogfooding `/coapply:discover` end-to-end against live public boards
(Greenhouse + Lever + Ashby) before merge. On a user's **first-ever** run — an empty runs
folder, no `_run.json` yet — the Step 3 seen-ledger build used a shell glob
(`"${RUNS_DIR}"/*/_run.json`) that zsh's `nomatch` turns into a spurious
`no matches found` error line. The run still worked (the union file is created empty and the
fetch proceeds), but the stray "error" reads as a failure on the very first invocation.

### Fixed
- **`skills/discover/SKILL.md`** Step 3 — build the dedup union with
  `grep -r --include='_run.json' "${RUNS_DIR}"` instead of a `*/_run.json` glob. No shell
  glob means no zsh `nomatch` noise; behavior is identical when runs exist (verified: same
  fingerprints extracted) and silent when the folder is empty. Clean under both bash and zsh.

## [0.7.0] — 2026-06-25 — Discovery: a company-watchlist job monitor that feeds the gate

Roadmap item #6. CoApply can now *surface* roles, not only process a job you already found —
without crossing the line the project draws. You keep a **watchlist** of companies; CoApply
checks each one's **public ATS board over plain HTTP** (no browser, no auth, no aggregator
scraping), filters to titles that match your target roles, and presents a ranked shortlist
**as a gate**. You pick; each pick is handed back as a ready-to-run `/coapply:start` command —
nothing batch-applies and no expensive agent runs before you decide. Built spec-first and
reviewed by a brains-trust (Gemini 3.1 Pro + Claude Opus 4.8); spec in
`docs/features/discovery/spec.md`.

**Named honestly:** this is a *watchlist monitor*, not whole-market search. It finds openings
at companies you already chose to watch; it can't yet suggest companies you didn't know to
care about (seed-from-public-directories is a planned follow-up). The help text and README say
so rather than overselling.

### Added
- **`/coapply:discover`** (`skills/discover/SKILL.md`) — the orchestrator: resolves paths +
  `$USER_TARGETS`, ensures a usable watchlist (offers `add`, never invents companies), fetches,
  ranks, **gates** on a ranked table, emits one copy-paste `/coapply:start` command per pick,
  and supports **dismiss** (stop a seen-but-unwanted role resurfacing).
- **`/coapply:discover add <careers or board URL>`** — detects the ATS and appends a watchlist
  row; recognizes Workday but defers it (not yet fetchable).
- **`scripts/discover-fetch.py`** — deterministic spine. Greenhouse + Lever + Ashby adapters,
  Lever pagination, one normalized schema, fail-loud on schema drift, `sha1(ats|token|id)`
  fingerprint, a light inline receipt. Ashby is best-effort: a `404` (org didn't enable the
  public API) is a soft note, not a failure. Stdlib-only Python 3.
- **`scripts/discover-triage.py`** — deterministic keyword/synonym title ranker with row
  location/keyword filters and **descriptive-only reasons that quote real fields** (no model
  writing "great fit"). No LLM, no network.
- **`scripts/discover-resolve.sh`** — careers/board URL → `(ats, board-id)`; only ever *emits*
  a known ATS.
- **`profile.example/watchlist.md`** — the watchlist template (placeholder rows only; the
  engine ships zero companies).
- **Single-authoritative-ledger dedup** — `/coapply:start` now stamps the posting's `fp` into
  its run's `_run.json` (`discoveryFp`, via `discover-fetch.py --fp-from-url`), so `start` and
  `discover` share one fingerprint scheme; the dedup union is every run's `discoveryFp` ∪ the
  `_discovery_seen.txt` dismiss cache.
- **`audit.sh` section 15** — asserts the discovery **3-point network boundary** (fetch host
  allowlist · resolve emits-only-a-known-ATS · triage has no network capability), a
  **vendor-vs-company guard** (ATS infra `greenhouse`/`lever`/`ashby` is allowed, but the
  watchlist template must ship only placeholder companies), and a **fingerprint guard**
  (`ats|token|id`, never `company|id`).

### The boundary (why this stays in bounds)
- **Public ATS JSON over plain HTTP only** — a hardcoded host allowlist in the fetch script;
  resolve validates the resolved host and refuses anything that isn't a known ATS; the default
  triage is a pure ranker that *can't* fetch (the biggest stay-in-bounds risk in the v1 design
  was an LLM triage that could WebFetch a posting and bypass the allowlist — removed).
- **The gate stays:** discovery ends at a pick-list; the hand-off emits commands you run; no
  auto-submit, no batch spend, every application is still a real go/no-go.

### Deferred (named, not dropped — spec §8)
- Workday adapter, seed-from-public-directory (the real answer to the cold-start gap), an
  optional LLM triage re-rank, and recurring/scheduled watches.

## [0.6.0] — 2026-06-08 — Per-agent model tiering: the tier picks the model too

Roadmap item #3. Until now `$TIER` only changed *how many* specialists ran; every agent
inherited the session model. Now the tier also picks *which model* each agent runs on, so
`lite` is genuinely cheaper — not just shorter. Verified that the Task tool's per-dispatch
`model` override routes correctly (`model: haiku` → `claude-haiku-4-5`, `model: opus` →
`claude-opus-4-8`), so this needed **no migration** to native plugin `agents/` and no config
schema change — the orchestrator just passes `model` on each Task call.

### Added
- **Model map in `master-apply.md` Step 3** — a tier × agent-class matrix. Three classes:
  **mechanical** (jd-parser, dedup-check), **reasoning** (role-analysis, fit-score, positioning,
  company-research, prototype-suggester, followup-plan), **voice** (cover-letter, outreach,
  resume-update, interview-prep, application-questions).

  | class | lite | standard | full |
  |---|---|---|---|
  | mechanical | haiku | haiku | haiku |
  | reasoning | haiku | sonnet | sonnet |
  | voice | sonnet | sonnet | opus |

  Baked-in judgments: mechanical work stays on haiku even on `full` (no premium model to parse a
  JD into JSON), and the cover letter never drops below `sonnet` even on `lite` (the deliverable
  stays good; lite saves by running *fewer* agents). "Right-size by role," not "cheap tier = worse letter."
- **Class tags on every dispatch** in `phase-research.md` / `phase-content.md` (e.g. `[voice]`),
  so the orchestrator knows which model to pass.
- **`audit.sh` section 14** — fails the build if the Model map or a class row goes missing, or if
  any agent dispatch line lacks a `[class]` tag (a new untagged agent would silently inherit).

### Changed
- **Cost-to-finish line** at the gate notes the token estimate is an upper bound — `lite`/`standard`
  run cheaper models, so real spend is lower.
- **README** tier section now states tiers control both agent count and per-agent model.

### Not changed
- No `coapply.config.json` change — the matrix is engine-defined off the existing `$TIER`. No new
  user knobs.

## [0.5.0] — 2026-06-08 — Allowlist-friendly Step 0: fewer "allow?" prompts

The 0.4.3 follow-up, done. Every skill resolved the profile folder by wrapping the resolver
in `PROFILE_DIR="$(…resolve-profile-dir.sh)"` — an assignment-wrapped command substitution
that Claude Code can't pre-approve, so it prompted on *every* command, every time, and no
allowlist or "don't ask again" could stop it. Skills now call their helper scripts **plainly**
(bare), so the prompt's **"Yes, and don't ask again"** saves a clean, reusable rule.

### Added
- **`scripts/profile-status.sh`** — one bare call that resolves the profile dir *and* reports
  readiness (`PROFILE_DIR`/`RUNS_DIR` + `WRITABLE`/`IDENTITY`/`IDENTITY_FILLED`/`SKILLS`/
  `RESUME`/`PLACEHOLDERS`). It replaces the inline compound Bash blocks (`touch`/`grep`/`find`)
  that `help`/`add`/`start` ran in Step 0 — one allowlistable call instead of a substitution
  plus a compound conditional, with no extra prompt for users who don't allowlist.
- **`audit.sh` section 13** — verifies the new script across states and **fails the build** if
  any skill reintroduces the un-allowlistable `VAR="$(…resolve-profile-dir.sh)"` wrapper.

### Changed
- **All eight skills** call their helper scripts bare and read the printed values, instead of
  capturing via `$(…)`: `help`/`add`/`start`/`list`/`resume` use `profile-status.sh`;
  `tier`/`setup`/`feedback` use a bare `resolve-profile-dir.sh`. Behavior is identical — the
  difference is that the calls can now be remembered.
- **README "fewer permission prompts"** now leads with "Yes, and don't ask again" (which works
  for CoApply's scripts because the calls are bare), and adds `printf` to the optional
  file-command allowlist (setup writes `coapply.config.json` with it).

### Not changed
- The one remaining `$(…)` is `gh issue create --repo "$(…)"` in `feedback`, which only runs on
  an explicit "yes" to file an issue — an outward action confirmed each time regardless, so its
  substitution adds no friction.

## [0.4.3] — 2026-06-08 — Docs: cut the permission-prompt friction

Dogfooding surfaced how often a run asks "allow?" for its own write/fetch steps. A plugin
can't grant permissions itself (a deliberate Claude Code security boundary), so the README
now documents an optional allowlist users can add to their own settings.

### Added
- **README "Optional: fewer permission prompts"** — an opt-in `permissions.allow` block for
  the safe commands CoApply uses (`mkdir`/`cp`/`mv`/`touch`/`python3`/`curl`), noting that
  read-only commands already run without prompting. Entirely optional; never reduces safety.

### Known follow-up
- Some calls are compound (e.g. `X="$(…script.sh)"`) and a few are Write-tool file creations,
  which allowlist rules match poorly. Fully minimizing prompts needs a later pass to simplify
  those calls — tracked, not in this release.

## [0.4.2] — 2026-06-08 — Import leaves unfilled identity fields blank, not masked

Dogfooding a real resume + SAVE surfaced a bug: identity fields the resume didn't provide
(Location, Contact, Portfolio) were written as the template's `<placeholder>` and then
neutralized to `(City, ST)` by the atomic writer. That masked genuinely-empty fields — the
first-run preflight no longer saw them as unfilled, and the parenthetical filler could leak
into a letter.

### Fixed
- **Resume import now leaves unfilled identity fields blank** (keeping the guidance comment),
  never a placeholder or parenthetical filler — so `start` skips them cleanly.
- **`identity.md` is written with a new `write-raw`** (atomic, no neutralization). If a stray
  `<placeholder>` slips through, it stays visible so the preflight catches it instead of
  silently masking an empty field. `skills-experience.md` and the resume keep the neutralizing
  `write` (they may contain `<Xxx>` from resume content). `audit.sh` covers both.

## [0.4.1] — 2026-06-08 — Setup leads with the resume, plain words

Dogfooding 0.4.0 showed setup narrating internal plumbing ("resolving your profile folder,"
"recording it to a flat file") and dumping a file-by-file template report — which buried the
resume request, the whole point of onboarding, behind setup mechanics.

### Changed
- **`/coapply:setup` opens with the resume**, not plumbing. Folder resolution and the
  saved-path write now happen **silently**; the template copy is silent and no-clobber.
- The user's first line is a plain preamble — where their profile lives, in plain words — then
  straight to "paste your resume." No "resolve," "flat file," "settings," "templates," or
  file-by-file dumps surfaced.

## [0.4.0] — 2026-06-08 — Guided onboarding: set up from your resume

Setup used to be the wall: hand-author `identity.md`, `skills-experience.md`, and a resume
from blank templates before your first run. Now you drop in your resume (or answer a few
questions) and CoApply drafts your profile, shows you everything, and saves only when you
type `SAVE`. Built per the review-hardened spec (private apply repo, onboarding-spec §16/§17).

### Added
- **Resume import (a sub-flow of `/coapply:setup`):** paste, or give a path to `.md` / `.txt`
  / `.pdf` (Word → paste or export to PDF). It reads behind a fail-closed sanity gate and a
  reflect-back that catches garbled multi-column PDFs, then drafts `identity.md` +
  `skills-experience.md` + one resume **verbatim** — dates, titles, and employers copied
  exactly, no embellishment, no title inflation. Missing numbers are marked `[GAP:]`, never
  invented. `skills-experience.md` is bloat-capped (~800 words, recency-truncated) because the
  profile is sent on every run.
- **No-resume path:** a short Q&A builds the profile from a quick conversation — for
  career-changers and new grads, so "anyone can use it" holds.
- **One batch review, committed by typing `SAVE`:** each original resume line is shown beside
  the drafted line so you can catch drift; nothing is written until `SAVE`; gaps surface
  low-pressure ("only you know this") and never block "you're ready."
- **First-run routing:** `/coapply:start` and `/coapply:add` run before setup now walk you
  into setup instead of aborting; `start` distinguishes "not set up" / "saved folder broken" /
  "profile not filled in."

### Changed
- `help`, `setup`, and the profile README lead with resume import; `setup` gains resume-import
  triggers and an already-set-up re-run check.
- New `scripts/resume-import.sh` (sanity gate, bloat check, atomic placeholder-neutralized
  writes) + `audit.sh` §12 (field-agnostic prompt grep + helper tests).

### Notes
- Voice and positioning are deliberately **not** drafted from a resume — resume prose is
  voiceless, and positioning is better suggested later from the resume↔job delta.

## [0.3.4] — 2026-06-08 — Feedback offers two paths

Filing feedback shouldn't always cost a full draft. `/coapply:feedback` now asks how you
want to get it to the maintainer, and matches the work (and tokens) to your answer.

### Added
- **A fork up front:** *"draft an issue for you, or just point you to the issue page?"*
  - **Light path** — hands you the GitHub template-chooser link (`/issues/new/choose`),
    your own words to paste, and your version/OS to fill the Environment section. Almost
    no tokens; you write it.
  - **Draft path** — the existing flow: clarify-if-vague, then a faithful ready-to-paste
    issue + one-click prefilled link + opt-in `gh` filing.
- **Ambiguity handling:** a non-answer ("idk", "easiest") re-asks once, then falls back to
  the light path — when consent is unclear, do less on the user's behalf, not more.

### Changed
- The clarify-when-vague step now lives inside the draft path (the light path doesn't need
  it — you write your own issue), so the quick path stays quick.

## [0.3.3] — 2026-06-08 — Feedback asks before it files

0.3.2 stopped the skill inventing *content*, but it still invented *intent*: a vague
remark like "I don't understand" got turned straight into a ready-to-file issue. A
confused user needs a question, not paperwork. Now it pauses.

### Fixed
- **`/coapply:feedback` asks one clarifying question when the input is too vague to be a
  useful report**, then builds the issue from the answer. Specific input ("the gate
  didn't show a fit score") still goes straight through; only thin input ("it's
  confusing", "it didn't work") triggers the single question. It asks once and never
  interrogates — if you say "just file it," it files what you gave it, captured faithfully.

### Changed
- **`scripts/audit.sh`** guards the new clarify-when-vague step against regression.

## [0.3.2] — 2026-06-08 — Feedback skill stops fabricating

The 0.3.0 feedback skill turned a one-line gripe into an invented feature proposal —
filling empty "Why it matters" / "How I imagine it working" sections with rationale and
solutions the user never said. That breaks CoApply's core premise (never fabricate) and
poisons the signal the feature exists to collect. Fixed by removing the structure that
invited it, not just by asking the model to behave.

### Fixed
- **`/coapply:feedback` now captures, doesn't compose.** The issue is the user's own
  words (typo-cleaned) plus the script-collected context — nothing else. Optional
  sections appear only if the user actually gave that information; empty sections and
  `(fill this in)` placeholders are gone, so there's nothing to invent. Added an explicit
  no-fabrication rule, a faithful title rule (restate, don't reframe), and a self-check.

### Changed
- **`scripts/audit.sh`** gains a regression guard (the feedback skill must keep the
  capture-don't-compose rule and must not reintroduce fill-in scaffolding) and an
  always-printed **manual gate**: dogfood every new/changed skill on a realistic input,
  and run three premise questions (fabricates? acts for the user? exposes private data?).
- **`PRINCIPLES.md`** — "Never fabricates" now covers everything the tool writes on your
  behalf, not just application output.

## [0.3.1] — 2026-06-08 — Clearer update path

After updating, plugins only load on a fresh session — so a running session keeps
showing the old version until you restart Claude Code. The docs didn't say that, which
made an update look like it had failed. Fixed the guidance so users (and the tool) point
at the right fix.

### Changed
- **README "Keeping CoApply up to date"** now says to **restart Claude Code** after
  `/plugin marketplace update`, then check the version with `/coapply:help`. Dropped the
  "that's it" line that implied the update was instant.
- **`/coapply:help`** now tells a user whose version looks stale after an update to
  restart Claude Code — and explicitly not to reinstall or re-add the plugin.

## [0.3.0] — 2026-06-08 — `/coapply:feedback`

A frictionless way to report a bug or send an idea — so the soft launch has a real
channel back. Describe what happened in plain words and CoApply turns it into a
**ready-to-file GitHub issue**: a clear title, a structured body (with `_(fill this in)_`
prompts where you didn't cover a section), and auto-collected context — all of which you
review before anything is sent. Same drafts-you-decide ethos as the application gate:
it hands you the issue to post, it never submits for you.

### Added
- **`/coapply:feedback` skill** — infers bug vs. idea from your words (near-zero turns;
  one short question at most), assembles the issue, and gives you (1) a complete
  paste-ready block and (2) a one-click prefilled `issues/new?title=…&labels=…&body=…`
  link. If `gh` is installed and authenticated, it offers — opt-in only, never default —
  to file the issue for you.
- **`scripts/feedback-context.sh`** — deterministic helper so the agent doesn't spend
  tokens (or make mistakes) on context-gathering and URL-encoding. `context` prints the
  reviewable block (CoApply version, Claude Code version, OS, tier, and — only when the
  feedback is about a specific run — that run's phase + which step failed, parsed from
  `_run.json` whether compact or pretty-printed). `url` percent-encodes the prefilled
  issue URL; `repo` prints the repository URL.
- **`.github/ISSUE_TEMPLATE/`** — `bug_report.md` + `idea.md` (same section structure as
  the skill emits) and a `config.yml` pointing usage questions at the README. Guides
  anyone who files directly on GitHub without the skill.

### Privacy
- No silent diagnostics: every byte of collected context is shown before anything is
  sent. The skill and script never read profile contents, cover letters, or resumes —
  only the tool's own version/config and a run's structural state. The bug template
  carries a "kept my profile/letters/secrets out" checkbox.

### Other
- `/coapply:help` now lists `/coapply:feedback`.
- `scripts/audit.sh` gains a section covering the feedback context block, URL encoding,
  and the failed-step parser; `feedback` added to the skill-presence check.

## [0.2.2] — 2026-06-07 — Setup-override safety + help polish

### Fixed
- **`/coapply:setup` no longer clobbers the global profile path when an explicit
  `CLAUDE_PLUGIN_OPTION_PROFILE_DIR` override is active.** Previously, running setup
  under a per-session override (e.g. dogfooding the new-user flow with a temp folder)
  wrote that temp path into `~/.coapply_profile_path`, silently redirecting the user's
  *normal* sessions to it. Setup now writes the flat file only when no env-var override
  is set. Makes the "experience it as a new user" test safe.
- **`/coapply:help` closing line no longer prints a stray `"`** — the deterministic
  next-step line is shown as plain bold text, not wrapped in literal quotes.

## [0.2.1] — 2026-06-07 — Onboarding clarity (help skill)

Sharpened the first-run experience using onboarding-CRO + copy-editing passes.

### Changed
- **`/coapply:help` now opens with a numbered "Getting started (first run — ~5 min)"
  path** — set Profile folder → `/coapply:setup` → fill in 3 files → `/coapply:start`.
  Gives a new user one clear, faceplant-proof sequence instead of a flat command list.
- **Help ends with a real next action, not a question.** It now resolves the profile
  state (no-folder / no-files / empty / ready) and prints exactly one definitive next
  step, instead of asking the user "want me to check?".
- **Reworded "checks billing"** → "confirms how runs are paid (usually your Claude plan
  — no extra charge)" so the cost line reassures instead of alarming.
- (No engine change — `/coapply:start` already guards empty/template profiles via its
  pre-flight placeholder + profile-depth checks.)

## [0.2.0] — 2026-06-05 — The Profile Library

Make CoApply a tool you mold over time by talking to it: give it your own writing
rules, your real letters as voice references, and your everyday facts — and it shows
you exactly what shaped each application. Designed + hardened across 3 review rounds
(2 audits + a 3-model brains trust each); rationale in the private apply repo
(`roadmap docs/coapply-modular-profile-spec-v3.md`). Everything lives in your profile
folder, so plugin updates never touch it. Secrets (SSN-grade) are deliberately out of
scope and refused — that's a later, separate design.

### Added
- **`/coapply:add`** — add a rule, an example, or a fact in plain language ("from now
  on never…", "save this as an example", "remember I'm based in Austin"). It confirms
  where each thing goes (never silent), refuses to store true secrets (no override),
  and caps a rules file at ~20 with a consolidate-or-prune offer so rules don't bloat
  and dilute. `scripts/scan-pii.sh` is the deterministic secret guard: it flags only
  true secrets (SSN, card/bank/account numbers, passwords, API keys, IBANs, exact
  street address), **allows** the everyday middle tier (salary, city, work-auth,
  phone), and prints redacted flags that never include the actual digits.
- **`facts.md`** — a home for everyday personal facts (location, target comp,
  work-authorization, start date) the AI legitimately needs to fill in applications.
  Honest framing: it's sent like the rest of your profile, not a private vault. Read
  by the application-questions and cover-letter agents.
- **Examples (voice few-shot)** — drop real letters/messages in `<profile>/examples/`
  (named `<role>--<tag>--<name>.md`); CoApply uses the most JD-relevant ones as a
  **voice reference only** (imitate cadence, never reuse facts). `scripts/context-pack.sh`
  ranks them by header/JD word-overlap (deterministic `sort` with a filename
  tiebreak), caps by tier (lite none / standard ≤2 / full ≤3) under a byte budget,
  and logs every pick/drop to the run's `.receipt.log`. Wired into the cover-letter,
  outreach, and application-questions agents. The trust receipt now reports which
  examples were **used** vs **set aside** from that log (glob fallback otherwise).
- **Output watermarking** — generated artifacts get an invisible `coapply:generated`
  tag so the upcoming ingest flow can refuse to re-ingest CoApply's own output as an
  "example" (the AI-cannibalism guard).
- **Trust receipt** — every run now ends with a plain-language "What shaped this
  application" block (your background, your rules with a JD-relevant sample, your
  examples) rendered by `scripts/render-receipt.sh`. **Deterministic by design:**
  derived from the filesystem + the run's tier, never the model's recollection.
  Fails closed to "Receipt unavailable" rather than ever implying nothing was used.
  Wired into `master-apply` Step 9, printed verbatim. `audit.sh` regression-tests it.
- **Playbooks** — per-role writing-rule docs in `<profile>/playbooks/<role>.md` the
  agents follow if present (generalizes the `principles.md` pattern). Wired into the 6
  content/strategy agents: cover-letter, positioning, outreach, interview-prep,
  resume-update, application-questions, plus a cross-cutting `general.md`. They're
  hard guidance and override engine defaults where they overlap.
- **Default cover-letter playbook** (`profile.example/playbooks/cover-letter.md`) +
  a plain-language `playbooks/README.md`. Ships universal copy hygiene: don't open by
  explaining the company to itself; keep concrete proof concrete; assert the positive
  directly; no self-promo closers; lead with the work, not the label.

### Version visibility
- **The SessionStart hook now announces the real version when it changes** — e.g.
  `✅ CoApply updated to v0.2.0` on the first session after an update, then stays
  silent. Claude Code auto-applies plugin updates and only shows a generic reload
  notice (the update flow and its lack of an approval step are host behavior a
  plugin can't change), so this is how you confirm which version you're actually on.
- **`/coapply:help` now prints the version** (`CoApply v0.2.0`) as its first line.

### Hardened (after a 7-agent adversarial stress swarm — 0 blockers, 0 serious found)
- **`scan-pii.sh` rewritten to whole-file passes** — ~500× faster on large pastes (no
  per-line subprocess loop); pins `LC_ALL=C` (deterministic, robust to invalid UTF-8);
  now catches modern token shapes (GitHub `ghp_`/`github_pat_`, Stripe `sk_live_`,
  Google `AIza`, GitLab `glpat-`, OpenAI `sk-proj-`, JWTs) and PEM private keys; widens
  card detection to 13-19 digits; and kills false positives (consecutive years read as a
  card, `passwordless`/`secret keynote` substring matches). Still never leaks a digit.
- **`resolve-profile-dir.sh`** — POSIX fallback is now **scoped to CoApply's own config**
  (a different plugin's `profile_dir` can't be picked); honors `settings.local.json` over
  `settings.json`; and truly always exits 0 (no crash when `HOME` is unset).
- **`context-pack.sh`** — pins `LC_ALL=C` for locale-independent ranking; logs the real
  drop reason (count-cap vs over-budget); and skips control-char filenames that could
  make the receipt claim a file was used without emitting it.
- **`render-receipt.sh`** — `- ` lines inside fenced code blocks are no longer counted as
  rules; strips CR so a CRLF-authored playbook doesn't corrupt the quoted sample.
- **`/coapply:help`** now documents `/coapply:add` and the Profile Library (was undiscoverable).
- `audit.sh` extended to 14 checks locking in all of the above.

### Fixed
- **`resolve-profile-dir.sh` had no POSIX fallback** (python3→jq only) — a user with
  neither silently got "not configured" on every command. Added: (1) a robust flat
  `~/.coapply_profile_path` file (written by `/coapply:setup`) as the primary path,
  and (2) a POSIX `grep`/`sed` settings.json fallback so no `python3`/`jq` is required.
  `audit.sh` now regression-tests both with `python3`/`jq` shadowed out.

## [0.1.3] — 2026-06-05 — Docs: saving & parallel-session behavior

Make the persistence/concurrency model explicit so users aren't surprised.

### Added
- **README FAQ** — "Do I need to save before I close?" (no — file-based, auto-saved; mid-run → `/coapply:resume`) and "Can I run several at once / edit my profile in another window?" (parallel runs are safe; don't edit the *same* profile file in two sessions — last save wins, no merge).
- **`/coapply:setup`** ends with a short "good to know": work saves automatically, run as many applications in parallel as you want, don't edit the same profile file in two windows at once.

## [0.1.2] — 2026-06-04 — Fix: profile folder not found (blocked all commands)

**Critical fix.** Every command aborted with "CoApply isn't configured" even when the Profile folder was set, because the skills read `$CLAUDE_PLUGIN_OPTION_PROFILE_DIR` in a Bash-tool call — and Claude Code only exports that variable to plugin *subprocesses* (hooks, MCP), never to the Bash tool a skill runs. So it was always empty for users.

### Fixed
- Added `scripts/resolve-profile-dir.sh`, which resolves the profile folder from the env var when present, then falls back to reading `pluginConfigs."coapply@*".options.profile_dir` from `settings.json` (the value Claude Code reliably saves). Portable: `python3` → `jq`.
- `start`, `setup`, `tier`, `list`, and `resume` now resolve the profile folder via the resolver instead of reading the env var directly.
- The SessionStart nudge hook uses the same resolver as a fallback.

## [0.1.1] — 2026-06-04 — Onboarding next-step guidance

Closes the "now what?" gaps in the first-run experience.

### Added
- **First-run nudge** — a `SessionStart` hook points new users at `/coapply:setup` (or, if no profile folder is set, at `/plugin`) until their profile is configured, then goes permanently silent (keys off whether `identity.md` exists — no state file).
- **Next-step lines** — `/coapply:tier`, `/coapply:list`, and the post-run summary (`/coapply:start` and `/coapply:resume`) now end with an explicit `Next:` line so the user is never left at a blank prompt.
- **README** — the install section now spells out the post-install screens (install scope, the Profile-folder prompt, the confirmation line) and the first step after; plus an optional status-line snippet for a persistent next-step hint.

### Changed
- `/coapply:setup`'s "not configured" message now tells the user to make a profile folder first.

## [0.1.0] — 2026-06-04 — Initial public release

A Claude Code plugin that turns a job posting into a complete, voice-matched, fit-gated application package — pre-screen → research → fit-score → a human go/no-go gate → cover letter, tailored resume guidance, outreach, interview prep. Profile-driven and field-agnostic; never auto-submits.

### Commands
- `/coapply:setup` — first-time setup: copies the profile templates into your folder, checks how your runs are billed, sets a budget tier.
- `/coapply:start <job>` — run an application (pre-screen → triage → cost-aware gate → package).
- `/coapply:tier` — change your budget tier (lite / standard / full) anytime.
- `/coapply:resume <run>` — resume an interrupted run (confirms which run first).
- `/coapply:list` — list recent runs.
- `/coapply:help` — orientation.

### Cost control
- **Budget tiers** — `lite` (cover letter only), `standard` (core package), `full` (everything incl. live company research + .docx). Stored in `coapply.config.json`.
- **Cheap pre-screen** flags obvious no-go roles before any agent runs — skipping a bad fit is nearly free.
- **Cost-aware gate** shows an estimated cost-to-finish + your live billing mode (subscription allowance vs per-token API) and lets you pick full / standard / lite / stop.
- README "Cost & limits" section explains the model honestly, including the `ANTHROPIC_API_KEY` billing caveat.

### Engine
- Skill-based entry points (so `${CLAUDE_PLUGIN_ROOT}` resolves); orchestrator hands subagents absolute paths.
- Master orchestrator + 13 focused agents + 2 phase dispatchers + shared voice/format/anti-AI rules; file-based handoffs; mandatory human checkpoint; retry-once verification; invariants enforced (never fabricate / never auto-submit / stay in lane).
- Robustness: cross-platform run-ID (no `openssl`); LinkedIn URLs prompt for pasted text; unfilled-`<placeholder>` preflight guard; case-insensitive voice lint; `.docx` is full-tier-only and degrades gracefully (never crashes the run).

### Profile & governance
- `profile.example/` field-neutral templates; `/coapply:setup` copies in only the missing ones (never overwrites filled-in files).
- **Optional Notion tracker** — off by default; can be connected during `/coapply:setup` to log applications to a Notion database. Most users skip it; nothing leaves your machine unless you turn it on.
- `PRINCIPLES.md` (invariants), `CLAUDE.md` (contributor rules), `CONTRIBUTING.md`, `SECURITY.md`, `scripts/audit.sh` (release audit), MIT license.

### Known limitations
- Observability is the inspectable run folder + `_run.json`; a richer cost/tracing dashboard is on the roadmap.
- Gate cost figures are rough heuristics, not a live token meter.
- Per-agent model tiering (cheaper models on lite) isn't wired yet — tiers vary the agent *set*, not the model.
- Freelance/proposal mode is held for a later version.
