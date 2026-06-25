# CoApply — Operating Principles

The invariants every CoApply run honors. These are not aspirations; they are rules the engine follows and that any change to it must preserve. They're also a fair description of what the tool will and won't do, so you know what you're installing.

## What CoApply always does

- **Stops for you.** Every run passes a human go/no-go gate after triage. Nothing expensive runs until you decide. The gate is the product, not a speed bump.
- **Writes as you, from your material.** Output is grounded in your profile and matched to your voice.
- **Keeps every step inspectable.** Each agent writes its output to a file in the run folder; nothing important hides in a transcript. You can open any artifact and see exactly what was produced and why.
- **Tells the truth about fit.** It surfaces low fit, gaps, and red flags honestly — and distinguishes "low fit" from "something errored." It will recommend *against* applying when that's the right call.

## What CoApply never does

- **Never auto-submits.** You review and submit every application yourself. Always. (This is permanent — not a v1 limitation.)
- **Never fabricates — anywhere, not just applications.** In application output, every factual claim (a metric, project, employer, credential) must trace to your profile or it gets cut, not invented. The same rule binds *everything* the tool writes on your behalf: when a skill turns your words into something to send — a cover letter, an outreach note, a bug report — it captures what you said and adds nothing you didn't. It never composes a rationale, motivation, or detail you didn't give. Short and faithful beats complete and invented.
- **Never scrapes behind logins or hits aggregators.** It works from a job posting you provide, or from public ATS boards it fetches over plain HTTP; it does not log into job sites or harvest aggregator listings. `/coapply:discover --auto` uses a web search only to find first-party ATS board *tokens* — never as a source of job data — then fetches each company's own board.
- **Never leaves its lane.** It reads your profile and the plugin's own engine files, and writes only to your runs folder (setup and tier also write to your own profile folder — config and templates — still your machine, not a third party). It does not touch anything else.
- **Never sends your data anywhere but your own Claude** — unless you explicitly connect an optional integration (e.g. a Notion tracker, off by default), or you run `/coapply:discover --auto`, which sends your **target-role and location keywords** (not personal data) to a web search provider to find companies that are hiring. Both are opt-in and named in the open, never hidden. No server, no telemetry, no covert third party.

## How this maps to the product principles

These invariants are the build-time principles in `product-principles.md` made concrete:

- **No "God Agent."** CoApply is a pipeline of focused agents with file handoffs and a deliberate human checkpoint — not one monolith.
- **Direct AI with goals, verify confident claims.** Each agent has an output contract and self-checks; the "never fabricate" rule is the verification applied where models are most confidently wrong.
- **Context is the product.** The durable work is structuring the run — every step's output lands in a known file, constrained to a known shape.
- **Optimize for the workflow, not the demo.** The gate, the compounding profile, and the honest fit-check exist to make the *considered* application good, not to impress.
- **Observability:** v1's observability surface is the inspectable run folder + `_run.json` (phase, per-artifact status). Richer tracing and per-agent cost (the dashboard) is on the roadmap — stated plainly rather than implied.

## Conscious non-goals

- **Not provider-agnostic.** CoApply is Claude-Code-native by design (its orchestration relies on Claude Code). That's a deliberate architecture choice, not an oversight.
- **Not a volume tool.** It optimizes the quality of applications you actually want, not the count of applications sent.
