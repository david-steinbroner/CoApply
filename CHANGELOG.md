# Changelog

All notable changes to CoApply. Versioned on the `plugin.json` version line.

## [1.0.0] — 2026-06-04 — Initial public release

A Claude Code plugin that turns a job posting into a complete, voice-matched, fit-gated application package — research → fit-score → a human go/no-go gate → cover letter, tailored resume guidance, outreach, interview prep. Profile-driven and field-agnostic; never auto-submits.

### Included

- **Commands:** `/coapply:start`, `/coapply:resume`, `/coapply:list`, `/coapply:help`.
- **Engine:** a master orchestrator + 13 focused agents + 2 phase dispatchers + shared voice/format/anti-AI rules. File-based handoffs, a mandatory human checkpoint, retry-once verification.
- **Profile templates** (`profile.example/`): identity, skills/experience, voice, positioning modes, portfolio links, resumes — field-neutral, fill-in-once, gets stronger as you add to it.
- **Config:** profile folder via the plugin's `userConfig`; optional external tracker (`$NOTION_DB_ID`) off by default.
- **Governance:** operating principles (`PRINCIPLES.md`), contributor rules (`CLAUDE.md`), a release audit (`scripts/audit.sh`), security posture (`SECURITY.md`), MIT license.

### Known limitations

- Observability is the inspectable run folder + `_run.json`; richer tracing/cost (a dashboard) is on the roadmap.
- No guided onboarding yet (`/coapply:setup` is planned); set up the profile from the `profile.example/` templates for now.
- Per-agent model tiering / a cheaper "lite" mode is planned, not yet shipped.
- Freelance/proposal mode is held for a later version.
