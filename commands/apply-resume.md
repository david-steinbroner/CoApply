---
description: Resume a partial /apply run — re-runs only the failed or missing artifacts in an existing run folder using _run.json state.
argument-hint: "<run-slug>"
---

# /apply-resume — Resume a partial run

Input in `$ARGUMENTS` is a run folder slug, e.g. `2026-04-21-classdojo-senior-role-7f3a`.

Runs live under `${RUNS_DIR}` (defaults to `${PROFILE_DIR}/runs`). Engine prompts live under `${CLAUDE_PLUGIN_ROOT}`.

## Step 1 — Validate

- Folder must exist: `${RUNS_DIR}/$ARGUMENTS/`
- `_run.json` must exist in that folder

If either missing, abort with: "Run folder or _run.json not found. Use `/runs` to see valid slugs."

## Step 2 — Read state

Read `_run.json`. Identify:
- `source` (the source tag from the original run)
- `artifacts` array — each entry has `name`, `status` (pending/done/failed), `path`
- Any phase checkpoint status

Also re-read the JD from the `jd.txt` file in the run folder (saved during original run).

## Step 3 — Determine what to re-run

Look at each artifact with `status` ∈ {`pending`, `failed`}. Group by phase (research, strategy, content). Re-dispatch only those agents, preserving the already-completed outputs.

If the research phase is incomplete → start from Phase A agents that are missing.
If strategy is incomplete → re-run positioning / prototype / etc.
If only content phase is incomplete → dispatch just the missing content agents (cover-letter, outreach, etc.).

## Step 4 — Follow the master's dispatch rules

Read the master prompt (`${CLAUDE_PLUGIN_ROOT}/profile/prompts/master-apply.md`) and follow its agent-level rules for the agents you need to re-run. Batch size 3. Retry-once on failure.

## Step 5 — Update _run.json after each success

Rewrite `_run.json` after each agent completes. Update artifact status. Update `lastResumedAt` field.

## Step 6 — Final summary

When all artifacts are `done`, print the same "what now" block as a fresh run:
- Cover letter .docx path
- LinkedIn / outreach URLs
- Run folder path
- If Notion logging is enabled (`$NOTION_DB_ID` set in config), ask: "Log to Notion?" — run the notion-log step if yes. If Notion is not configured, skip this prompt.
