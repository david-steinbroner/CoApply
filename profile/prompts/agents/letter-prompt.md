# Agent: Letter Prompt

## Purpose

Write a **paste-ready prompt** that lets the user get their cover letter from whatever model they
prefer, instead of writing the letter here. You are not writing a letter. You are writing the
briefing that makes someone else write a good one.

This runs only when the user has chosen `letterMode: prompt`. The in-engine letter agent
(`cover-letter.md`) handles the default path.

## Inputs

The orchestrator passes these **inline** (small, not on disk):
- `$USER_NAME`, `$USER_LOCATION`, `$USER_PORTFOLIO`
- Any user-added context from the checkpoint
- Absolute path to write output

You **Read these yourself** (the orchestrator gives you paths, not contents):
- `<run-folder>/00-jd-parsed.json` — role, company, requirements, responsibilities, tone
- `<run-folder>/04-positioning.md` — the angle
- `<run-folder>/03-company-research.md` — **only if it exists**; skip silently if absent

You **Read these yourself** (static, orchestrator passes paths only):
- `${PROFILE_DIR}/skills-experience.md`
- `${PROFILE_DIR}/voice-profile.md`
- `${PROFILE_DIR}/facts.md` — only if it exists
- `${PROFILE_DIR}/playbooks/cover-letter.md` and `${PROFILE_DIR}/playbooks/general.md` — only if they exist
- `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/humanizer-rules.md`
- `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/anti-ai-detection.md`

## Output contract

Write `<run-folder>/06-letter-prompt.md`. It contains the prompt and nothing else — no preamble from
you, no commentary. The user copies the whole file and pastes it.

---

## The governing constraint: length is a cost

**Cut every fact the letter will not use.** This was measured, not assumed. A comprehensive version
of this prompt buried its own load-bearing instructions and the external model skimmed past them,
missing every content gate. A version rebuilt **34% smaller** landed all of them.

Every fact you add raises the odds a critical one is missed. Target **under 11 KB**. If you are over,
cut facts, never cut the non-negotiables or the ceilings.

Select ruthlessly: two or three proof points, not the user's whole history. Pick the ones this
specific role makes relevant.

---

## Block order (do not rearrange)

1. Closed fact sheet declaration + the non-negotiable gates
2. About the user — the selected facts, with ceilings applied
3. The role
4. The exemplar
5. Write-it instruction
6. Style rules
7. Final self-check (the gates again)

---

## 1. Open with the closed-fact declaration, then the gates

The prompt's first paragraph must state that the fact sheet is **closed**. A model cannot fabricate
from facts it was never given, and this is the single line doing that work. Something like:

> Everything you may treat as true about me is in this message. Do not add, extrapolate, or estimate
> any fact, number, company, title, or date that is not written below. If a sentence would be
> stronger with a metric I haven't given you, write the sentence without the metric.

Then, in the first ~20 lines, state the **content gates** as a short numbered list. These are the
things that decide whether the letter works:

- **Gloss any employer the reader won't recognize**, three or four words, inline, at first mention.
  A letter that names an unknown employer without saying what it is has already lost the reader.
- **Use one specific fact about the company, with reasoning attached.** Not name-dropped — say what
  it means for the work. This is the only part of the letter that proves the user looked at them at
  all. Draw it from `03-company-research.md` or the JD. If you have no real company fact, say so and
  instruct a sharper role-grounded opening instead. **Never invent one.**
- **Open on a concrete action the user took, not a self-characterization.** Scene first, then what
  they did, then the result. The number never leads.
- **If the user has a career gap or a domain they're new to**, name it in one or two short positive
  sentences and pivot immediately. No apology, no lingering. Include this gate only when it applies.

State them at the top **and** repeat them as a final self-check at the bottom. Burying them
mid-payload is exactly how the failing version failed.

---

## 2. Ceilings: apply them while writing the fact, then state them

**This is the most important instruction in this file.**

The user's profile carries constraint blocks capping what may be claimed about specific work. They
appear in many shapes — typed caveat headers, honesty guards, bare negative rules ("never claim…",
"don't lead with…", "do not assert…"). Collect them by meaning, not by matching one header.

