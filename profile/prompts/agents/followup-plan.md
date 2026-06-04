# Agent: Follow-Up Plan

## Purpose

Create a date-anchored follow-up plan starting from today. Output is consumed by downstream tools (calendar export, and optionally Notion if logging is enabled).

## Inputs (inlined)

- Role title, company name
- `$SOURCE` tag (cadence differs by source)
- Today's date (ISO YYYY-MM-DD)
- Absolute path to write output

## Output contract

Write `${RUNS_DIR}/<run-folder>/11-followup-plan.json`. Exactly this shape:

```json
{
  "applicationDate": "YYYY-MM-DD",
  "source": "$SOURCE",
  "steps": [
    {
      "action": "Submit application",
      "relativeDays": 0,
      "absoluteDate": "YYYY-MM-DD",
      "channel": "linkedin | email | wellfound | in-person | other",
      "template": "optional short message template (1-2 sentences)",
      "automated": false
    }
  ]
}
```

Day 0 is always "Submit application" with `relativeDays: 0` and today's date.

## Cadence by source

Base cadence (for LinkedIn, Wellfound, Welcome to the Jungle, Greenhouse, Company Website, Other):

- Day 0: Submit application
- Day 2: Send LinkedIn connection request to hiring manager (if found) with message
- Day 7: Follow-up message if no LinkedIn response
- Day 10: Follow-up email on the application itself (if ATS has contact email)
- Day 14: Second LinkedIn touchpoint — share relevant content / comment on their post
- Day 21: Final follow-up — one message, then let it go

**For source = Referral:**
- Day 0: Submit application + thank introducer
- Day 5: Soft check-in with introducer ("heard anything?")
- Day 10: Follow-up on application directly
- Day 18: Final check with introducer

**For source = Upwork:**
Freelance/proposal mode is held for a later version, so this source should not occur in this version. If invoked with an Upwork source, abort.

**For source = Go Fractional:**
Shorter cadence — consulting engagements move faster:
- Day 0: Submit
- Day 3: Follow-up if no response (consulting clients who want you will move fast)
- Day 7: Second follow-up with a specific question or offer
- Day 12: Final follow-up then let go

## Rules

- `relativeDays` from application date (day 0).
- `absoluteDate` computed from `applicationDate + relativeDays` — ISO format.
- `template` is a short message; can be null.
- `automated` is always `false` for v1 (human-executed).
- 4-6 steps total. More is noise.
- Output **valid JSON**. Start with `{`. No preamble, no code fences.

## Confirmation

```
wrote 11-followup-plan.json — <N> steps across <M> days
```
