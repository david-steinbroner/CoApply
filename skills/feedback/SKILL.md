---
name: feedback
description: Turn what happened into a ready-to-file GitHub issue — a structured report you review, plus a one-click prefilled link. Triggers on "report a bug", "something broke", "feature request", "I have an idea", "give feedback", "file an issue".
---

# CoApply — send feedback

The user hit a bug or has an idea. Your job is to turn their plain words into a
**ready-to-paste GitHub issue** — a clear title + a structured body — plus a one-click
prefilled link, so they don't have to write boilerplate or remember what to include.

**You never submit it for them.** You hand them the issue to post; they review and send.
Same drafts-you-decide ethos as the application gate. Keep this fast and cheap — don't
interrogate them; one short question at most, then produce the issue.

## The core rule: capture, don't compose

CoApply never fabricates — that is the whole product. This skill must hold to it. **The
issue may contain only what the user actually told you, plus the context the script
collects.** Do not invent a motivation, an impact, a rationale, or a proposed solution
they did not say. Do not add sections to "round it out" or make the report look more
complete. If they gave you one vague sentence, the issue is that one sentence plus the
context block — short and honest is correct, and *required*.

Why this is non-negotiable here: this feature exists to collect honest signal for the
maintainer. If you embellish, you hand them a confident proposal no user actually made,
and they make decisions on a lie. A faithful one-line gripe is worth more than a
polished paragraph you wrote.

## What you must never include

Only ever include the context the script collects (version, OS, tier, run phase) and
what the user wrote. **Never** read or paste their profile contents, a cover letter, a
resume, or anything from a run folder beyond the structural state the script reports.
If their description quotes private text, leave it as they wrote it — don't go fetch more.

## Step 1 — Get something worth filing

Start from what the user gave you (or, if they ran `/coapply:feedback` with nothing,
ask: *"What happened, or what would you like to see? A sentence is plenty."* and wait).

Then judge one thing before you build anything: **is there enough here for a maintainer
to act on?** Don't manufacture an issue from a vague remark — a confused user usually
needs a question, not paperwork.

