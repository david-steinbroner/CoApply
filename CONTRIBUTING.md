# Contributing to CoApply

CoApply is a Claude Code plugin — a profile-driven, field-agnostic engine that turns a job posting into a complete, fit-gated application package. Contributions welcome; a few things keep it working.

## Local testing

Run the plugin against a throwaway profile so you never touch your real one:

```bash
CLAUDE_PLUGIN_OPTION_PROFILE_DIR=/path/to/a/throwaway/profile claude --plugin-dir .
```

Then run `/coapply:start <a real job posting>` and confirm it reaches the human go/no-go gate. After editing any plugin file, run `/reload-plugins` to pick up the changes.

## The boundaries that matter

- **Keep the engine generic.** No personal data, no field/PM assumptions. The engine must work for any user in any field — a nurse, a teacher, an accountant. All discipline-specific judgment comes from the user's profile, not the engine.
- **Entry points are skills, not commands.** `${CLAUDE_PLUGIN_ROOT}` is substituted in skill/agent/hook content but **not** in plugin commands — so the orchestrator and its entry points must be skills (`skills/*/SKILL.md`).
- **The orchestrator hands subagents absolute paths.** Subagents don't inherit the path variables. The orchestrator resolves `${CLAUDE_PLUGIN_ROOT}` / `${PROFILE_DIR}` / `${RUNS_DIR}` to real absolute paths and passes those down — never a literal `${...}`.

See `CLAUDE.md` for the full working rules and `PRINCIPLES.md` for the invariants no change may weaken (the human gate, no fabrication, staying in lane).

## Before a PR

1. Run `bash scripts/audit.sh` — it must pass (no personal-data or field-assumption leaks, structure intact).
2. Bump `version` in `.claude-plugin/plugin.json`.
3. Add a top entry to `CHANGELOG.md`.

## Etiquette

- Open an issue to discuss anything large before you build it.
- Keep PRs focused — one concern per PR.
- Contributions are accepted under the MIT license.
