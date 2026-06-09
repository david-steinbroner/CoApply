---
name: list
description: List your recent application runs.
argument-hint: "[--notion]"
---

# CoApply — List recent application runs

## Step 0 — Resolve the runs folder

Run this **bare** (don't capture it in `VAR="$(…)"` — that can't be allowlisted and would prompt every time). It prints `PROFILE_DIR=…` and `RUNS_DIR=…`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/profile-status.sh"
```

Use the printed `RUNS_DIR` as the absolute runs path below. If `PROFILE_DIR` is empty, tell the user CoApply isn't configured yet (set the Profile folder via `/plugin`).

## Default (filesystem)

If `$ARGUMENTS` is empty or does not contain `--notion`:

List the 10 most recent folders under `${RUNS_DIR}`, sorted by modification time descending. For each, show:
- Folder slug
- Date (from slug prefix)
- Company + role (from `_run.json` if present, otherwise parse slug)
- Status summary: `N/M artifacts done` (from `_run.json.artifacts[].status`)
- Source tag
- If status is partial/failed: offer `/coapply:resume <slug>`

Format as a compact markdown table, one row per run.

Use Bash: `ls -1t "${RUNS_DIR}" | grep -v '^\.' | head -10` to get the list, then Read each `_run.json` in parallel.

If a folder has no `_run.json`, show it with `(stale or aborted)`. If the runs folder is empty, say so.

## --notion mode

If `$ARGUMENTS` contains `--notion`:

Requires an external tracker to be configured — the Applications DB id must be set as `$NOTION_DB_ID` in config. If it's not set, tell the user tracker logging isn't configured and fall back to the filesystem listing above.

If configured, query the Applications DB (using `$NOTION_DB_ID`) via the Notion MCP. Return the most recent 20 entries (Company, Role, Date, Status, Source) as a compact table, date descending.

## Always end with the next step

After the table, close with one forward-pointing line so the user always has a next move:

- If any listed run is partial/failed (resumable): **Next:** `/coapply:resume <slug>` to finish it, or `/coapply:start <job>` for a new application.
- Otherwise: **Next:** `/coapply:start <job url or text>` to begin a new application.

## Errors

- Tracker MCP unavailable → fall back to filesystem + tell the user to retry later.
- Runs folder missing → tell the user to run `/coapply:start` at least once first.
