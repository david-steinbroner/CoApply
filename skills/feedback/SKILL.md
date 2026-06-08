---
name: feedback
description: Send a bug or idea to CoApply's maintainer. Offers to either point you to the issue page so you can write it yourself, or draft a ready-to-paste issue from your words. Triggers on "report a bug", "something broke", "feature request", "I have an idea", "give feedback", "file an issue".
---

# CoApply — send feedback

The user hit a bug or has an idea, and wants it to reach the maintainer. There are two
ways to get it there, and which one fits depends on how much they want to do versus how
much they want you to do. **You offer the choice; you never submit anything for them.**

- **Light path** — you point them at GitHub's issue page and they write it themselves.
  Quick, almost no work for you.
- **Draft path** — you turn their words into a ready-to-paste issue (+ a one-click
  prefilled link). More work for you, less for them.

Same drafts-you-decide ethos as the application gate: it always ends with the user
reviewing and posting.

## The core rule: capture, don't compose

CoApply never fabricates — that is the whole product. This skill must hold to it. **Any
issue you draft may contain only what the user actually told you, plus the context the
script collects.** Do not invent a motivation, an impact, a rationale, or a proposed
solution they did not say. Do not add sections to "round it out." If they gave you one
vague sentence, the issue is that one sentence plus the context block — short and honest
is correct, and *required*.

Why this is non-negotiable: this feature exists to collect honest signal for the
maintainer. If you embellish, you hand them a confident proposal no user actually made,
and they decide on a lie. A faithful one-line gripe beats a polished paragraph you wrote.

## What you must never include

Only ever include the context the script collects (version, OS, tier, run phase) and
what the user wrote. **Never** read or paste their profile contents, a cover letter, a
resume, or anything from a run folder beyond the structural state the script reports.
If their description quotes private text, leave it as they wrote it — don't go fetch more.

## Step 1 — Get the feedback

Start from what the user gave you. If they ran `/coapply:feedback` with nothing, ask
once and wait: *"What happened, or what would you like to see? A sentence is plenty."*

Don't judge or clarify it yet — that comes later, and only on the draft path.

## Step 2 — Offer the fork (and read the answer carefully)

Ask one short question:

> Want me to **draft an issue for you to review and post**, or just **point you to the
> issue page so you can write it yourself**? (I'll do the writing, or you keep it quick.)

Read their answer:
- **Clearly "draft it"** (or they just keep talking / add more detail — that's an
  engaged "handle it") → **Step 4 (draft path).**
- **Clearly "just the link" / "I'll write it"** → **Step 3 (light path).**
- **A non-answer** ("idk", "whatever's easiest", a bare "ok") → **ask the fork once
  more, in one line.** If they still don't choose, fall back to the **light path** — when
  consent is unclear, do *less* on their behalf, not more. Never generate a draft off an
  ambiguous answer.

## Step 3 — Light path: point them to the issue page

Cheap and self-served. Give them three things:

1. **The link** — GitHub's template chooser (so they land on a Bug/Idea template that
   structures it for them). Get the repo URL and append `/issues/new/choose`:
   ```bash
   echo "$("${CLAUDE_PLUGIN_ROOT}/scripts/feedback-context.sh" repo)/issues/new/choose"
   ```
2. **Their own words**, in a code block, so they can paste them in if they like — *their
   words only, nothing added.*
3. **Their environment**, so they can fill the template's Environment section (users
   don't know their CoApply version offhand). This is just facts to copy, not a drafted
   issue:
   ```bash
   PROFILE_DIR="$("${CLAUDE_PLUGIN_ROOT}/scripts/resolve-profile-dir.sh")"
   "${CLAUDE_PLUGIN_ROOT}/scripts/feedback-context.sh" context "$PROFILE_DIR"
   ```

Then you're done — skip to the end. No drafting, no prefilled URL.

## Step 4 — Draft path

### 4a — Clarify only if it's too vague to draft

Judge: **is there enough here to write an issue a maintainer could act on?** Don't
manufacture a report from a vague remark — a confused user needs a question, not paperwork.

- **Specific enough** ("the gate didn't show a fit score", "add a way to find jobs") →
  continue.
- **Too vague** ("I don't understand", "it's confusing", "it didn't work") → **ask
  exactly one short, concrete clarifying question and wait.** Offer likely areas, tailored
  to what they said:
  - confusion / idea: *"Happy to draft that. What part's tripping you up — setting it up,
    starting an application, the fit-check gate, or something else? One line is plenty."*
  - something broke: *"Got it. What were you doing when it happened, and what did you
    expect to see?"*

  **Ask only once.** If they decline or say "just draft it," proceed with exactly what you
  have — captured faithfully, never padded. One clarification is the limit.

