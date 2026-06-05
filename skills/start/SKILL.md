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

**User paths.** Resolve these with one Bash call. The resolver reads your saved profile folder from the plugin config — it checks `$CLAUDE_PLUGIN_OPTION_PROFILE_DIR` first, then falls back to `settings.json`, because that env var is NOT exported into skill Bash calls (only into plugin subprocesses):

```bash
PROFILE_DIR="$("${CLAUDE_PLUGIN_ROOT}/scripts/resolve-profile-dir.sh")"
echo "PROFILE_DIR=$PROFILE_DIR"
echo "RUNS_DIR=${APPLY_RUNS_DIR:-$PROFILE_DIR/runs}"
```

- **`${PROFILE_DIR}`** — the user's profile folder. **If it is empty, abort:** "CoApply isn't configured yet. Run `/plugin`, open CoApply, and set your **Profile folder** — point it at the folder containing your identity.md, skills-experience.md, resumes/, etc."
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
- Empty — ask the user: "Paste a JD URL or the full text."

If URL: canonicalize it (lowercase hostname, strip `www.`, strip query string and fragment) BEFORE any downstream use (hashing, dedup, routing).

## Step 2 — Pre-flight checks (abort fast if any fail)

Run these, fail fast with clear error messages:

1. `${PROFILE_DIR}/identity.md` exists (the token source from Step 0). If missing, abort with the "not configured" message above.
2. Write access to `${RUNS_DIR}` (Bash: `mkdir -p "${RUNS_DIR}" && touch "${RUNS_DIR}/.preflight" && rm "${RUNS_DIR}/.preflight"`).
3. Master prompt exists: `${CLAUDE_PLUGIN_ROOT}/profile/prompts/master-apply.md`.
4. Required profile files exist: `${PROFILE_DIR}/{skills-experience.md,positioning-modes.md,voice-profile.md}`. (`portfolio-links.md` and `principles.md` are optional — do not abort if absent.)
5. At least one resume variant exists in `${PROFILE_DIR}/resumes/` (Bash: confirm it contains at least one `*.md`).
6. **No leftover template placeholders:** grep `identity.md` and `skills-experience.md` for unfilled template tokens — angle-bracket tokens that start with a capital letter (`grep -nE '<[A-Z][^>]*>'`), which catches `<Your Name>`, `<Company>`, `<City, ST...>` without false-tripping on lowercase HTML like `<br>` or comparisons like `< 5`. If found, abort: "Your profile still has template placeholders (e.g. `<Your Name>`). Fill them in first — run `/coapply:setup` if you haven't set up yet."
7. **Profile depth (soft — warn, don't abort):** if `skills-experience.md` is very thin (under ~250 words) or has no quantified detail (no digits / `%` / `$`), warn before proceeding: "Heads up — your skills-experience.md looks brief. CoApply writes best from specific, quantified stories; a thin profile tends to produce a generic letter. Add more detail for a stronger result, or continue as-is?" Continue if the user wants; this is guidance, not a blocker.

If any check fails, abort and tell the user exactly which file/path is missing.

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
