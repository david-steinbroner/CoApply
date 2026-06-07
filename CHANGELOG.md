# Changelog

All notable changes to CoApply. Versioned on the `plugin.json` version line.

## [0.2.1] — 2026-06-07 — Onboarding clarity (help skill)

Sharpened the first-run experience using onboarding-CRO + copy-editing passes.

### Changed
- **`/coapply:help` now opens with a numbered "Getting started (first run — ~5 min)"
  path** — set Profile folder → `/coapply:setup` → fill in 3 files → `/coapply:start`.
  Gives a new user one clear, faceplant-proof sequence instead of a flat command list.
- **Help ends with a real next action, not a question.** It now resolves the profile
  state (no-folder / no-files / empty / ready) and prints exactly one definitive next
  step, instead of asking the user "want me to check?".
- **Reworded "checks billing"** → "confirms how runs are paid (usually your Claude plan
  — no extra charge)" so the cost line reassures instead of alarming.
- (No engine change — `/coapply:start` already guards empty/template profiles via its
  pre-flight placeholder + profile-depth checks.)

## [0.2.0] — 2026-06-05 — The Profile Library

Make CoApply a tool you mold over time by talking to it: give it your own writing
rules, your real letters as voice references, and your everyday facts — and it shows
you exactly what shaped each application. Designed + hardened across 3 review rounds
(2 audits + a 3-model brains trust each); rationale in the private apply repo
(`roadmap docs/coapply-modular-profile-spec-v3.md`). Everything lives in your profile
folder, so plugin updates never touch it. Secrets (SSN-grade) are deliberately out of
scope and refused — that's a later, separate design.

### Added
- **`/coapply:add`** — add a rule, an example, or a fact in plain language ("from now
  on never…", "save this as an example", "remember I'm based in Austin"). It confirms
  where each thing goes (never silent), refuses to store true secrets (no override),
  and caps a rules file at ~20 with a consolidate-or-prune offer so rules don't bloat
  and dilute. `scripts/scan-pii.sh` is the deterministic secret guard: it flags only
  true secrets (SSN, card/bank/account numbers, passwords, API keys, IBANs, exact
  street address), **allows** the everyday middle tier (salary, city, work-auth,
  phone), and prints redacted flags that never include the actual digits.
- **`facts.md`** — a home for everyday personal facts (location, target comp,
  work-authorization, start date) the AI legitimately needs to fill in applications.
  Honest framing: it's sent like the rest of your profile, not a private vault. Read
  by the application-questions and cover-letter agents.
- **Examples (voice few-shot)** — drop real letters/messages in `<profile>/examples/`
  (named `<role>--<tag>--<name>.md`); CoApply uses the most JD-relevant ones as a
  **voice reference only** (imitate cadence, never reuse facts). `scripts/context-pack.sh`
  ranks them by header/JD word-overlap (deterministic `sort` with a filename
  tiebreak), caps by tier (lite none / standard ≤2 / full ≤3) under a byte budget,
  and logs every pick/drop to the run's `.receipt.log`. Wired into the cover-letter,
  outreach, and application-questions agents. The trust receipt now reports which
  examples were **used** vs **set aside** from that log (glob fallback otherwise).
- **Output watermarking** — generated artifacts get an invisible `coapply:generated`
  tag so the upcoming ingest flow can refuse to re-ingest CoApply's own output as an
  "example" (the AI-cannibalism guard).
- **Trust receipt** — every run now ends with a plain-language "What shaped this
  application" block (your background, your rules with a JD-relevant sample, your
  examples) rendered by `scripts/render-receipt.sh`. **Deterministic by design:**
  derived from the filesystem + the run's tier, never the model's recollection.
  Fails closed to "Receipt unavailable" rather than ever implying nothing was used.
  Wired into `master-apply` Step 9, printed verbatim. `audit.sh` regression-tests it.
- **Playbooks** — per-role writing-rule docs in `<profile>/playbooks/<role>.md` the
  agents follow if present (generalizes the `principles.md` pattern). Wired into the 6
  content/strategy agents: cover-letter, positioning, outreach, interview-prep,
  resume-update, application-questions, plus a cross-cutting `general.md`. They're
  hard guidance and override engine defaults where they overlap.
- **Default cover-letter playbook** (`profile.example/playbooks/cover-letter.md`) +
  a plain-language `playbooks/README.md`. Ships universal copy hygiene: don't open by
  explaining the company to itself; keep concrete proof concrete; assert the positive
  directly; no self-promo closers; lead with the work, not the label.

### Version visibility
- **The SessionStart hook now announces the real version when it changes** — e.g.
  `✅ CoApply updated to v0.2.0` on the first session after an update, then stays
  silent. Claude Code auto-applies plugin updates and only shows a generic reload
  notice (the update flow and its lack of an approval step are host behavior a
  plugin can't change), so this is how you confirm which version you're actually on.
- **`/coapply:help` now prints the version** (`CoApply v0.2.0`) as its first line.

### Hardened (after a 7-agent adversarial stress swarm — 0 blockers, 0 serious found)
- **`scan-pii.sh` rewritten to whole-file passes** — ~500× faster on large pastes (no
  per-line subprocess loop); pins `LC_ALL=C` (deterministic, robust to invalid UTF-8);
  now catches modern token shapes (GitHub `ghp_`/`github_pat_`, Stripe `sk_live_`,
  Google `AIza`, GitLab `glpat-`, OpenAI `sk-proj-`, JWTs) and PEM private keys; widens
  card detection to 13-19 digits; and kills false positives (consecutive years read as a
  card, `passwordless`/`secret keynote` substring matches). Still never leaks a digit.
- **`resolve-profile-dir.sh`** — POSIX fallback is now **scoped to CoApply's own config**
  (a different plugin's `profile_dir` can't be picked); honors `settings.local.json` over
  `settings.json`; and truly always exits 0 (no crash when `HOME` is unset).
- **`context-pack.sh`** — pins `LC_ALL=C` for locale-independent ranking; logs the real
  drop reason (count-cap vs over-budget); and skips control-char filenames that could
  make the receipt claim a file was used without emitting it.
- **`render-receipt.sh`** — `- ` lines inside fenced code blocks are no longer counted as
  rules; strips CR so a CRLF-authored playbook doesn't corrupt the quoted sample.
- **`/coapply:help`** now documents `/coapply:add` and the Profile Library (was undiscoverable).
- `audit.sh` extended to 14 checks locking in all of the above.

### Fixed
- **`resolve-profile-dir.sh` had no POSIX fallback** (python3→jq only) — a user with
  neither silently got "not configured" on every command. Added: (1) a robust flat
  `~/.coapply_profile_path` file (written by `/coapply:setup`) as the primary path,
  and (2) a POSIX `grep`/`sed` settings.json fallback so no `python3`/`jq` is required.
  `audit.sh` now regression-tests both with `python3`/`jq` shadowed out.

## [0.1.3] — 2026-06-05 — Docs: saving & parallel-session behavior

Make the persistence/concurrency model explicit so users aren't surprised.

### Added
- **README FAQ** — "Do I need to save before I close?" (no — file-based, auto-saved; mid-run → `/coapply:resume`) and "Can I run several at once / edit my profile in another window?" (parallel runs are safe; don't edit the *same* profile file in two sessions — last save wins, no merge).
- **`/coapply:setup`** ends with a short "good to know": work saves automatically, run as many applications in parallel as you want, don't edit the same profile file in two windows at once.

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