### 4b — Decide the type (silently)

- **Bug** — something broke or behaved wrong. Label: `bug`.
- **Idea** — a feature request or improvement. Label: `enhancement`.
- Genuinely unclear → treat as a **bug** (more actionable).

### 4c — Collect the context (one Bash call)

```bash
PROFILE_DIR="$("${CLAUDE_PLUGIN_ROOT}/scripts/resolve-profile-dir.sh")"
```
Pass a **run slug only if the feedback is clearly about a specific run** (a failure or odd
output *during* `/coapply:start` or `/coapply:resume`); otherwise omit it. Most recent run
when relevant: `ls -1t "$PROFILE_DIR/runs" 2>/dev/null | grep -v '^\.' | head -1`.
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/feedback-context.sh" context "$PROFILE_DIR"
# or, about a specific run:
"${CLAUDE_PLUGIN_ROOT}/scripts/feedback-context.sh" context "$PROFILE_DIR" "<run-slug>"
```
Show this context block as-is — no hidden diagnostics.

### 4d — Assemble the issue (capture, don't compose)

Build it from the user's words and nothing else. A section appears **only if the user
actually gave that information** — there are no empty sections to complete.

- **Title:** a short, plain restatement of what they said (≤ 70 chars, no "Bug:"/"Idea:"
  prefix). Not a reframe, not a proposed fix. "I don't understand how to use it" →
  "Hard to understand how to use it", never "Add a guided onboarding flow."
- **Body:** their words, lightly cleaned for typos/grammar only — keep their meaning and
  voice. Then the context block.

A **bug** with just "What happened" + Environment is a complete, valid issue:
```markdown
**What happened**
<their words, cleaned for typos only>

**Environment**
<the context block from 4c>
```
Add **What I was doing**, **What I expected vs. happened**, or **Steps to reproduce**
*only if the user told you those.* Otherwise leave them out — no heading, no inference.

An **idea** with just "What I'd like" + Environment is likewise complete:
```markdown
**What I'd like**
<their words, cleaned for typos only>

**Environment**
<CoApply version + OS from the context block>
```
Add **Why it matters** *only if they said why*, and **How I imagine it working** *only if
they proposed how.* Never write a rationale or solution they didn't give.

After "Environment", append one plain invite (a prompt to the user, not a fabricated
section):
> _Want to add anything before filing — what you were doing, what you expected, or any
> detail? Or send it as-is._

Show the **complete title + body** in one copy-paste block. This is the primary artifact —
it works even if the link below is too long.

**Self-check before you show it:** reread the draft against what the user actually wrote.
If any sentence isn't grounded in their words or the context block, delete it. When in
doubt, leave it out.

### 4e — The prefilled link (one Bash call)

Write the exact body you showed to a temp file, then build the URL:
```bash
TMP="$(mktemp)"; cat > "$TMP" <<'COAPPLY_EOF'
<the exact issue body from 4d>
COAPPLY_EOF
"${CLAUDE_PLUGIN_ROOT}/scripts/feedback-context.sh" url "<the title>" "<bug|enhancement>" "$TMP"
```
Give them:
1. **One-click:** the prefilled URL — opens the new-issue page filled in; they review and Submit.
2. **Fallback:** if it's too long, the plain `<repo>/issues/new` (from `feedback-context.sh repo`) and tell them to paste the block above.

### 4f — Offer to file it directly (only if `gh` is ready)

```bash
gh auth status >/dev/null 2>&1 && echo GH_READY || echo GH_NO
```
- `GH_NO` → skip; the links are the path.
- `GH_READY` → offer, never default:
  > I can file this for you directly with `gh` if you'd like — want me to? (yes / I'll post it myself)

  Only on an explicit **yes** (reuse the temp body):
  ```bash
  gh issue create --repo "$("${CLAUDE_PLUGIN_ROOT}/scripts/feedback-context.sh" repo)" \
    --title "<the title>" --label "<bug|enhancement>" --body-file "$TMP"
  rm -f "$TMP"
  ```
  Show the returned issue URL. Never file without the explicit yes. (Clean up `$TMP` with
  `rm -f "$TMP"` once you're done either way.)

## Always end with the next step

Close with one forward-pointing line:

> **Next:** `/coapply:start <job url or text>` to get back to applying — or send another note with `/coapply:feedback` anytime.
