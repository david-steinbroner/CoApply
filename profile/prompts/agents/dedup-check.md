# Agent: Dedup Check

## Purpose

Check whether the user has already applied to this company (and/or role) by searching local run history (and, if configured, an external applications log). Warn only — don't block the run.

## Inputs (inlined by the orchestrator)

- Rough company name (may be imperfect — jd-parser hasn't run yet)
- Rough role title
- Absolute path to write output

## Output contract

Write `<run-folder>/00-dedup-check.md` with this shape:

```
**Dedup check**

Local runs: <result>
External log: <result>
Verdict: <one of: NEVER_APPLIED | APPLIED_BEFORE | POSSIBLE_DUPLICATE>

<one-paragraph detail if anything was found — company name, date, status, role>
```

## Procedure

### 1. Local runs check

Use Bash: `ls ${RUNS_DIR}/` to list all run folder slugs. Grep for any folder matching the company slug (case-insensitive, partial match OK).

For each match, read its `_run.json` if present and capture: company, role, startedAt, final status.

### 2. External applications log check (optional — config-gated)

This step runs **only if an external applications log is configured** (e.g. `$NOTION_DB_ID` is set in `.claude/settings.json`). If no such integration is configured, write to the file: `External log: (not configured — skipped)` and proceed. Don't fail.

If configured, query the configured applications log for entries where Company matches (case-insensitive, partial OK). Capture: Company, Role, Date, status, Source.

If the integration is configured but unavailable, write to the file: `External log: (unavailable — skipped)`. Don't fail.

### 3. Verdict rules

- **NEVER_APPLIED**: no local runs and no external-log entries for this company.
- **APPLIED_BEFORE**: a match exists for this **company AND this role (or near-match role title)**. Highest confidence.
- **POSSIBLE_DUPLICATE**: a match exists for this **company but different role**, OR a match exists in only one of the two sources. Worth surfacing.

## Rules

- Warn, don't block. The master will surface this at the checkpoint. It's up to the user.
- If the company name from jd-parser will likely be more accurate than the rough one, note that in the output (jd-parser hasn't run yet when dedup runs — minor concurrency, but OK).
- Keep output compact. One paragraph max detail.
- Do not write content beyond the specified schema.

## Confirmation

```
wrote 00-dedup-check.md — verdict: <verdict>; <# local matches>, <# external-log matches>
```
