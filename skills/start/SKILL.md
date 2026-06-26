---
name: start
description: Begin an application from a job posting (URL or text).
argument-hint: "<url-or-text>"
---

# CoApply — Job Application Orchestrator

You are orchestrating a job application package for the user. The input is in `$ARGUMENTS`.

## Step 0 — Resolve paths and identity (do this first)

**Engine root.** The CoApply engine prompts live under this absolute path:

> `${CLAUDE_PLUGIN_ROOT}/profile/prompts/`

`${CLAUDE_PLUGIN_ROOT}` is substituted to the real install path in this skill — so the line above already shows the real absolute base. Use that resolved value, and substitute it wherever any engine file you later read shows `${CLAUDE_PLUGIN_ROOT}`. Subagents cannot resolve the variable, so always hand them the real absolute path.

**User paths + first-run routing — one Bash call.** Resolve the profile folder *and* its readiness with a single call. Run it **bare** — capturing it in `VAR="$(…)"` can't be allowlisted, so it would prompt on every run. The script resolves your saved profile folder (it checks `$CLAUDE_PLUGIN_OPTION_PROFILE_DIR` first, then falls back to `settings.json`, because that env var is NOT exported into skill Bash calls — only into plugin subprocesses), then probes the folder:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/profile-status.sh"
```

It prints these fields; use the printed `PROFILE_DIR` and `RUNS_DIR` as your absolute paths from here on, and substitute them into every subagent prompt and Task dispatch:

```
PROFILE_DIR=…   RUNS_DIR=…   WRITABLE=yes|no
IDENTITY=yes|no   SKILLS=yes|no   RESUME=yes|no   PLACEHOLDERS=yes|no
```

**First-run routing — warm route, never a raw abort.** A user who runs `/coapply:start` before they've set up should be walked into setup, not hit a dead end. Map the fields to one `STATE`:
- `PROFILE_DIR` empty → `not-set`
- `WRITABLE=no` → `bad-path`
- otherwise, build a `MISSING` list from the flags — `IDENTITY=no` → `identity.md`, `SKILLS=no` → `skills-experience.md`, `RESUME=no` → `a-resume`, `PLACEHOLDERS=yes` → `unfilled-placeholders`. If `MISSING` is non-empty → `not-ready` (with that list); otherwise → `ok`.

- **`STATE=not-set`** (no Profile folder yet) — the one step CoApply can't do for them (it's
  the `/plugin` GUI). Give a numbered path with a return cue, not a bare error:
  > Let's get you set up first — quick. **1.** Make a new empty folder, e.g. `~/coapply-profile`.
  > **2.** Run `/plugin`, open **CoApply**, set **Profile folder** to that path. **3.** Run
  > **`/coapply:setup`** — you can build your whole profile from your resume in about two minutes.
  > Then re-run `/coapply:start` with this job and I'll pick up right here.

  Then stop.
- **`STATE=bad-path`** (a saved path that's missing or not writable — *different* from not-set):
  > Your saved Profile folder (`${PROFILE_DIR}`) isn't there or isn't writable anymore. Re-point
  > it via `/plugin` → CoApply → **Profile folder** (or recreate that folder), then re-run `/coapply:start`.

  Then stop.
- **`STATE=not-ready`** (folder is fine, profile isn't filled in — `$MISSING` says what's
  absent) — warm-route into setup; don't cold-abort over a missing file:
  > Your profile isn't finished yet (missing: `<the MISSING list, in plain words>`). Run
  > **`/coapply:setup`** and I'll build it from your resume in a couple of minutes — then re-run
  > `/coapply:start` with this job.

  Then stop.
- **`STATE=ok`** — continue.

- **`${RUNS_DIR}`** — where output is written; defaults to `${PROFILE_DIR}/runs`. Create it if it doesn't exist (`mkdir -p`).

From here on use these absolute values, and substitute them into every subagent prompt and Task dispatch.

Then read `${PROFILE_DIR}/identity.md` and resolve these identity tokens (injected into the master prompt and every downstream agent, so the engine never hardcodes a name, location, or field):

- `$USER_NAME`: the `Name` field — "orchestrating for $USER_NAME", cover-letter signature, resume header.
- `$USER_FIRST_NAME`: the first whitespace-delimited token of `$USER_NAME`.
- `$USER_LOCATION`: the `Location` field — location-aware lines; skip if empty/absent.
- `$USER_PORTFOLIO`: the `Portfolio` field — portfolio links; skip if empty or `(none)`.
- `$USER_TARGETS`: the `Target roles` field — **replaces every field assumption** in fit-score, triage, and role-analysis. Treat it as "the user's field" wherever a discipline is implied.

If `identity.md` is missing one of these fields, use a sensible empty/skip behavior; do not invent a value.

Also read `${PROFILE_DIR}/coapply.config.json` for the budget tier → `$TIER` (`lite` / `standard` / `full`; default `standard` if the file is absent). Pass `$TIER` to the master prompt.

## Step 1 — Resolve input

$ARGUMENTS contains one of:
- A **LinkedIn job URL** (`linkedin.com/jobs/...`) — WebFetch is blocked there, so do NOT fetch it. Ask: "LinkedIn blocks automatic reading — paste the job description text and I'll take it from there." Use the pasted text as the JD (source = `LinkedIn`).
- Another URL (starts with `http://` or `https://`) — use WebFetch to get the page
- Free-text JD (anything else)
- **Empty — first check for a hub *apply queue*, then fall back to asking.** The hub (`/coapply:hub`)
  lets the user stage roles; consuming that queue is a **gate hand-off**, never an auto-run. Read
  `${RUNS_DIR}/.coapply_queue.json` (a plain read — `cat` it; if the file is absent or its `items`
  array is empty, skip to the plain prompt below). If it has items:
  - Show them as a compact list under a heading like **"You have N role(s) staged in the hub"** — one
    row per item: `company · title · link`.
  - Then **emit one ready-to-run `/coapply:start <url>` command per item**, each on its own line, for
    the user to run at their own pace — exactly like `/coapply:discover`'s hand-off (no batch
    auto-routing). Do **not** WebFetch, do **not** call any agent, do **not** write anything — the hub
    is the **only** writer of the queue file, so leave it untouched (a role's "queued" state clears on
    its own once it gains a run). Then **stop.** The user runs the per-job commands themselves; each
    one re-enters this skill *with* a URL and hits its own fit gate.
  - Mention they can instead paste a JD URL or full text to start a different role.
  - If the queue is absent or empty: ask "Paste a JD URL or the full text."

