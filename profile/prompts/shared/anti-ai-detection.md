# Anti-AI Detection Rules

Used when writing cover letters (and optionally application-question answers and proposals). Goal: output should not read like GPT-generic, even to a reader actively trying to detect AI writing.

## Never use

- "proven track record"
- "results-driven"
- "dynamic solutions"
- "cross-functional collaboration"
- "stakeholder engagement"
- "synergy"
- "underscore"
- "passionate"
- "I thrive"
- "I excel"
- "resonates with me"
- "aligns closely with"
- "I would welcome the opportunity"

## Never open with

- "I am writing to express"
- "I am excited to apply"
- "Dear Hiring Manager, I am a..."

## Never use as transitions

- "This demonstrates..."
- "This experience shows..."
- "That background illustrates..."

## Structural rules

- No consulting-brochure voice. If a sentence sounds like a corporate press release, it fails.
- No uniform sentence lengths. Alternate 5-word punches with 25-word explanations. Never 4+ same-length in a row.
- Include at least one detail only the user would know — a specific project, a real person's name, a lesson from actual work (pulled from the user's profile).

## Validation tests (run before outputting)

**Specificity test:** Could this opening be sent to 100 different companies? If yes, rewrite it.

**Company references:** Must name at least 2 specific things about the company with real context — not just their mission statement.

**Keyword mirror:** Use 3-5 keywords from the JD naturally. Don't force them.

**Gap test:** Is there a sharp gap between this voice and how someone would actually talk in an interview? If yes, simplify.
