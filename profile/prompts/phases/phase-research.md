# Phase A — Research & Strategy (employee mode)

Dispatched from `master-apply.md`. You are the orchestrator; the agents below do the actual work.

**Gated structure (read this first).** Phase A is split by the checkpoint:
- **Wave A1 (Triage)** runs *before* the checkpoint — four cheap agents that produce the go/no-go read (jd-parser, dedup-check, role-analysis, fit-score). No web research, no positioning agent.
- **Wave A2 (Strategy)** runs *only after* the user clears the checkpoint with a go — the three expensive agents (company-research with live web fetches, positioning, work-sample-suggester). On an abort, these never run, so a skip costs four cheap agents instead of seven.

The checkpoint itself lives in `master-apply.md` Step 3. Wave A1 hands back to it; Step 3 dispatches Wave A2 on a go.

## Wave A1 — Triage (cheap; runs BEFORE the checkpoint)

Spawn these agents in parallel (one message, multiple Task calls, `run_in_background: true`). Since there are 4 agents and batch size is 3, split into two batches.

**Model:** set each Task's `model` parameter per the **Model map** in `master-apply.md` Step 3 — active tier × the agent's class (tagged in brackets below). The model is a Task-call parameter, not prompt text.

**Batch 1 of A1 (3 agents in parallel):**
- Task: agent_type `general-purpose`, `[mechanical]`, instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/jd-parser.md` — writes `00-jd-parsed.json`
- Task: agent_type `general-purpose`, `[mechanical]`, instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/dedup-check.md` — writes `00-dedup-check.md`
- Task: agent_type `general-purpose`, `[reasoning]`, instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/role-analysis.md` — writes `01-role-analysis.md`

**Batch 2 of A1 (1 agent):**
- Task: agent_type `general-purpose`, `[reasoning]`, instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/fit-score.md` — writes `02-fit-score.json`

Wave A1 agents each get the **path** to the raw JD — `<run-folder>/jd.txt` — and Read it themselves. (`master-apply.md` Step 0 writes `jd.txt` before any agent is dispatched, so it is always on disk by now. jd-parser runs in this same wave, so `00-jd-parsed.json` isn't available yet to its siblings — the raw file is what they get.) Do **not** paste `$JD_TEXT` into the prompts: a JD is a few thousand tokens and inlining it four times is the single most wasteful thing this wave can do.

**After Wave A1 returns:**

1. Verify each expected file exists under the run folder and is non-empty.
2. For any missing file: re-dispatch that single agent once. Wait 60s first if the failure reason looked rate-limity.
3. If still missing: update `_run.json.artifacts[].status = "failed"`, report to the user, wait for instruction.
4. Update `_run.json.artifacts[].status = "done"` for each successful file.

**Special: Application questions.** When verifying `00-jd-parsed.json`, also inspect its `applicationQuestions` array. If non-empty, set `_run.json.artifacts` for `application-questions` to `pending` (it'll run in Phase B). If empty, set to `skipped`.

**→ Stop here and hand back to `master-apply.md` Step 3 (Checkpoint).** Do NOT run Wave A2 yet. Step 3 dispatches Wave A2 only after the user returns a go (or a `redirect:` that keeps the run alive). On an abort, Wave A2 never runs — this is the whole point of the gate.

## Wave A2 — Strategy (runs ONLY after the checkpoint clears; batch size ≤3)

Run only the agents the **active tier** calls for (tier table in `master-apply.md` Step 3): **lite** → positioning only · **standard** → positioning + company-research · **full** → company-research + positioning + work-sample-suggester. Mark tier-skipped A2 agents `skipped`.

The available A2 agents (set each Task's `model` per the Model map — active tier × the class tagged below):

- Task: agent_type `general-purpose`, `[reasoning]`, instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/company-research.md` — writes `03-company-research.md` (uses WebSearch + WebFetch)
- Task: agent_type `general-purpose`, `[reasoning]`, instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/positioning.md` — writes `04-positioning.md`
- Task: agent_type `general-purpose`, `[reasoning]`, instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/prototype-suggester.md` — writes `05-work-sample-ideas.md`

Each gets in its prompt:
- The run folder path (so it knows where to write)
- The **path** to the parsed JD — `<run-folder>/00-jd-parsed.json` — which the agent Reads itself. Do not inline its contents.

Positioning and work-sample-suggester additionally get (as **file paths**, not inline contents — they Read these themselves):
- `${PROFILE_DIR}/skills-experience.md`
- `${PROFILE_DIR}/positioning-modes.md`
- `${PROFILE_DIR}/portfolio-links.md`

Work-sample-suggester gets one more (as file path): `01-role-analysis.md` from the run folder.

**Why paths, not inline contents:** inlining a file the agent could open is double work — it burns orchestrator context on every dispatch and buys nothing. This applies to *both* kinds of file: static profile files (large and identical across runs) and this run's own artifacts (already on disk in the run folder). Pass the path; the agent reads it once.

**After Wave A2 returns:** verify + retry-once, same as A1.

## Phase A output contract

After **Wave A1 (Triage)**, these four files exist — then hand back to the checkpoint:
- `00-jd-parsed.json`
- `00-dedup-check.md`
- `01-role-analysis.md`
- `02-fit-score.json`

After **Wave A2 (Strategy)** — only reached on a go — these three more exist:
- `03-company-research.md`
- `04-positioning.md`
- `05-work-sample-ideas.md`

All `_run.json.artifacts` statuses updated accordingly.

Wave A1 returns control to `master-apply.md` Step 3 (Checkpoint). Wave A2 returns control to Step 4 (Phase B).

## Inline payload templates for each agent Task prompt

When dispatching a Task agent, set its **`model`** parameter (per the Model map — active tier × the agent's class) on the Task call itself, and structure the prompt like this:

```
You are the <agent-name> agent in $USER_NAME's CoApply pipeline. Follow your instruction file exactly.

YOUR INSTRUCTION FILE (read first) — use the resolved ABSOLUTE path:
<the real absolute ${CLAUDE_PLUGIN_ROOT}>/profile/prompts/agents/<agent-name>.md

PATHS (absolute — your instruction file may show ${PROFILE_DIR} or ${RUNS_DIR}; treat them as these real paths):
- PROFILE_DIR = <the real absolute ${PROFILE_DIR}>
- run folder = <absolute run folder path under ${RUNS_DIR}>

READ THESE YOURSELF (absolute paths — do not expect their contents inlined):
<the run artifacts this agent depends on, e.g. <run folder>/jd.txt or <run folder>/00-jd-parsed.json>
<any ${PROFILE_DIR} files the agent's instruction file calls for>

INPUTS (inlined — only what exists nowhere on disk):
<conversation-derived context only: user-added notes from the checkpoint, a mode override, the $SOURCE tag, today's date>

OUTPUT CONTRACT:
Write your output to: <absolute path in run folder>
Confirm in your reply: "wrote <filename> — <short summary>"

CONSTRAINTS:
- Start with the actual content. No preamble.
- Respect format rules and voice rules from the instruction file.
- If you cannot complete the task with the provided inputs, do NOT guess — return with an error message explaining what's missing.
```

The agent instruction files themselves contain the actual prompt logic. Your Task prompt is just the envelope.
