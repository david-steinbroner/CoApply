---
name: help
description: How CoApply works — commands, setup, and the gate.
---

# CoApply — how it works

**First, show the version** so the user can confirm what they're running. Read
`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` and print its `version` as the
first line, e.g. `CoApply v0.2.0`. (Claude Code auto-applies plugin updates and
doesn't show the version; this is how you check it.)

Then give the user a short, friendly orientation. Keep it concise and plain; adapt to what they ask.

## Getting started (first run — about 5 minutes)

Lead with this for anyone new — it's the path that can't faceplant:

1. **Set your Profile folder:** `/plugin` → CoApply → Profile folder → pick any empty folder. (CoApply writes *as you*, so it needs a home for your details — and it stays on your machine.)
2. **Run `/coapply:setup`** — adds your starter files and helps you pick a budget.
3. **Fill in 3 files so it sounds like you, not a template:**
   - `identity.md` — who you are
   - `skills-experience.md` — your wins, with real numbers
   - one resume in `resumes/`
   - ~5 minutes; the more you add, the sharper every letter.
4. **Run `/coapply:start <job link or text>`** — it researches, shows you a fit score to approve, then writes your package.

## What CoApply is

Your partner for the jobs you actually want. Point it at a job posting and it researches the role, scores how well you fit, **pauses for you to decide go/no-go**, then writes a cover letter, tailors your resume, drafts outreach, and preps you for the interview — in your voice, from your profile. It never auto-submits and never scrapes job sites. You make the call on each job and you hit submit.

## The commands

- **`/coapply:setup`** — first-time setup. Copies the profile templates into your folder, confirms how runs are paid (usually your Claude plan — no extra charge), and helps you pick a budget tier.
- **`/coapply:start <job url or text>`** — begin an application. Does triage, then stops at a fit-check gate for your go/no-go. On a go, it generates the full package into a run folder.
- **`/coapply:add <thing>`** — teach CoApply in plain language so future runs sound more like you: a **writing rule** ("from now on, never open by explaining the company to itself"), an **example** of your own writing to match your voice ("save this as an example"), or a **personal fact** like your location or target salary. It confirms where each goes and refuses to store true secrets.
- **`/coapply:tier`** — change your budget tier (`lite` / `standard` / `full`) anytime.
- **`/coapply:resume <run>`** — pick a run back up if it was interrupted.
- **`/coapply:list`** — list your recent runs.
- **`/coapply:feedback`** — hit a bug or have an idea? Describe it in plain words and CoApply turns it into a ready-to-file GitHub issue (structured, with version/OS auto-filled) plus a one-click link. You review and post it — it never submits for you.
- **`/coapply:help`** — this.

## Making it yours over time

CoApply gets more "you" the more you use it. Tell it your **rules** and it follows them on every future letter; give it **examples** of your own writing and it matches your voice (it imitates how you sound, never copies your facts); add **facts** (location, target comp, work-authorization) and it fills them into applications. Just say `/coapply:add` or talk to it in plain language ("remember I'm based in Austin"). Every run ends with a short receipt showing exactly which of your rules and examples shaped that application — so you can see it actually used your input.

## First-time setup

CoApply writes *as you*, so it reads a profile folder you control. Set it once: run `/plugin`, open CoApply, and set your **Profile folder** to a directory you control. Then run **`/coapply:setup`**, which copies the templates in for you (`identity.md`, `skills-experience.md`, `voice-profile.md`, `positioning-modes.md`, and a `resumes/` folder), confirms how runs are paid (usually your Claude plan — no extra charge), and helps you pick a budget tier. Start by filling in `identity.md`, `skills-experience.md`, and one resume — that's enough for a first run; deepen it over time and every run gets better.

## The gate

The most important part: after triage, CoApply **stops** and shows you a fit score, the reasons, and any red flags. Nothing expensive runs until you say go. That's the point — it helps you skip bad-fit roles, not mass-apply.

## Privacy

Your profile and your run output stay on your machine. Nothing is uploaded except to your own Claude. CoApply never submits applications for you and never logs into job sites.

## What to do right now (always end with this — check, don't ask)

Don't ask the user whether they're set up — **check, then give exactly one next action.** Resolve the profile folder and inspect it:

```bash
PROFILE_DIR="$("${CLAUDE_PLUGIN_ROOT}/scripts/resolve-profile-dir.sh")"
if [ -z "$PROFILE_DIR" ]; then echo "STATE=no-folder"
elif [ ! -f "$PROFILE_DIR/identity.md" ]; then echo "STATE=no-files"
elif ! grep -q '[A-Za-z]' "$PROFILE_DIR/identity.md" 2>/dev/null; then echo "STATE=empty"
else echo "STATE=ready"; fi
```

Then print exactly one closing line based on `STATE` (print the bold text only — do NOT wrap it in quotation marks):
- `no-folder` → **Next: run `/coapply:setup` to get started.**
- `no-files` → **Next: run `/coapply:setup` to add your starter files.**
- `empty` → **Almost there — fill in `identity.md`, `skills-experience.md`, and one resume in `resumes/`, then run `/coapply:start <job>`.**
- `ready` → **You're set up. Run `/coapply:start <job posting>` to make your application.**

Never end with "want me to check?" — you just did.
