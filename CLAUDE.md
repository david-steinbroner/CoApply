# Working on CoApply

Standards: inherits ../engineering-standards.md. Overrides & project-specifics below.

Rules for anyone — human or AI — changing this repo. CoApply is a Claude Code plugin: a profile-driven, field-agnostic engine that turns a job posting into a complete, fit-gated application package. It was built solo by a PM with Claude Code as the engineering partner; these rules keep that disciplined.

## Non-negotiable invariants (see `PRINCIPLES.md`)

Never weaken these:
- The human go/no-go gate stays. No change may auto-submit, skip the gate by default, or run the expensive agents before it.
- No fabrication — claims trace to the user's profile.
- Stay in bounds — read the profile + engine files, write only to the runs folder; no network exfiltration, no logging into job sites.

## Keep the engine generic

This is the rule most likely to rot. The engine must work for **any field** (a nurse, a teacher, an accountant — not just a PM) and for **any user**.
- **No personal data** in the engine: no names, no real employers/metrics/projects as examples, no personal paths, no account IDs.
- **No field assumptions**: don't bake in "PM"/"product"/"roadmap" framing. Discipline-specific judgment comes from the user's profile (`positioning-modes.md`, optional `principles.md`), via the `$USER_TARGETS` token.
- Personal and field-specific content lives in the user's **profile**, never in the engine. Respect that boundary.

## Architecture facts that bite if you forget them

- **Entry points are skills, not commands.** `${CLAUDE_PLUGIN_ROOT}` is substituted in *skill/agent/hook* content but NOT in plugin commands. The orchestrator must be a skill (`skills/*/SKILL.md`).
- **Subagents don't inherit the path variables.** The orchestrator resolves `${CLAUDE_PLUGIN_ROOT}` / `${PROFILE_DIR}` / `${RUNS_DIR}` to absolute paths and hands the real paths to every dispatched agent. Never pass a literal `${...}` to a subagent.
- **User profile location** comes from the plugin's `userConfig.profile_dir` (env `CLAUDE_PLUGIN_OPTION_PROFILE_DIR`). Resolve it via Bash; abort clearly if unset.
- **File-based handoff.** Agents communicate through files on disk, not return messages. An agent says "done" → verify the file.

## Before you commit

1. **Run the audit:** `bash scripts/audit.sh`. It must pass (no personal-data or field-assumption leaks, structure intact). This is the tripwire that keeps the engine generic.
2. **Bump the version:** update `version` in `.claude-plugin/plugin.json` and add a top entry to `CHANGELOG.md`.
3. **Smoke-test if you touched the engine:** `claude --plugin-dir .` with a throwaway profile, run `/coapply:start` against a real posting, confirm it reaches the gate.

## Working stance

Best idea wins regardless of source. When stuck, change the approach — restart clean, get more literal — don't just refine the failing one. Judgment is the job: the taste calls (what's a real fit, what reads as slop, where to step in) are the point.
