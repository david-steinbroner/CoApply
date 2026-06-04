---
name: help
description: How CoApply works — commands, setup, and the gate.
---

# CoApply — how it works

Give the user a short, friendly orientation. Keep it concise and plain; adapt to what they ask.

## What CoApply is

Your partner for the jobs you actually want. Point it at a job posting and it researches the role, scores how well you fit, **pauses for you to decide go/no-go**, then writes a cover letter, tailors your resume, drafts outreach, and preps you for the interview — in your voice, from your profile. It never auto-submits and never scrapes job sites. You make the call on each job and you hit submit.

## The commands

- **`/coapply:setup`** — first-time setup. Copies the profile templates into your folder, checks how runs are billed, and helps you pick a budget tier.
- **`/coapply:start <job url or text>`** — begin an application. Does triage, then stops at a fit-check gate for your go/no-go. On a go, it generates the full package into a run folder.
- **`/coapply:tier`** — change your budget tier (`lite` / `standard` / `full`) anytime.
- **`/coapply:resume <run>`** — pick a run back up if it was interrupted.
- **`/coapply:list`** — list your recent runs.
- **`/coapply:help`** — this.

## First-time setup

CoApply writes *as you*, so it reads a profile folder you control. Set it once: run `/plugin`, open CoApply, and set your **Profile folder** to a directory you control. Then run **`/coapply:setup`**, which copies the templates in for you (`identity.md`, `skills-experience.md`, `voice-profile.md`, `positioning-modes.md`, and a `resumes/` folder), checks billing, and helps you pick a budget tier. Start by filling in `identity.md`, `skills-experience.md`, and one resume — that's enough for a first run; deepen it over time and every run gets better.

## The gate

The most important part: after triage, CoApply **stops** and shows you a fit score, the reasons, and any red flags. Nothing expensive runs until you say go. That's the point — it helps you skip bad-fit roles, not mass-apply.

## Privacy

Your profile and your run output stay on your machine. Nothing is uploaded except to your own Claude. CoApply never submits applications for you and never logs into job sites.

## If they ask "what should I do right now?"

- No profile yet → tell them to run `/coapply:setup`, which copies the templates in for you.
- Profile ready → tell them to run `/coapply:start` with a job posting.
