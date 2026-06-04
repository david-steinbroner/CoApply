---
description: List recent /apply runs. Default shows last 10 from the filesystem; --notion flag queries the configured Notion Applications DB for full history.
argument-hint: "[--notion]"
---

# /runs — List recent application runs

Runs live under `${RUNS_DIR}` (defaults to `${PROFILE_DIR}/runs`).

## Default (filesystem)

If `$ARGUMENTS` is empty or does not contain `--notion`:

List the 10 most recent folders under `${RUNS_DIR}`, sorted by modification time descending. For each, show:
- Folder slug
- Date (from slug prefix)
- Company + role (from `_run.json` if present, otherwise parse slug)
- Status summary: `N/M artifacts done` (from `_run.json.artifacts[].status`)
- Source tag
- If status is partial/failed: offer `/apply-resume <slug>` command

Format as a compact markdown table. One row per run.

Use Bash: `ls -1t ${RUNS_DIR} | grep -v '^\.' | head -10` to get the list, then Read each `_run.json` in parallel (one tool call with multiple Read invocations).

If a folder has no `_run.json`, show it with `(stale or aborted)` note.

If the runs folder is empty, say so.

## --notion mode

If `$ARGUMENTS` contains `--notion`:

Notion mode requires Notion logging to be enabled — the Applications DB id must be set in config as `$NOTION_DB_ID` (in `.claude/settings.json`). If `$NOTION_DB_ID` is not set, tell the user Notion logging isn't configured and fall back to the filesystem listing above.

If configured, query the Notion Applications DB (using `$NOTION_DB_ID`) via the Notion MCP. Return the most recent 20 entries, showing:
- Company
- Role
- Date
- Status
- Source

Format as a compact table, date descending.

## Errors

- Notion MCP unavailable → fall back to filesystem + tell user to retry Notion later.
- Runs folder missing → tell user to run `/apply` at least once first.
