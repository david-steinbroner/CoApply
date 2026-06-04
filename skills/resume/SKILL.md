---
name: resume
description: Resume a paused or interrupted application run.
argument-hint: "<run-slug>"
---

# CoApply — Resume a partial run

Input in `$ARGUMENTS` is a run folder slug, e.g. `2026-04-21-acme-senior-role-7f3a`.

## Step 0 — Resolve paths, identity, and tier (same as `start`)

The engine prompts live under `${CLAUDE_PLUGIN_ROOT}/profile/prompts/` (substituted to the real install dir in this skill — use the resolved value, and substitute it wherever an engine file shows `${CLAUDE_PLUGIN_ROOT}`; subagents get the real absolute path).

A resumed run needs the SAME inputs a fresh run does. Resolve them with Bash, exactly like `start`:

```bash
echo "PROFILE_DIR=$CLAUDE_PLUGIN_OPTION_PROFILE_DIR"
echo "RUNS_DIR=${APPLY_RUNS_DIR:-$CLAUDE_PLUGIN_OPTION_PROFILE_DIR/runs}"
```

Then read `${PROFILE_DIR}/identity.md` → `$USER_NAME`, `$USER_FIRST_NAME`, `$USER_LOCATION`, `$USER_PORTFOLIO`, `$USER_TARGETS`. These get injected into every agent you re-dispatch.

## Step 1 — Pick the run (always confirm)

- If `$ARGUMENTS` names an existing folder under `${RUNS_DIR}`: show its company / role / `phase` and ask **"Resume this one?"** before any work.
- Otherwise: list resumable runs — folders whose `_run.json` `phase` is **not** `done` and **not** `aborted` — with company / role / phase, and ask which to resume. Never auto-pick, even with one run.

Verify the chosen run's `_run.json` exists (abort with "No _run.json — use `/coapply:list`." if missing). Read it: note the root `phase`, the per-artifact `status`, the recorded `tier` (use it; fall back to `${PROFILE_DIR}/coapply.config.json`, default `standard`), and re-read the JD from `jd.txt`.

## Step 2 — Resume BY PHASE (the gate stays mandatory)

Pick up exactly where the run left off — and **never skip the human checkpoint.**

- **`done`** → nothing to resume; tell the user it's complete.
- **`aborted`** → do not resume by default. Ask: "This run was aborted (<reason>). Reopen it anyway?" Continue only on an explicit yes.
- **`triage`** → finish any missing Wave A1 agents (jd-parser, dedup-check, role-analysis, fit-score), then **go to the checkpoint** (`master-apply.md` Step 3). Do NOT run A2/B yet.
- **`awaiting_checkpoint`** → the run paused at the gate. **Re-present the go/no-go checkpoint** — rebuild the Step 3 summary from the existing triage files (fit, provisional mode, cost-to-finish, tier, dedup) and wait for the user's decision. Do NOT run A2/B until they say go. *Resuming must never bypass the gate.*
- **`strategy`** → the gate was already cleared. Resume Wave A2 (only the active tier's agents) for any `pending`/`failed` artifact, then Phase B.
- **`content`** → resume only the `pending`/`failed` Phase B agents for the active tier.

## Step 3 — Re-dispatch (follow the master)

For whatever needs to run, follow `master-apply.md`'s rules: active-tier agent set, batch size ≤3, retry-once, inline run-specific context (the JD + prior-wave files), and **substitute real absolute paths** into every subagent prompt.

## Step 4 — Update state

Rewrite `_run.json` after each agent completes: update the artifact `status`, advance the root `phase`, set `lastResumedAt`.

## Step 5 — Final summary

When the active tier's artifacts are all `done`, print the same "what now" block as a fresh run, listing ONLY the artifacts actually produced. The optional tracker step runs only if the user connected one.
