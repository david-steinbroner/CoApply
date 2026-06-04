# Changelog

All notable changes to CoApply. Versioned on the `plugin.json` version line.

## [0.1.0] — 2026-06-04 — Initial public release

A Claude Code plugin that turns a job posting into a complete, voice-matched, fit-gated application package — pre-screen → research → fit-score → a human go/no-go gate → cover letter, tailored resume guidance, outreach, interview prep. Profile-driven and field-agnostic; never auto-submits.

### Commands
- `/coapply:setup` — first-time setup: copies the profile templates into your folder, checks how your runs are billed, sets a budget tier.
- `/coapply:start <job>` — run an application (pre-screen → triage → cost-aware gate → package).
- `/coapply:tier` — change your budget tier (lite / standard / full) anytime.
- `/coapply:resume <run>` — resume an interrupted run (confirms which run first).
- `/coapply:list` — list recent runs.
- `/coapply:help` — orientation.

### Cost control
- **Budget tiers** — `lite` (cover letter only), `standard` (core package), `full` (everything incl. live company research + .docx). Stored in `coapply.config.json`.
- **Cheap pre-screen** flags obvious no-go roles before any agent runs — skipping a bad fit is nearly free.
- **Cost-aware gate** shows an estimated cost-to-finish + your live billing mode (subscription allowance vs per-token API) and lets you pick full / standard / lite / stop.
- README "Cost & limits" section explains the model honestly, including the `ANTHROPIC_API_KEY` billing caveat.

### Engine
- Skill-based entry points (so `${CLAUDE_PLUGIN_ROOT}` resolves); orchestrator hands subagents absolute paths.
- Master orchestrator + 13 focused agents + 2 phase dispatchers + shared voice/format/anti-AI rules; file-based handoffs; mandatory human checkpoint; retry-once verification; invariants enforced (never fabricate / never auto-submit / stay in lane).
- Robustness: cross-platform run-ID (no `openssl`); LinkedIn URLs prompt for pasted text; unfilled-`<placeholder>` preflight guard; case-insensitive voice lint; `.docx` is full-tier-only and degrades gracefully (never crashes the run).

### Profile & governance
- `profile.example/` field-neutral templates; `/coapply:setup` copies them in.
- `PRINCIPLES.md` (invariants), `CLAUDE.md` (contributor rules), `CONTRIBUTING.md`, `SECURITY.md`, `scripts/audit.sh` (release audit), MIT license.

### Known limitations
- Observability is the inspectable run folder + `_run.json`; a richer cost/tracing dashboard is on the roadmap.
- Gate cost figures are rough heuristics, not a live token meter.
- Per-agent model tiering (cheaper models on lite) isn't wired yet — tiers vary the agent *set*, not the model.
- Freelance/proposal mode is held for a later version.
