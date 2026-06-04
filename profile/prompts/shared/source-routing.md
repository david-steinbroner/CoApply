# Source Routing

Maps a URL (or lack of URL) to a source tag. Used by the start skill at invocation, by the outreach agent for channel selection, and (when tracker logging is enabled) by the tracker-log step for the Source column.

## Hostname → Source tag

Source tag values are **the exact strings used by the Notion Applications DB Source select** (when Notion logging is enabled via `$NOTION_DB_ID`). Do not invent new ones — if a domain doesn't match, fall through to `Company Website` or `Other` per the fallback rules.

| Hostname contains | Source tag | Upwork fork? |
|---|---|---|
| `linkedin.com` | `LinkedIn` | No |
| `upwork.com` | `Upwork` | Freelance/proposal mode held for a later version — surface to the user, do not route |
| `wellfound.com`, `angel.co` | `Wellfound` | No |
| `boards.greenhouse.io`, `greenhouse.io` (job page) | `Greenhouse` | No |
| `jobs.lever.co` | `Other` (Lever not in Notion list) | No |
| `myworkdayjobs.com`, `workday.com` (job page) | `Other` (Workday not in Notion list) | No |
| `welcometothejungle.com` | `Welcome to the Jungle` | No |
| `gofractional.com`, `go-fractional.com` | `Go Fractional` | No (but treat as fractional-leaning — see below) |
| any other company domain | `Company Website` | No |
| no URL (text-only paste) | `Other` | No |

## Referral and email-intro

The skill cannot auto-detect these. If the user invokes CoApply and mentions in their message (or the pasted text's framing) that it's a referral or warm intro, **ask once** before Phase A begins: "Is this a referral or warm intro?" If yes, set source to `Referral` and adjust outreach to the warm-reply template.

## Aggregator rejection

Reject these domains. Parser should abort with "paste the original company URL or post a fresh URL from the company's career page":

- `indeed.com`
- `glassdoor.com` (yes, Glassdoor is a valid Source value in Notion — for logging — but the URLs themselves are aggregator pages; parse the JD from the company source and set Source manually if needed)
- `ziprecruiter.com`
- `simplyhired.com`
- `monster.com`
- `careerbuilder.com`

## Text-input content-based fork warning

Source routing is **URL-domain-only**. Never infer `Upwork` from keywords in text-input. If the user pastes freelance/contract text without a URL, source = `Other`.

Exception: if the JD body contains keywords `contract`, `1099`, `hourly`, `SOW`, or `contract-to-hire`, surface it once at the checkpoint: "This looks like contract/freelance work — note that a dedicated proposal mode is coming in a later version. Continue as a standard application package?" Continue in standard mode unless the user says otherwise.

## Outreach agent: channel map

The `outreach` agent uses source to pick channel templates:

| Source | Default outreach |
|---|---|
| `LinkedIn` | LinkedIn DM (search URL + 300-char msg + optional post comment) |
| `Wellfound` | Wellfound in-app message |
| `Welcome to the Jungle` | In-app message + LinkedIn search for hiring manager |
| `Greenhouse`, `Company Website`, `Other` (via ATS) | Cold email to hiring manager — do LinkedIn search first |
| `Go Fractional` | Fractional-framed message (consultant voice, rate-aware) |
| `Referral` | Warm reply to introducer + forwarded intro message |
| `Upwork` | Freelance/proposal mode held for a later version — not handled in this version |

## Matching rules

- Pattern matching is **most-specific-first**. `boards.greenhouse.io` before `greenhouse.io`.
- Hostname comparison is **case-insensitive** and checks `hostname.includes(pattern)`.
- URL canonicalization before matching: lowercase hostname, strip `www.`.

## Domain-specific fetcher hints

Some ATS pages are JS-rendered SPAs — WebFetch will return only the meta description, not the JD body. Use these direct endpoints **first**, before falling back to WebFetch or asking the user to paste:

| Hostname | Fetch this instead | Notes |
|---|---|---|
| `apply.workable.com` | `https://apply.workable.com/<account>/jobs/view/<id>.md` | Returns clean markdown of the full JD. Pattern: take the URL `apply.workable.com/<account>/j/<id>/`, transform `/j/<id>/` → `/jobs/view/<id>.md`. |
| `boards.greenhouse.io` | `https://boards-api.greenhouse.io/v1/boards/<board>/jobs/<id>?content=true` | Returns JSON with full HTML content. URL pattern: `boards.greenhouse.io/<board>/jobs/<id>`. |
| `jobs.lever.co` | `https://jobs.lever.co/<company>/<id>?format=json` (some companies); otherwise WebFetch the page directly — Lever pages are mostly server-rendered | |
| `*.myworkdayjobs.com` | WebFetch first; Workday pages vary. If <500 chars returned, ask the user to paste. | |

**Procedure for the orchestrator:** if the JD URL hostname matches a hint above, use Bash `curl -sL` against the transformed endpoint and skip WebFetch entirely. Only fall back to WebFetch if the curl returns non-200 or <500 bytes. Save the raw response to `/tmp/<slug>-jd.<ext>` then read into context.