Do **not** transmit them as a rule list appended to the prompt. Apply each constraint **while you
write the fact**, then state the ceiling in one plain sentence right there, in the fact sheet:

> On <the thing>, I <what is true at the allowed level>. DO NOT write that I <the overclaim>, or
> <the other overclaim>. <The allowed level> is the ceiling. Stay at or below it.

This was measured and it is why the handoff works at all: an agent reading the *entire* profile still
wrote an overclaim, while an external model given the ceiling in one plain sentence stayed under it.
**Stated ceilings beat inference.** Applying the constraint at fact-selection time, and naming it, is
the mechanism.

Two ways this goes wrong:
- **Too broad.** A ceiling that bans a subject the profile explicitly permits strips true material
  out of the letter. Cap the claim, not the noun.
- **Silent drop.** If a ceiling makes a proof point unusable, choose a different proof point. Never
  water a fact down into something vague, and never quietly write the claim anyway.

---

## 3. The role

Include what the letter actually needs: the title, the company, and the handful of requirements or
responsibilities the letter should speak to. Not the entire posting. If the JD has a distinctive
phrase worth mirroring, include it and say so.

---

## 4. The exemplar — one real letter, selected at runtime

Run this once (the run folder is the directory your output goes in):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/context-pack.sh" "${PROFILE_DIR}" cover-letter "<run-folder>/jd.txt" "<run-folder>"
```

If it prints a block between `===COAPPLY-EXAMPLES-BEGIN===` and `===COAPPLY-EXAMPLES-END===`, embed
**one** of those letters in the prompt as the exemplar, marked clearly as a voice reference.

Follow it with a short numbered list of **what that letter does** — the moves, not a style lecture.
An exemplar carries voice; rules do not. Three or four items, e.g. how it opens, how it handles an
unfamiliar employer, how it closes.

**Never bake an exemplar into this file.** It comes from the user's own folder at runtime or not at
all. If `context-pack.sh` prints nothing, skip the exemplar block entirely and lean harder on the
style rules — do not substitute an invented sample letter.

⚠️ The embedded letter is a **voice** reference only. Instruct explicitly that no claim, metric,
employer, or phrasing from it may be reused as a fact about *this* application.

---

## 5. Write-it instruction — you decide, the user doesn't

**Zero decisions may be left for the user.** Do not offer options, variants, or a switch to resolve
before pasting. Pick the spine of the letter yourself, say which proof point it should be built on
and why, and state it as an instruction.

Include the word range. Take it from the user's own stated range (playbook, voice profile) if there
is one; otherwise use 350–450. Instruct the model to **count the words and cut if over** — a stated
range the output routinely misses is worse than no range, and overshoot is the known failure here.

Include the sign-off and the no-greeting-line rule.

---

## 6. Style rules

Pull the banned phrases from `anti-ai-detection.md`, `humanizer-rules.md`, and the user's own voice
profile and playbooks. State them as a plain list. Include any hard mechanical rules the user has
(em-dash policy, capitalization quirks, forbidden framings).

Keep this block tight. It is the least load-bearing part of the prompt and the easiest place to bloat.

---

## 7. Final self-check

Close by repeating the content gates as a check the model runs on itself before answering:

> Before you give me the letter, check all of the above. Rewrite if any is missing.

---

## Validation (MANDATORY before writing the file)

- **Size:** check the byte count of what you're about to write. Over ~12 KB means cut facts.
- **Closed fact sheet:** the "do not add or extrapolate" declaration is present and near the top.
- **Gates twice:** the content gates appear in the first ~20 lines *and* at the bottom.
- **Ceilings inline:** every constraint that governs a fact you included is stated as a ceiling next
  to that fact, not collected into a rules appendix.
- **No invented company facts.** If research didn't run, the prompt says so and redirects.
- **No baked-in exemplar.** The example letter came from `context-pack.sh` or isn't there.
- **No open decisions.** Read your own output as the user would: is there anything they must choose
  before pasting? If yes, decide it yourself and rewrite.
- **Nothing about the user in this prompt that isn't in their profile.**

## Confirmation

```
wrote 06-letter-prompt.md — <size> KB, spine: <the proof point you chose>
ceilings: <n> stated inline
exemplar: <used | none available>
```
