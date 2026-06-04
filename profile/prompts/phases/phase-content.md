# Phase B — Content Generation (employee mode)

Dispatched from `master-apply.md` after the user confirms at the Phase A checkpoint.

**Run only the content agents the active tier calls for** (tier table in `master-apply.md` Step 3): **lite** = cover-letter only · **standard** = cover-letter, outreach, resume-update, interview-prep, followup-plan · **full** = those + application-questions (if present). Mark tier-skipped agents `skipped`.

## Wave B1 — Primary content

On **lite**: run ONLY cover-letter, then skip the rest of B1 and all of B2. On **standard** and **full**: spawn these 3 in parallel (batch size 3):

- Task: agent_type `general-purpose`, instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/cover-letter.md` — writes `06-cover-letter.md`
- Task: agent_type `general-purpose`, instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/outreach.md` — writes `07-outreach.md`
- Task: agent_type `general-purpose`, instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/resume-update.md` — writes `08-resume-update.md`

**Inline rule:** inline only run-specific artifacts (parsed JD, prior-wave outputs, conversation-derived context the user added, e.g. their location). Pass static profile files as file **paths** — the agent reads them itself. Inlining + agent-read is double work and burns orchestrator context.

For **cover-letter**:
- Inline: contents of `00-jd-parsed.json`, contents of `04-positioning.md`, any conversation-derived context the user added at the checkpoint
- Read-yourself paths to give the agent: `${PROFILE_DIR}/skills-experience.md`, `${PROFILE_DIR}/voice-profile.md`, `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/humanizer-rules.md`, `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/anti-ai-detection.md`, `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/format-rules.md`

For **outreach**:
- Inline: contents of `00-jd-parsed.json`, the `$SOURCE` tag, any user-added context
- Read-yourself paths: `${PROFILE_DIR}/skills-experience.md`, `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/humanizer-rules.md`, `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/source-routing.md`, `${PROFILE_DIR}/voice-profile.md`

For **resume-update**:
- Inline: contents of `00-jd-parsed.json`, the list of available resume variant PDFs from the user's profile
- Read-yourself paths: all resume markdowns under `${PROFILE_DIR}/resumes/`, `${PROFILE_DIR}/skills-experience.md`, `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/humanizer-rules.md`

**After Wave B1 returns:** verify each file exists + non-empty. Retry-once policy.

## Wave B2 — Follow-up content (batch size 3)

Determine which agents to run:
- `application-questions` — **full tier only**, and only if `00-jd-parsed.json.applicationQuestions` has items
- `interview-prep` — runs on standard / full
- `followup-plan` — runs on standard / full
(On **lite**, none of Wave B2 runs — mark them `skipped`.)

Spawn the applicable agents in parallel (1-3 depending on whether application-questions applies):

- (conditional) Task: instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/application-questions.md` — writes `09-application-questions.md`
- Task: instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/interview-prep.md` — writes `10-interview-prep.md`
- Task: instructed by `${CLAUDE_PLUGIN_ROOT}/profile/prompts/agents/followup-plan.md` — writes `11-followup-plan.json`

**Inline rule (same as Wave B1):** inline only run-specific artifacts. Pass static profile files as paths.

For **application-questions** (if applicable):
- Inline: contents of `00-jd-parsed.json`, contents of `04-positioning.md`
- Read-yourself paths: `${PROFILE_DIR}/skills-experience.md`, `${PROFILE_DIR}/voice-profile.md`, `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/humanizer-rules.md`, `${CLAUDE_PLUGIN_ROOT}/profile/prompts/shared/anti-ai-detection.md`

For **interview-prep**:
- Inline: contents of `00-jd-parsed.json`, contents of `03-company-research.md`
- Read-yourself path: `${PROFILE_DIR}/skills-experience.md`

For **followup-plan**:
- Inline: contents of `00-jd-parsed.json`, the `$SOURCE` tag, today's date

**After Wave B2 returns:** verify + retry-once.

## Phase B output contract

On success, these files exist in the run folder:
- `06-cover-letter.md`
- `07-outreach.md`
- `08-resume-update.md`
- `09-application-questions.md` (if applicable)
- `10-interview-prep.md`
- `11-followup-plan.json`

All `_run.json.artifacts` statuses updated. Return control to master-apply.md Step 5 (docx generation).

## Failure handling

If any Wave B agent fails its retry:
1. Update `_run.json.artifacts[].status = "failed"`
2. Continue Phase B (other agents succeed independently — cover letter success doesn't depend on outreach success)
3. After B completes: report to the user which artifacts failed and offer `/coapply:resume <slug>` to retry them.

Don't abort the whole run for a single failure in Phase B. Partial success is useful.
