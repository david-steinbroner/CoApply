---
description: Generate a full job application package from a JD URL or text. Orchestrates research, strategy, and content agents using the user's profile; writes files to the configured runs folder; optionally logs to Notion.
argument-hint: "<url-or-text>"
---

# /apply — Job Application Orchestrator

You are orchestrating a job application package for the user. The input is in `$ARGUMENTS`.

## Step 0 — Resolve paths and identity (do this first, via Bash)

Resolve all paths to ABSOLUTE values up front. Subagents do NOT inherit these variables, so wherever a prompt or instruction file shows `${CLAUDE_PLUGIN_ROOT}`, `${PROFILE_DIR}`, or `${RUNS_DIR}`, you must substitute the real absolute path before handing it to an agent.

Run one Bash call to capture them:

```bash
echo "CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT"
echo "PROFILE_DIR=$CLAUDE_PLUGIN_OPTION_PROFILE_DIR"
echo "RUNS_DIR=${APPLY_RUNS_DIR:-$CLAUDE_PLUGIN_OPTION_PROFILE_DIR/runs}"
```

- **`${CLAUDE_PLUGIN_ROOT}`** — the plugin's install dir; engine prompts live under `${CLAUDE_PLUGIN_ROOT}/profile/prompts/`. (Claude Code also substitutes this token inside plugin content.)
- **`${PROFILE_DIR}`** — the user's profile folder, from the plugin's `profile_dir` config. **If it is empty, abort:** "CoApply isn't configured yet. Run `/plugin`, open CoApply, and set your **Profile folder** — point it at the folder containing your identity.md, skills-experience.md, resumes/, etc."
- **`${RUNS_DIR}`** — where output is written; defaults to `${PROFILE_DIR}/runs`.

From here on, use these absolute values, and substitute them into every subagent prompt and Task dispatch.

Then read `${PROFILE_DIR}/identity.md` and resolve these identity tokens (injected into the master prompt and every downstream agent, so the engine never hardcodes a name, location, or field):

- `$USER_NAME`: the `Name` field — "orchestrating for $USER_NAME", cover-letter signature, resume header.
- `$USER_FIRST_NAME`: the first whitespace-delimited token of `$USER_NAME`.
- `$USER_LOCATION`: the `Location` field — location-aware lines; skip if empty/absent.
- `$USER_PORTFOLIO`: the `Portfolio` field — portfolio links; skip if empty or `(none)`.
- `$USER_TARGETS`: the `Target roles` field — **replaces every field assumption** in fit-score, triage, and role-analysis. Treat it as "the user's field" wherever a discipline is implied.

If `identity.md` is missing one of these fields, use a sensible empty/skip behavior; do not invent a value.

## Step 1 — Resolve input

$ARGUMENTS contains one of:
- A URL (starts with `http://` or `https://`) — use WebFetch to get the page
- Free-text JD (anything else)
- Empty — ask the user: "Paste a JD URL or the full text."

If URL: canonicalize it (lowercase hostname, strip `www.`, strip query string and fragment) BEFORE any downstream use (hashing, dedup, routing).

## Step 2 — Pre-flight checks (abort fast if any fail)

Run these in parallel, fail fast with clear error messages:

1. Verify `${PROFILE_DIR}/identity.md` exists (the token source from Step 0). If missing, abort with: "No identity.md found at ${PROFILE_DIR}/identity.md. Run profile setup first — the engine needs your name, location, portfolio, and target roles."
2. Verify write access to `${RUNS_DIR}` (Bash: `touch ${RUNS_DIR}/.preflight && rm ${RUNS_DIR}/.preflight`).
3. Verify master prompt exists: `${CLAUDE_PLUGIN_ROOT}/profile/prompts/master-apply.md`.
4. Verify required profile files exist: `${PROFILE_DIR}/{skills-experience.md,positioning-modes.md,voice-profile.md}`. (`portfolio-links.md` and `principles.md` are optional — do not abort if they are absent.)
5. Verify at least one resume variant exists in `${PROFILE_DIR}/resumes/` (Bash: confirm `${PROFILE_DIR}/resumes/` contains at least one `*.md` file).

If any check fails, abort and tell the user exactly which file/path is missing.

## Step 3 — Source routing

Read `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/source-routing.md`. Apply the hostname-match rules to the URL (or set `Other` if text-only input).

**Aggregator rejection:** if the URL matches indeed.com / glassdoor.com / ziprecruiter.com / simplyhired.com / monster.com / careerbuilder.com → abort with: "That's an aggregator page. Paste the original company URL (from the company's career page, Greenhouse, Lever, Workday, etc.)."

## Step 4 — Route to master prompt

Detect whether this is a contract / freelance / proposal-style posting (e.g. source resolves to `Upwork`, or the JD is clearly a freelance gig rather than an employee role).

- **If a contract/freelance role is detected:** surface this to the user rather than routing. Say something like: "This looks like a freelance/contract posting (source: <source>). Freelance/proposal mode isn't part of this version yet — it's coming later. Want me to run it as a standard application package instead, or skip it?" Wait for the user's decision before continuing. (Do not route to a master-apply-upwork.md — the Upwork master and agents are held out of this version.)
- **Otherwise (standard employee role):** read `${CLAUDE_PLUGIN_ROOT}/profile/prompts/master-apply.md`.

Follow that master prompt exactly. It handles the rest (research, checkpoint, content generation, file writes, optional Notion log).

## Step 5 — Pass required inputs to the master

The master prompt needs the following inputs — inject them at the top of your next action, together with the identity tokens resolved in Step 0 (`$USER_NAME`, `$USER_FIRST_NAME`, `$USER_LOCATION`, `$USER_PORTFOLIO`, `$USER_TARGETS`):

- `$SOURCE`: the source tag from Step 3
- `$JD_URL`: the canonicalized URL, or `(text-only)` if pasted text
- `$JD_TEXT`: the full JD text (from WebFetch, or pasted)
- `$TIMESTAMP`: current ISO-8601 timestamp
- `$RUN_ID`: a 4-character hash — generate with `openssl rand -hex 2` via Bash

## Constraints for this command

- **Never generate JD content yourself** — always dispatch via Task tool as the master prompt instructs.
- **Max 3 parallel Task agents per batch** (per the master's batching rules).
- **Write every agent output to disk** in the run folder (under `${RUNS_DIR}`) before moving on.
- **Verify each file exists and is non-empty** after agent completion. If an expected file is missing after a Task reports done, re-run that one agent once; if still missing, report state and wait for instruction.

## Failure handling

- **WebFetch returns <500 chars or contains login/captcha markers:** fall back to asking the user to paste the text.
- **Any Task agent failure:** retry once with 60s pause. If still failing, report which agents completed vs. failed and wait.
- **Notion MCP failure at log-time:** only relevant if Notion logging is enabled (`$NOTION_DB_ID` set in config). If it fails, write `_notion_log_pending.md` with the formatted payload and tell the user to paste manually.
