---
name: add
description: Add a rule, an example, or a personal fact to your CoApply profile in plain language, so future applications match you better. Triggers on "add this to my profile", "remember this", "from now on always/never...", "save this as an example".
---

# CoApply — add to your profile

The user wants to teach CoApply something so future runs are more like them. Your job
is to figure out *what kind* of thing it is, **confirm where it goes** (never guess
silently), refuse to store true secrets, and write it. Speak plain English — never
say "playbook", "role binding", "few-shot", or other internals to the user.

## Step 0 — Resolve the profile folder

```bash
PROFILE_DIR="$("${CLAUDE_PLUGIN_ROOT}/scripts/resolve-profile-dir.sh")"
echo "PROFILE_DIR=$PROFILE_DIR"
```

If empty, tell the user to run `/coapply:setup` first and stop.

## Step 1 — Get the content

Use what the user gave you in their message (the rule, the letter, or the fact). If
they invoked `/coapply:add` with nothing, ask: *"What would you like me to remember?
A writing rule, an example of your own writing, or a personal detail like your
location or target salary?"* and wait.

## Step 2 — Secret check FIRST (deterministic, mandatory)

Write the exact content to a temp file and scan it before anything else:

```bash
TMP="$(mktemp)"; cat > "$TMP" <<'COAPPLY_EOF'
<the exact content the user wants to add>
COAPPLY_EOF
"${CLAUDE_PLUGIN_ROOT}/scripts/scan-pii.sh" "$TMP"; echo "scan_rc=$?"; rm -f "$TMP"
```

**If `scan_rc` is 3 (a secret was found):** refuse to store it. Make this message
visually distinct (lead with a clear warning line) and give it **no "save anyway"
option** — there is no override:

> ⚠️ That looks like it contains a secret (e.g. `<the flag(s) the script printed>`).
> I won't save it — your profile is sent to the AI when it writes for you, so things
> like SSNs, passwords, and account numbers don't belong here.

If the user typed the secret directly into this chat, add one honest line:
*"Also — because you typed it here, it's already been sent to the AI for this one
message. Best to keep secrets out of the chat entirely."* Then stop.

**If `scan_rc` is 0:** continue.

## Step 3 — Classify and CONFIRM placement (never silent)

Decide which of three it is, then confirm with the user. Make "yes" the easy default.

- **A writing RULE** — an instruction about *how* to write ("never open by explaining
  the company to itself", "keep it under 250 words"). → goes in a rules file for the
  kind of writing it affects.
  - Pick the kind: `cover-letter`, `positioning`, `outreach`, `interview-prep`,
    `resume-update`, or `application-questions`. If it spans several, propose
    `general` (applies to everything) and say so.
  - Confirm: *"I'll add this as a cover-letter rule — yes? (Enter to confirm /
    different kind / let me edit)."*
- **An EXAMPLE** — a real thing the user wrote (a letter, an outreach message). →
  saved as a style reference.
  - Confirm: *"Want me to keep this as one of your saved letters, so I can match your
    voice next time? (yes / no)"*
- **A personal FACT** — location, target comp, work-authorization, start date, etc.
  → goes in `facts.md`.
  - Confirm: *"I'll save this to your profile facts. Heads up: your profile is sent to
    the AI when it writes for you (that's how it uses your location/salary) — so this
    will be sent, but never anything you didn't put here. Save it? (yes / no)"*

If you're unsure which it is, ask rather than guess.

## Step 4 — Write it (after the user confirms)

### Rule → playbook
```bash
mkdir -p "$PROFILE_DIR/playbooks"
PB="$PROFILE_DIR/playbooks/<kind>.md"
[ -f "$PB" ] || printf '# %s rules\n\n' "<kind>" > "$PB"
```
**Rule cap — check before appending:**
```bash
COUNT=$(grep -c '^- ' "$PB" 2>/dev/null || echo 0); echo "rules_now=$COUNT"
```
- If `COUNT` < 20: append the rule as a single-line bullet:
  ```bash
  printf -- '- %s\n' "<the rule, one line>" >> "$PB"
  ```
- If `COUNT` >= 20: **do not just append.** Tell the user this file is getting long
  (long rule-lists get diluted and the tool starts ignoring older ones), and offer:
  *"Your cover-letter rules are at 20 — adding more risks the AI ignoring some. Want
  me to (a) merge similar rules into a tighter set, or (b) show them so you can prune
  a few first?"* On **merge**: read the file, propose a consolidated rewrite that
  preserves every distinct intent, show it, and only on approval write it back
  (overwrite). On **prune**: show the numbered list and let them pick which to drop.

### Example → examples/
First guard against re-ingesting CoApply's own output:
```bash
printf '%s' "<content>" | grep -q 'coapply:generated' && echo "GENERATED" || echo "OK"
```
- If `GENERATED`: warn — *"This looks like CoApply's own output. Using its own writing
  as a 'good example' teaches it to imitate itself and drifts your voice over time. Add
  it anyway only if you've rewritten it in your own words. Proceed? (no / yes-it's-mine)"*
  Default to **no**.
- Otherwise save with a header so it can be matched to future jobs:
  ```bash
  mkdir -p "$PROFILE_DIR/examples"
  printf '<!-- role: <kind> | tags: <2-4 short tags you infer> | note: <one line> -->\n%s\n' "<content>" \
    > "$PROFILE_DIR/examples/<kind>--<short-tag>--<slug>.md"
  ```
  Pick `<kind>` (cover-letter / outreach / application-questions), a short tag, and a
  slug from the content. Keep filenames `<kind>--<tag>--<slug>.md`.

### Fact → facts.md
```bash
[ -f "$PROFILE_DIR/facts.md" ] || cp "${CLAUDE_PLUGIN_ROOT}/profile.example/facts.md" "$PROFILE_DIR/facts.md"
printf -- '- %s\n' "<the fact>" >> "$PROFILE_DIR/facts.md"
```
(If it updates an existing field, edit that line instead of appending a duplicate.)

## Step 5 — Confirm

Tell the user exactly what you saved and where, in plain words, and that it'll be used
on the next run:

> Done — added your rule to your cover-letter rules. You'll see it under "your writing
> rules" in the receipt on your next application. Add another anytime, or just tell me
> "from now on..." mid-run.
