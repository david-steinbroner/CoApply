# Changelog

All notable changes to CoApply. Versioned on the `plugin.json` version line.

## [0.1.2] — 2026-06-04 — Fix: profile folder not found (blocked all commands)

**Critical fix.** Every command aborted with "CoApply isn't configured" even when the Profile folder was set, because the skills read `$CLAUDE_PLUGIN_OPTION_PROFILE_DIR` in a Bash-tool call — and Claude Code only exports that variable to plugin *subprocesses* (hooks, MCP), never to the Bash tool a skill runs. So it was always empty for users.

### Fixed
- Added `scripts/resolve-profile-dir.sh`, which resolves the profile folder from the env var when present, then falls back to reading `pluginConfigs."coapply@*".options.profile_dir` from `settings.json` (the value Claude Code reliably saves). Portable: `python3` → `jq`.
- `start`, `setup`, `tier`, `list`, and `resume` now resolve the profile folder via the resolver instead of reading the env var directly.
- The SessionStart nudge hook uses the same resolver as a fallback.

## [0.1.1] — 2026-06-04 — Onboarding next-step guidance

Closes the "now what?" gaps in the first-run experience.

### Added
- **First-run nudge** — a `SessionStart` hook points new users at `/coapply:setup` (or, if no profile folder is set, at `/plugin`) until their profile is configured, then goes permanently silent (keys off whether `identity.md` exists — no state file).
- **Next-step lines** — `/coapply:tier`, `/coapply:list`, and the post-run summary (`/coapply:start` and `/coapply:resume`) now end with an explicit `Next:` line so the user is never left at a blank prompt.
- **README** — the install section now spells out the post-install screens (install scope, the Profile-folder prompt, the confirmation line) and the first step after; plus an optional status-line snippet for a persistent next-step hint.

### Changed
- `/coapply:setup`'s "not configured" message now tells the user to make a profile folder first.

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
- `profile.example/` field-neutral templates; `/coapply:setup` copies in only the missing ones (never overwrites filled-in files).
- **Optional Notion tracker** — off by default; can be connected during `/coapply:setup` to log applications to a Notion database. Most users skip it; nothing leaves your machine unless you turn it on.
- `PRINCIPLES.md` (invariants), `CLAUDE.md` (contributor rules), `CONTRIBUTING.md`, `SECURITY.md`, `scripts/audit.sh` (release audit), MIT license.

### Known limitations
- Observability is the inspectable run folder + `_run.json`; a richer cost/tracing dashboard is on the roadmap.
- Gate cost figures are rough heuristics, not a live token meter.
- Per-agent model tiering (cheaper models on lite) isn't wired yet — tiers vary the agent *set*, not the model.
- Freelance/proposal mode is held for a later version.
