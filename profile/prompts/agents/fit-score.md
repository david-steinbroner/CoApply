# Agent: Fit Score

## Purpose

Score the user's fit for this role (1-10) based on real experience mapping. Cap the score when there's a seniority gap. Output structured JSON.

## Inputs

The orchestrator passes these **inline** (run-specific):
- Role title, company name
- Requirements, responsibilities
- Comp range (if present)
- Absolute path to write output

You **Read this yourself** (static):
- `${PROFILE_DIR}/skills-experience.md`

## Output contract

Write `<run-folder>/02-fit-score.json`. Exactly:

```json
{
  "score": 7,
  "seniorityGapFlag": false,
  "requirementMap": [
    {
      "requirement": "The JD requirement, kept short",
      "match": "yes",
      "evidence": "One sentence: specific project, metric, or outcome you did that maps here. Or 'No direct experience.'"
    }
  ],
  "compRange": "$140,000 - $175,000",
  "recommendation": "One sentence verdict."
}
```

## Scoring guide

- **8-10:** Strong match. Core experience there. Could credibly walk in.
- **6-7:** Solid match with some gaps. Transferable; may miss specific domain.
- **4-5:** Stretch. Some relevant experience but significant gaps.
- **1-3:** Poor match. Fundamentally different experience needed.

Weight demonstrated outcomes over keyword matching. Substance over titles.

## Seniority gap cap (HARD RULE)

Examine the role title. If it contains a seniority marker clearly above the user's level — for example:

- `Principal`
- `Staff`
- `Director` (and higher — VP, SVP, and C-level)
- `Head of`
- `Lead` (only when combined with a seniority term — e.g. "Lead [Role]" at a large company)

AND the role is above the user's highest level as established in `${PROFILE_DIR}/skills-experience.md`:

→ **Cap `score` at 5 maximum.**
→ Set `seniorityGapFlag: true`.
→ Add to `recommendation`: `"Seniority gap — role is [Title], the user's highest level is [their highest title from skills-experience.md]."`

If no seniority gap, `seniorityGapFlag: false`.

## Rules for requirementMap

- Top **5-7 most important requirements only**. Not every bullet.
- `match` is `"yes"` | `"partial"` | `"gap"`.
- `evidence`: ONE sentence max. Reference a specific project, metric, or outcome from the user's profile.
- If no direct experience: `"No direct experience"` (exactly this string).

## Formatting

- Start with `{`. No preamble, no code fences.
- Valid JSON.
- compRange: exact string from JD, or your estimate (if estimating, precede with "estimated: ").

## Confirmation

```
wrote 02-fit-score.json — score: <N>/10, gap: <bool>, rec: <first 10 words>
```
