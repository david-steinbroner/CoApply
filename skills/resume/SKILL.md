---
name: resume
description: Resume a paused or interrupted application run.
argument-hint: "<run-slug>"
---

# CoApply — Resume a partial run

Input in `$ARGUMENTS` is a run folder slug, e.g. `2026-04-21-acme-senior-role-7f3a`.

## Step 0 — Resolve paths

The engine prompts live under `${CLAUDE_PLUGIN_ROOT}/profile/prompts/` (that path is substituted to the real install dir in this skill — use the resolved value, and substitute it wherever an engine file you read shows `${CLAUDE_PLUGIN_ROOT}`; subagents get the real absolute path).

Resolve the runs folder with Bash:

```bash
echo "RUNS_DIR=${APPLY_RUNS_DIR:-$CLAUDE_PLUGIN_OPTION_PROFILE_DIR/runs}"
```

## Step 1 — Pick the run (always confirm before resuming)

- If `$ARGUMENTS` names an existing folder under `${RUNS_DIR}`: that's the likely target — but still show its company / role / status and ask **"Resume this one?"** before doing any work.
- If `$ARGUMENTS` is empty or doesn't match a folder: list the resumable runs (folders whose `_run.json` status is not `done`), each with company / role / status, and **ask the user which one to resume.** Do NOT auto-pick — even if there is only one run, confirm first.

Once the user confirms a run, verify its `_run.json` exists (abort with "No _run.json in that run — use `/coapply:list`." if missing), then proceed.

## Step 2 — Read state

Read `_run.json`. Identify:
- `source` (the source tag from the original run)
- `artifacts` array — each entry has `name`, `status` (pending/done/failed), `path`
- Any phase checkpoint status

Also re-read the JD from `jd.txt` in the run folder.

## Step 3 — Determine what to re-run

Look at each artifact with `status` ∈ {`pending`, `failed`}. Group by phase (research, strategy, content). Re-dispatch only those agents, preserving completed outputs.

## Step 4 — Follow the master's dispatch rules

Read the master prompt (`${CLAUDE_PLUGIN_ROOT}/profile/prompts/master-apply.md`) and follow its agent-level rules for the agents you need to re-run. Batch size 3. Retry-once on failure. Substitute real absolute paths into every subagent prompt.

## Step 5 — Update _run.json after each success

Rewrite `_run.json` after each agent completes. Update artifact status. Update `lastResumedAt`.

## Step 6 — Final summary

When all artifacts are `done`, print the same "what now" block as a fresh run (cover-letter docx path, outreach URLs, run folder path). If a tracker is configured (`$NOTION_DB_ID`), offer to log it; otherwise skip.
