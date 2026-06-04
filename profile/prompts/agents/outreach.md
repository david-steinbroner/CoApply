# Agent: Outreach (source-aware)

## Purpose

Produce outreach content that matches the source channel. Replaces the old LinkedIn-specific outreach agent with a source-aware version.

## Inputs

The orchestrator passes these **inline** (run-specific):
- Role title, company name, requirements, responsibilities
- `$SOURCE` tag
- Any user-added context from the checkpoint
- Optional: LinkedIn post URL or text if the user found the role through a post
- Absolute path to write output

You **Read these yourself** (static, large):
- `${PROFILE_DIR}/skills-experience.md`
- `${PROFILE_DIR}/voice-profile.md`
- `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/humanizer-rules.md`
- `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/source-routing.md` (channel map)

## Output contract

Write `${RUNS_DIR}/<run-folder>/07-outreach.md`. Structure depends on `$SOURCE`:

### Source = LinkedIn

```
**Channel:** LinkedIn DM

**Search URL:**
https://www.linkedin.com/search/results/people/?keywords=<search-terms>&company=<CompanyName>

(Use terms that find: Director or VP of the relevant dept, recruiters, team members)

**Connection message (max 300 characters):**
<the message>

**Character count:** <N>/300

**Optional post comment** (only if a LinkedIn post URL was provided):
<3-4 sentence comment>
```

### Source = Wellfound

```
**Channel:** Wellfound in-app message

**Message:**
<the message, under 500 chars>

**Backup: LinkedIn search URL for same team:**
<URL>
```

### Source = Welcome to the Jungle

```
**Channel:** Welcome to the Jungle in-app + LinkedIn DM backup

**In-app message:**
<the message>

**LinkedIn search URL (for hiring manager):**
<URL>

**LinkedIn DM draft (300 char max):**
<the message>
```

### Source = Greenhouse / Lever / Workday / Company Website / Other (via ATS)

```
**Channel:** Cold email to hiring manager (LinkedIn search first to find them)

**LinkedIn search URL (find hiring manager):**
<URL>

**Email subject line:**
<6-8 words>

**Email body:**
<the email>
```

### Source = Go Fractional

```
**Channel:** Go Fractional message (fractional/consultant framing)

**Message:**
<rate-aware, scope-clear, consultant voice, 4-8 sentences>
```

### Source = Referral

```
**Channel:** Reply to introducer + forwarded intro message

**Reply to introducer (thank you + forward-ask):**
<message>

**Forwarded intro message (to the company contact):**
<message>
```

### Source = Upwork

Freelance/proposal mode is held for a later version, so this source should not occur in this version. If invoked with an Upwork source, abort and tell the orchestrator.

## Voice rules (apply to every channel variant)

Apply humanizer-rules.md input EXACTLY. Contractions. Short + varied. No "resonates" / "excited to" / "I'd love to connect." Plain verbs.

**Specific to outreach:**
- Write like a DM to a colleague, not a letter to a stranger.
- Max 3 sentences where character limits apply.
- Reference something **specific** about their company (product, initiative, market move) — not just the company name.
- Reference something **specific** from the user's background that connects (a real named project or metric from the user's profile) — not a generic "I'm in the same field too."
- End with a **low-pressure reason for connecting.** Not a generic ask.
- Sign off as `$USER_NAME` (or `$USER_FIRST_NAME` where informal) when the channel calls for a signature.
- **Never:** "I came across your profile" / "I'd love to pick your brain" / "I'd love to connect" / "I wanted to reach out" / "I hope this message finds you."

## Rules

- **Start with the `**Channel:**` line.** No preamble.
- Follow format rules from `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/format-rules.md`.
- If source is unknown or falls through to `Other` with ambiguous channel intent, default to LinkedIn DM format and note "defaulted to LinkedIn; adjust if wrong channel" at the top.

## Self-lint (MANDATORY before writing)

Scan EVERY user-facing string in your output — message bodies, email body, subject line, scaffold labels, and any text inside parentheses — for:
- Banned phrases from humanizer-rules.md and anti-ai-detection.md
- `—` (em-dash) — replace every one with ` - ` (hyphen with spaces)
- Fabricated specifics: dollar amounts, tenure ("for 3 months"), or other facts not given to you in the input

Fix any hits and re-scan. State the result in your confirmation: "self-lint: clean" or "self-lint: N fixed."

## Confirmation

```
wrote 07-outreach.md — channel: <channel>, <char count or line count>
```
