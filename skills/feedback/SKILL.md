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

## What you must never include

Only ever include the context the script collects (version, OS, tier, run phase) and
what the user wrote. **Never** read or paste their profile contents, a cover letter, a
resume, or anything from a run folder beyond the structural state the script reports.
If their description quotes private text, leave it as they wrote it — don't go fetch more.

## Step 1 — Get the gist

Use what the user gave you in their message. If they ran `/coapply:feedback` with
nothing, ask one short question and wait:

> What happened, or what would you like to see? A sentence is plenty.

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

## Step 4 — Assemble the issue and show it

Write a short, specific **title** (≤ 70 chars, no "Bug:"/"Idea:" prefix — the label
carries that). Then build the **body** from the template for the type, slotting the
user's words into the right sections. **Where they didn't cover a section, keep the
heading and leave a `_(fill this in — e.g. …)_` prompt** so they know exactly what to
add. Append the context block from Step 3 verbatim.

**Bug body:**

```markdown
**What happened**
<their description, or _(fill this in — one or two sentences)_>

**What I was doing**
<the command / step, e.g. `/coapply:start <url>`, at the gate, during setup — or _(fill this in)_>

**What I expected vs. what happened**
<expected → actual, or _(fill this in)_>

**Steps to reproduce** _(optional)_
<numbered steps, or delete this section>

**Environment**
<the context block from Step 3>

---
- [ ] I've kept my profile, letter text, and any secrets out of this report.
```

**Idea body:**

```markdown
**What I'd like**
<their idea, or _(fill this in — the capability or change)_>

**Why it matters**
<the problem it solves, or _(fill this in)_>

**How I imagine it working** _(optional)_
<rough sketch, or delete this section>

**Environment**
<CoApply version + OS from the context block>
```

Show the user the **complete title + body** in a single copy-paste block. This is the
primary artifact — it works even if the link below is too long for the browser.

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