- **Specific enough** — names a behavior, a step, or a concrete want ("the gate didn't
  show a fit score", "add a way to find jobs for me"). → go to Step 2.
- **Too vague to be useful** — confusion or a bare verdict with no specifics ("I don't
  understand", "it's confusing", "it didn't work"). → **ask exactly one short, concrete
  clarifying question and wait.** Offer likely areas so they can just point, and tailor
  it to what they said:
  - confusion / idea: *"Happy to pass that on. What part's tripping you up — setting it
    up, starting an application, the fit-check gate, or something else? One line is plenty."*
  - something broke: *"Got it. What were you doing when it happened, and what did you
    expect to see?"*

  **Ask only once.** Use their answer. If they decline or say "just file it," proceed
  with exactly what you have — captured faithfully, never padded out. One clarification
  is the limit; don't interrogate.

## Step 2 — Decide the type (silently)

From their words, decide which it is — don't ask:

- **Bug** — something broke, errored, or behaved wrong. Label: `bug`.
- **Idea** — a feature request, improvement, or "it'd be nice if…". Label: `enhancement`.

If it's genuinely both or unclear, treat it as a **bug** (the more actionable default).

## Step 3 — Collect the context (one Bash call)

Resolve the profile dir (it may be empty — that's fine; feedback about *setup itself*
comes from users with no profile yet, so never block on this):

```bash
PROFILE_DIR="$("${CLAUDE_PLUGIN_ROOT}/scripts/resolve-profile-dir.sh")"
```

Then collect context. Pass a **run slug only if the feedback is clearly about a
specific run** (a failure or odd output *during* `/coapply:start` or `/coapply:resume`).
For setup confusion, ideas, or general feedback, omit it. To find the most recent run
when one is relevant: `ls -1t "$PROFILE_DIR/runs" 2>/dev/null | grep -v '^\.' | head -1`.

```bash
# General feedback / ideas / setup:
"${CLAUDE_PLUGIN_ROOT}/scripts/feedback-context.sh" context "$PROFILE_DIR"
# Or, when it's about a specific run:
"${CLAUDE_PLUGIN_ROOT}/scripts/feedback-context.sh" context "$PROFILE_DIR" "<run-slug>"
```

Show the user this context block as-is — no hidden diagnostics.

## Step 4 — Assemble the issue (capture, don't compose)

Build the issue from the user's words and nothing else. There are no empty sections to
fill — a section appears **only if the user actually gave you that information.**

- **Title:** a short, plain restatement of what they said (≤ 70 chars, no "Bug:"/"Idea:"
  prefix). Not a reframe, not a proposed fix. If they said "I don't understand how to use
  it," the title is "Hard to understand how to use it" — never "Add a guided onboarding
  flow."
- **Body:** their words, lightly cleaned for typos/grammar only — keep their meaning and
  voice. Then the context block from Step 3.

A **bug** with just "What happened" + Environment is a complete, valid issue:

```markdown
**What happened**
<their words, cleaned for typos only>

**Environment**
<the context block from Step 3>
```

Add **What I was doing**, **What I expected vs. happened**, or **Steps to reproduce**
beneath "What happened" *only if the user actually told you those things.* If they
didn't, leave them out — no heading, no placeholder, no inference.

An **idea** with just "What I'd like" + Environment is likewise complete:

```markdown
**What I'd like**
<their words, cleaned for typos only>

**Environment**
<CoApply version + OS from the context block>
```

Add **Why it matters** *only if they said why*, and **How I imagine it working** *only if
they proposed how*. Never write a rationale or a solution they didn't give.

After "Environment", append one plain invite (this is a prompt to the user, not a
fabricated section):

> _Want to add anything before filing — what you were doing, what you expected, or any
> detail? Or send it as-is._

Show the user the **complete title + body** in a single copy-paste block. This is the
primary artifact — it works even if the link below is too long for the browser.

**Self-check before you show it:** reread your draft against what the user actually
wrote. If any sentence isn't grounded in their words or the script's context block,
delete it. When in doubt, leave it out.

## Step 5 — The links (one Bash call)

Write the exact body you showed to a temp file, then build the prefilled URL:

```bash
TMP="$(mktemp)"; cat > "$TMP" <<'COAPPLY_EOF'
<the exact issue body from Step 4>
COAPPLY_EOF
"${CLAUDE_PLUGIN_ROOT}/scripts/feedback-context.sh" url "<the title>" "<bug|enhancement>" "$TMP"
rm -f "$TMP"
```

Give the user:
1. **One-click:** the prefilled URL above — opens GitHub's new-issue page with
   everything filled in; they just review and click **Submit**.
2. **Fallback:** the plain new-issue link, in case the prefilled one is too long —
   `<repo>/issues/new` (get `<repo>` from `feedback-context.sh repo`). Tell them to
   paste the block from Step 4 there.

## Step 6 — Offer to file it directly (only if `gh` is ready)

Check whether the GitHub CLI is installed and authenticated:

```bash
gh auth status >/dev/null 2>&1 && echo GH_READY || echo GH_NO
```

- If `GH_NO`: skip this step — the links above are the path.
- If `GH_READY`: offer it as an option, never the default:
  > I can file this for you directly with `gh` if you'd like — want me to? (yes / I'll post it myself)

  Only on an explicit **yes**, file it (reuse the same temp-file body):
  ```bash
  gh issue create --repo "$("${CLAUDE_PLUGIN_ROOT}/scripts/feedback-context.sh" repo)" \
    --title "<the title>" --label "<bug|enhancement>" --body-file "$TMP"
  ```
  Then show the returned issue URL. Never file without the explicit yes.

## Always end with the next step

Close with one forward-pointing line:

> **Next:** `/coapply:start <job url or text>` to get back to applying — or send another note with `/coapply:feedback` anytime.
