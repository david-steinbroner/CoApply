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

## Step 1 — Copy the profile templates (only the missing ones)

Copy in any template files the profile doesn't already have, and **never overwrite** files the user has filled in. Don't skip the whole copy just because one file (e.g. `identity.md`) exists — fill in only what's missing.

Use `cp -Rn` (no-clobber) so existing files are left untouched, then report what was added vs. already present:

```bash
mkdir -p "${PROFILE_DIR}"
before=$(cd "${PROFILE_DIR}" && find . -type f | sort)
cp -Rn "${CLAUDE_PLUGIN_ROOT}/profile.example/." "${PROFILE_DIR}/"
after=$(cd "${PROFILE_DIR}" && find . -type f | sort)
echo "ADDED:"; comm -13 <(echo "$before") <(echo "$after")
echo "ALREADY PRESENT:"; echo "$before"
```

Report to the user which files were **added** and which were **already present** (left as-is). If everything was already present, say so — nothing was overwritten.

Then tell them what to fill in next:

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

## Step 5 — Optional: connect a tracker

Offer this as clearly optional and **off by default** — most people skip it:

> Want CoApply to log each application to a Notion database? **Most people skip this.** If yes, I'll set a `NOTION_DB_ID` in your config — and you should know this will send application data to Notion, a third party. If no (the default), nothing is logged anywhere but your own machine.

- **If they decline (default):** do nothing — no tracker, no data leaves their machine. Move on.
- **If they want it:** ask for their Notion database ID, then add it to the config (preserving the tier already written):

  ```bash
  printf '{"tier": "%s", "notion_db_id": "%s"}\n' "<choice>" "<notion-db-id>" > "${PROFILE_DIR}/coapply.config.json"
  ```

  Confirm it's saved and remind them application data will now be sent to Notion. They can remove `notion_db_id` from the config anytime to turn logging back off.

## Step 6 — Done

Tell them they're set:

> All set. Once your profile is filled in, run `/coapply:start <job posting>` (a URL or pasted text) to begin.
