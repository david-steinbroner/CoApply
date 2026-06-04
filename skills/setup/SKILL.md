---
name: setup
description: Set up CoApply — copy profile templates, check billing, pick a budget tier.
---

# CoApply — first-time setup

Walk the user through getting CoApply ready: copy the profile templates into their folder, check how runs will be billed, and pick a default budget tier. Be concise and friendly; do one step at a time and confirm as you go.

## Step 0 — Resolve the profile folder (do this first)

Run one Bash call:

```bash
echo "PROFILE_DIR=$CLAUDE_PLUGIN_OPTION_PROFILE_DIR"
```

If `$CLAUDE_PLUGIN_OPTION_PROFILE_DIR` is **empty**, stop and tell the user:

> CoApply doesn't have a Profile folder yet. Run `/plugin`, open **CoApply**, set the **Profile folder** to a directory you control, then re-run `/coapply:setup`.

Do not continue past this step until it resolves. From here on, use the resolved absolute path wherever this file shows `${PROFILE_DIR}`. The engine's templates live under `${CLAUDE_PLUGIN_ROOT}/profile.example/` — `${CLAUDE_PLUGIN_ROOT}` is already substituted to the real install path in this skill, so use that resolved value.

## Step 1 — Copy the profile templates

Check whether the profile is already populated:

```bash
test -f "${PROFILE_DIR}/identity.md" && echo EXISTS || echo MISSING
```

- **If MISSING:** copy the templates in, then list what landed:

  ```bash
  mkdir -p "${PROFILE_DIR}" && cp -R "${CLAUDE_PLUGIN_ROOT}/profile.example/." "${PROFILE_DIR}/" && ls -1 "${PROFILE_DIR}"
  ```

  Confirm to the user which files landed.

- **If EXISTS:** say the profile's already set up and **skip the copy** — do not overwrite anything they've already filled in.

Either way, tell them what to fill in next:

> Open and fill in **`identity.md`**, **`skills-experience.md`**, and at least one file in **`resumes/`** — that's the minimum for a first run. Deepen `voice-profile.md`, `positioning-modes.md`, and the rest over time; every run gets better as the profile grows.

## Step 2 — Billing check (live)

Check whether an `ANTHROPIC_API_KEY` is present, both in the current environment and in the user's shell profiles. **Mask any value** — never print the key.

```bash
if [ -n "$ANTHROPIC_API_KEY" ]; then echo "ENV: ANTHROPIC_API_KEY is set (***masked***)"; else echo "ENV: no ANTHROPIC_API_KEY"; fi
grep -lE 'ANTHROPIC_API_KEY' ~/.zshrc ~/.zprofile ~/.bashrc ~/.bash_profile ~/.profile 2>/dev/null || echo "RC: not found in shell profiles"
```

Report honestly based on the result:

- **No key found** (neither in env nor any rc file):
  > You're on your Claude subscription allowance — these runs use your plan, with no per-token charge.
- **Key found** (in env or any rc file):
  > Heads up: an `ANTHROPIC_API_KEY` is set, so Claude Code may bill these runs **per-token** instead of drawing on your subscription. If you meant to use your subscription, unset it. (We can detect that the key is present, not Claude Code's exact billing decision.)

## Step 3 — Cost, in plain words

Explain briefly, without inventing dollar figures:

> Every run uses your Claude Code's model access. A full run is token-heavy — it dispatches many focused agents. The budget **tier** below controls how much each run spends.

## Step 4 — Pick a default tier

Explain the three tiers (relative cost only — lite is cheapest, full is most), recommend `standard`, and ask which they want:

- **lite** — cheapest. Triage → the go/no-go gate → positioning + a cover letter. The essentials.
- **standard** *(recommended)* — lite, plus outreach, resume guidance, interview prep, follow-up, role analysis, and light company research.
- **full** — most expensive. Everything in standard, plus live company web research, a work-sample suggestion, application questions, and a `.docx`.

Once they choose, write the config (replace `<choice>` with their pick — one of `lite`, `standard`, `full`):

```bash
printf '{"tier": "%s"}\n' "<choice>" > "${PROFILE_DIR}/coapply.config.json"
```

Confirm it's saved, and note they can change it anytime with `/coapply:tier`.

## Step 5 — Done

Tell them they're set:

> All set. Once your profile is filled in, run `/coapply:start <job posting>` (a URL or pasted text) to begin.
