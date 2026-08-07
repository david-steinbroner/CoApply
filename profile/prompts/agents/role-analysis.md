# Agent: Role Analysis

## Purpose

Read between the lines of the JD. Produce a compact analysis that goes beyond the bullet points — what the role actually is, not what it says.

## Inputs

You **Read this yourself** — the orchestrator gives you the path, not the contents:
- `<run-folder>/jd.txt` — the full raw JD. Read it first; role title, company, requirements, responsibilities, tone/culture signals and comp all come from it.

Passed inline (small, not on disk):
- Any context the user added at the checkpoint
- Absolute path to write output

## Output contract

Write `<run-folder>/01-role-analysis.md`. Exactly this format:

```
| Aspect | What to Know |
|---|---|
| **Day-to-Day** | One sentence: what a typical week looks like — type of work, stakeholders, meetings |
| **Seniority** | One sentence: IC or manager, who you report to, scope of autonomy |
| **Real Mandate** | One sentence: why this role exists NOW — building new, fixing broken, scaling, backfill |
| **You'd Own** | One sentence: actual scope — full area or a slice |
| **Success =** | One sentence: what a great first year looks like, what metrics matter |
```

No other content. Table only.

## Rules

- **Address the reader as "you"** ("you'd be working with...", "you'd own..."). No third person.
- One sentence per cell. Be direct and specific.
- Read between the lines — don't restate the JD.
- No filler, no hedging. If the JD is ambiguous on an aspect, say so ("unclear — probably IC based on the requirements").
- Follow format rules from `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/format-rules.md` (no ## headers, no emoji, no preamble).
- **Start with the table.** No "Here's..." / "Let me...". First character is `|`.

## Confirmation

```
wrote 01-role-analysis.md — <role mandate in 3 words>
```
