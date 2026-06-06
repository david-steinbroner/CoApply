# Playbooks — your own rules, so CoApply writes more like you

A **playbook** is a plain list of *your* rules for one kind of thing CoApply
writes. Drop a rule in here and CoApply follows it on every future run — no
settings, no syntax. This is how you mold the tool over time so it stops sounding
generic and starts sounding like you.

## How it works

- One file per kind of output, named for what it shapes:
  - `cover-letter.md` — rules for cover letters *(a starter set ships here)*
  - `positioning.md` — rules for the angle/strategy of an application
  - `outreach.md` — rules for outreach messages
  - `interview-prep.md` — rules for interview prep
  - `resume-update.md` — rules for résumé tailoring
  - `application-questions.md` — rules for free-text application answers
  - `general.md` — cross-cutting rules that apply to **everything** CoApply writes
- Each file is just a markdown list of rules in plain English. Write them however
  you'd tell a sharp assistant: *"Don't open by explaining the company to itself."*
- A file is used **only if it exists**. No file, no problem — CoApply just uses its
  defaults. Delete a file anytime to go back to defaults.
- Your playbooks survive CoApply updates — they live in your profile, never the engine.

## The easy way to add a rule

You don't have to edit these files by hand. Just tell CoApply in plain language —
*"from now on, never open my cover letters by explaining the company to itself"* —
and it will offer to add the rule to the right playbook and show you where it put it.

## Keep them tight

A short, sharp list works better than a long one: long rule-lists get diluted and
the tool starts ignoring the older ones. CoApply caps each playbook around ~20 rules
and will offer to help you merge or prune when one gets too long.

## Note on the `general.md` cross-cutting case

A rule that spans several kinds of writing (e.g. "always lead with measurable
impact") can either live in `general.md` (applied to every output) or be copied
into each relevant playbook. CoApply will suggest which when you add one.
