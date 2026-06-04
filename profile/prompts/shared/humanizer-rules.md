# Voice / Humanizer Rules

These are non-negotiable. They override all other style instincts when writing in the user's voice (cover letters, application-question answers, outreach, resume bullet recommendations).

## Mandatory

- **Use contractions ALWAYS.** "I've" not "I have." "didn't" not "did not." "that's" not "that is." "wasn't" not "was not." "I'm" not "I am." If there's a contraction available, use it.
- **Vary sentence length dramatically.** Mix 5-word punches ("That's how I work.") with 25-word explanations. Never write 4+ sentences of similar length in a row.
- **Sentence fragments are good when they hit harder.** "Product design. User experience. The stuff that makes people stick around."
- **Parenthetical asides add personality.** "(the feature everyone loved — and the one that broke most often)" / "(onboarding, billing, support)"
- **Name real things.** Tools, people, partners, features, specific numbers. Never categories or abstractions. Pull these from the user's profile, never invent them.
- **Name + describe + outcome.** Every proper noun you name (a project, a tool, a partner, an internal feature name) must be followed by a one-phrase description AND a concrete outcome. Readers don't know a company's internal feature names — the description bridges "sounds real" to "I understand what you did." Format: `<plain verb> <Named Thing> (<one-phrase what-it-is>) — <concrete outcome>`. The description must be how you'd explain it to a friend at a bar, not how a case study would write it up: ✅ `"the daily in-app game that rewarded users for checking in"` / ❌ `"the strategic engagement and retention feature."` If you can't write a plain-English description of the thing, it doesn't belong in the output.
- **One idea per paragraph.** If a paragraph does two things, split it.
- **Use "we" before "I"** when talking about team accomplishments. Your role within the team comes second.
- **Use hyphens " - " for asides**, never em dashes "—".
- **Plain verbs:** built, ran, shipped, cut, grew, fixed, owned, mapped, killed.

## Banned — never use

**Connector words:** Furthermore, Additionally, Moreover, In addition, Consequently, As a result.

**Summary sentences:** "This demonstrates..." / "This experience shows..." / "That background illustrates..." / "This work was central to..."

**"Intersection of X and Y" constructions.**

**Self-aggrandizing phrases:** "I thrive" / "I excel" / "I am drawn to" / "resonates with me" / "aligns closely with."

**Formal closers:** "the opportunity to discuss" / "I would welcome" / "I look forward to."

**Puffy verbs:** Spearheaded, Leveraged, Orchestrated, Facilitated, Championed, Streamlined, Navigated.

**Empty adjectives:** passionate (especially this one).

## Voice-Lint Check

Before finalizing any output from cover-letter, application-questions, outreach, upwork-proposal, or resume-update agents, run these two checks:

**Banned-phrase check.** Grep the output against the banned list above. If any match, rewrite that sentence and retry once. If a second violation occurs, flag to the user rather than shipping.

**Name-describe-outcome check.** For every proper noun in the output (specific project names, internal feature names, partner names), verify it has both a plain-English description AND a concrete outcome nearby. If a name appears alone with no description, rewrite to add one. Exception: a name that readers plausibly already know (a major public company or widely used product) doesn't need a description — only internal feature names / obscure projects do.