If URL: canonicalize it (lowercase hostname, strip `www.`, strip query string and fragment) BEFORE any downstream use (hashing, dedup, routing).

**Discovery fingerprint (single-ledger dedup, spec §3.3).** If the canonicalized URL is a public ATS *posting* URL (Greenhouse/Lever/Ashby), stamp this run so `/coapply:discover` won't resurface a job you've already acted on. Run **bare**:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/discover-fetch.py" --fp-from-url "<canonicalized-url>"
```

If it exits 0, it prints `fp=<sha1>`; set `$DISCOVERY_FP` to that value. If it exits non-zero (a branded/non-ATS URL, or pasted text), leave `$DISCOVERY_FP` empty — that's correct: the run simply carries no fingerprint and isn't deduped against the watchlist. This is the discover↔start shared ledger: discover derives the same `sha1(ats|token|id)` from the same URL, so the two never drift.

## Step 2 — Pre-flight checks

Step 0's first-run routing already gated profile *readiness* (identity, skills-experience,
a resume, no placeholders) — so by here the profile is filled in. These remaining checks
cover infrastructure and a soft quality nudge.

1. **Write access to `${RUNS_DIR}`** (Bash: `mkdir -p "${RUNS_DIR}" && touch "${RUNS_DIR}/.preflight" && rm "${RUNS_DIR}/.preflight"`). If this fails, report the exact path and stop.
2. **Master prompt exists:** `${CLAUDE_PLUGIN_ROOT}/profile/prompts/master-apply.md`. If missing, report it (an engine problem, not a user one) and stop.
3. **Required profile files exist:** `${PROFILE_DIR}/{positioning-modes.md,voice-profile.md}` (templates from setup count). (`portfolio-links.md` and `principles.md` are optional — don't abort if absent.) If either is somehow missing, **warm-route, don't cold-abort:** "Your profile's missing `<file>` — run `/coapply:setup` to restore it (it can rebuild from your resume), then re-run." Then stop.
4. **Profile depth (soft — warn, don't abort):** if `skills-experience.md` is very thin (under ~250 words) or has no quantified detail (no digits / `%` / `$`), warn before proceeding: "Heads up — your skills-experience.md looks brief. CoApply writes best from specific, quantified stories; a thin profile tends to produce a generic letter. Add more detail for a stronger result, or continue as-is?" Continue if the user wants; this is guidance, not a blocker.

## Step 3 — Source routing

Read `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/source-routing.md`. Apply the hostname-match rules to the URL (or set `Other` if text-only input).

**Aggregator rejection:** if the URL matches indeed.com / glassdoor.com / ziprecruiter.com / simplyhired.com / monster.com / careerbuilder.com → abort with: "That's an aggregator page. Paste the original company URL (from the company's career page, Greenhouse, Lever, Workday, etc.)."

## Step 4 — Route to master prompt

Detect whether this is a contract / freelance / proposal-style posting (e.g. source resolves to `Upwork`, or the JD is clearly a freelance gig rather than an employee role).

- **If a contract/freelance role is detected:** surface this to the user rather than routing. Say something like: "This looks like a freelance/contract posting (source: <source>). Freelance/proposal mode isn't part of this version yet — it's coming later. Want me to run it as a standard application package instead, or skip it?" Wait for the user's decision. (Do not route to a master-apply-upwork.md — the freelance master and agents are held out of this version.)
- **Otherwise (standard employee role):** read `${CLAUDE_PLUGIN_ROOT}/profile/prompts/master-apply.md`.

Follow that master prompt exactly. It handles the rest (research, checkpoint, content generation, file writes, optional tracker log).

## Step 5 — Pass required inputs to the master

The master prompt needs these inputs — inject them at the top of your next action, together with the identity tokens from Step 0 (`$USER_NAME`, `$USER_FIRST_NAME`, `$USER_LOCATION`, `$USER_PORTFOLIO`, `$USER_TARGETS`) and the resolved absolute paths (`${CLAUDE_PLUGIN_ROOT}`, `${PROFILE_DIR}`, `${RUNS_DIR}`):

- `$SOURCE`: the source tag from Step 3
- `$JD_URL`: the canonicalized URL, or `(text-only)` if pasted text
- `$JD_TEXT`: the full JD text (from WebFetch, or pasted)
- `$TIMESTAMP`: current ISO-8601 timestamp
- `$RUN_ID`: a 4-character hex id — generate cross-platform via Bash `python3 -c "import secrets;print(secrets.token_hex(2))"` (fallback: `printf '%04x' $((RANDOM % 65536))`). Avoid `openssl` (not on native Windows) and avoid `tail -c` tricks (trailing-newline bugs).
- `$DISCOVERY_FP`: the discovery fingerprint from Step 1 (empty string if none) — master records it in `_run.json` for single-ledger dedup.

## Constraints for this skill

- **Never generate JD content yourself** — always dispatch via Task tool as the master prompt instructs.
- **Substitute real absolute paths** into every subagent prompt — never pass a literal `${...}` to a subagent.
- **Max 3 parallel Task agents per batch** (per the master's batching rules).
- **Write every agent output to disk** under `${RUNS_DIR}` before moving on.
- **Verify each file exists and is non-empty** after agent completion. If missing after a Task reports done, re-run that one agent once; if still missing, report state and wait.

## Failure handling

- **WebFetch returns <500 chars or contains login/captcha markers:** fall back to asking the user to paste the text.
- **Any Task agent failure:** retry once with 60s pause. If still failing, report which agents completed vs. failed and wait.
- **Tracker log failure:** only relevant if logging is enabled (`$NOTION_DB_ID` set in config). If it fails, write `_tracker_log_pending.md` with the formatted payload and tell the user to paste manually.
