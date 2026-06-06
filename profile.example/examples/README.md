# Examples — your real letters, so CoApply matches your voice

Drop real things you've written here — a cover letter that landed an interview, an
outreach message that got a reply — and CoApply uses them as a **voice reference**:
it imitates your cadence, structure, and tone, while keeping every *fact* sourced
from your profile and the job posting. This is the fastest way to make the output
sound like you, because good writing is easier to imitate than to describe.

## How to add one

Save a markdown file named for what it is, using this pattern:

```
<role>--<tag>--<short-name>.md
```

- `<role>` — what kind of thing it is: `cover-letter`, `outreach`, or
  `application-questions`.
- `<tag>` — a short hint (a domain, seniority, or company type) used to pick the
  most relevant examples for a given job, e.g. `senior`, `remote`, `early-stage`.
- `<short-name>` — anything memorable, e.g. the company.

Example filenames:

```
cover-letter--senior--acme.md
outreach--recruiter--bluebird.md
```

Then put a one-line header comment at the very top so CoApply can match it to a job
(optional but recommended — without it the file is still used, just matched by name):

```
<!-- role: cover-letter | seniority: senior | tags: remote, early-stage | note: landed an interview -->
```

Below the header, paste the real letter exactly as you wrote it.

## The easy way

You don't have to do this by hand. After a run you like, just say **"save this as an
example"** and CoApply will file it here for you.

## Good to know

- **Voice only, never facts.** CoApply imitates *how* your examples read, never
  *what* they claim. It won't copy a number, employer, or story from an old letter
  into a new application — those always come from your current profile and the JD.
- **How many are used:** higher budget tiers pull in more examples per run (lite
  uses none; standard up to 2; full up to 3), always the ones most relevant to the
  job. Your end-of-run receipt tells you which were used and which were set aside.
- **Don't paste CoApply's own output back in as an example.** Feeding the tool its
  own writing teaches it to imitate itself, which drifts your voice over time.
  CoApply tags what it generates and will warn you if you try.
