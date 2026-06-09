---
name: tier
description: View or change your CoApply budget tier (lite/standard/full).
---

# CoApply — budget tier

View or set the budget tier that controls how much each run spends. Keep it short.

## Step 0 — Resolve the profile folder

Run one Bash call, **bare** (don't capture it in `VAR="$(…)"` — that can't be allowlisted and would prompt every time). It prints `PROFILE_DIR=…`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-profile-dir.sh"
```

If the printed path is **empty**, stop and tell the user:

> CoApply doesn't have a Profile folder set yet — that's the folder where your profile and applications live. First make a new empty folder (e.g. `~/coapply-profile`), then run `/plugin`, open **CoApply**, set the **Profile folder** to that path, and re-run `/coapply:tier`.

Use the resolved absolute path wherever this file shows `${PROFILE_DIR}`.

## Step 1 — Read the current tier

Read `${PROFILE_DIR}/coapply.config.json`. The shape is `{"tier": "<lite|standard|full>"}`. If the file is absent or has no valid `tier`, treat the current tier as **`standard`** (the default).

## Step 2 — If a tier was passed in `$ARGUMENTS`, set it

If `$ARGUMENTS` contains one of `lite`, `standard`, or `full`, write it to the config (replace `<choice>`):

```bash
printf '{"tier": "%s"}\n' "<choice>" > "${PROFILE_DIR}/coapply.config.json"
```

Confirm the change and give one line on what that tier runs:

- **lite** — triage → the go/no-go gate → positioning + a cover letter.
- **standard** — lite, plus outreach, resume guidance, interview prep, follow-up, role analysis, and light company research.
- **full** — everything in standard, plus live company web research, a work-sample suggestion, application questions, and a `.docx`.

Then stop.

## Step 3 — Otherwise, show the menu and ask

If no tier was passed, show the current tier, then list all three with their composition and relative cost, and ask which to switch to:

- **lite** *(cheapest)* — triage → the go/no-go gate → positioning + a cover letter.
- **standard** *(default)* — lite, plus outreach, resume guidance, interview prep, follow-up, role analysis, and light company research.
- **full** *(most expensive)* — everything in standard, plus live company web research, a work-sample suggestion, application questions, and a `.docx`.

When they answer, write the config as in Step 2 and confirm.

## Always end with the next step

Whether you set the tier or just showed it, close with one forward-pointing line so the user is never left at a blank prompt:

> **Next:** `/coapply:start <job url or text>` to run an application at this tier.
