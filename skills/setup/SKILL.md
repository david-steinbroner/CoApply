---
name: setup
description: Set up CoApply — build your profile from your resume (or fill it in by hand), check billing, pick a budget tier. Also redoes an existing profile from a new resume. Triggers on "set me up", "set up from my resume", "redo my profile from my resume", "import my resume".
---

# CoApply — first-time setup

Walk the user through getting CoApply ready: copy the profile templates into their folder, check how runs will be billed, and pick a default budget tier. Be concise and friendly; do one step at a time and confirm as you go.

## Step 0 — Find the profile folder (internal — do NOT narrate this)

This is plumbing. **Say nothing to the user about it** — no "resolving," no saved-path file,
no settings. Just run it; the user's first words come in Step 1.

Run it **bare** (don't capture it in `VAR="$(…)"` — that can't be allowlisted and would prompt every time). It prints `PROFILE_DIR=…`; use that resolved path wherever this file shows `${PROFILE_DIR}`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-profile-dir.sh"
```

If the printed path is **empty**, stop — this is the one thing only the user can do:

> CoApply needs a folder to keep your profile and applications in. Make a new empty folder
> (e.g. `~/coapply-profile`), then run `/plugin`, open **CoApply**, set the **Profile folder**
> to that path, and re-run `/coapply:setup`.

Otherwise, silently record the path so later commands find it — only when there's no explicit
override (an override is its own source; writing the file would clobber the user's normal setup):

```bash
if [ -z "${CLAUDE_PLUGIN_OPTION_PROFILE_DIR:-}" ]; then
  printf '%s\n' "$PROFILE_DIR" > "${HOME}/.coapply_profile_path"
fi
```

From here use the resolved `${PROFILE_DIR}` and the templates at `${CLAUDE_PLUGIN_ROOT}/profile.example/`
(both already real paths in this skill). The only thing the user hears from this is one plain
line in Step 1.

## Step 1 — Add the starter files, then lead with the resume

Copy the starter files in **silently** (no-clobber, so a filled-in profile is never overwritten),
and note whether this is a fresh folder:

```bash
mkdir -p "${PROFILE_DIR}"
had=$(find "${PROFILE_DIR}" -maxdepth 1 -name '*.md' 2>/dev/null | head -1)
cp -Rn "${CLAUDE_PLUGIN_ROOT}/profile.example/." "${PROFILE_DIR}/"
[ -z "$had" ] && echo "FRESH" || echo "EXISTING"
```

Now — and this is the **first thing the user hears** — give a short, plain preamble: name where
their stuff lives and that the starter files are in. **No file lists, and never the words
"templates," "resolve," "directory," or a saved-path file.**

> Setting up CoApply. Your profile and applications will live in `<the folder>` — on your
> machine, nowhere else. `<FRESH: "Adding your starter files… done." | EXISTING: "Your starter files are already in place.">`

**Re-run check (silent)** — don't push import at someone already set up:

```bash
FILLED=yes
{ [ -f "$PROFILE_DIR/identity.md" ] && [ -f "$PROFILE_DIR/skills-experience.md" ]; } || FILLED=no
find "$PROFILE_DIR/resumes" -maxdepth 1 -name '*.md' 2>/dev/null | grep -q . || FILLED=no
grep -qnE '<[A-Z][^>]*>' "$PROFILE_DIR/identity.md" "$PROFILE_DIR/skills-experience.md" 2>/dev/null && FILLED=no
echo "FILLED=$FILLED"
```

- **`FILLED=yes`** (already-built profile): skip the resume offer; ask instead *"Your profile's
  already filled in — want to rebuild it from a new resume, or are you good?"* Run the import
  (Step 1.5) only if they choose rebuild; otherwise continue to Step 2.
- **`FILLED=no`** → lead straight into the resume offer below.

**Lead with the resume** (this is the point of setup — don't bury it):

> The fastest way to fill these in is your **resume**: paste it here or give me the file path,
> and I'll draft your profile from it — you'll see everything before I save anything. I only use
> what's actually in your resume; where it's thin, I'll flag it instead of guessing. No resume
> handy? I can ask you a few questions instead. Prefer to type it in yourself? Open
> **`identity.md`**, **`skills-experience.md`**, and one file in **`resumes/`** — that's the
> minimum for a first run.

## Step 1.5 — Set up from their resume (the fast path)

Based on how they answer:

In all of the resume/Q&A cases, read `${CLAUDE_PLUGIN_ROOT}/profile/prompts/onboarding/import-resume.md`
and follow it exactly — it reads the resume (fail-closed sanity gate + reflect-back for garbled
PDFs) **or** runs a short no-resume Q&A, drafts `identity.md` + `skills-experience.md` + one
resume **verbatim, never embellished**, shows everything with the original lines beside the
drafted ones, and writes only after the user types `SAVE`.

- **They give a resume, or ask you to build from it** → run the import prompt's resume path.
- **No resume handy** → run the import prompt's **Step 1b** (the short Q&A). Don't make a
  resume mandatory — this is the path for career-changers and new grads.
- **They want to skip for now** → soft fallback, never leave them staring at raw `<placeholder>`
  files: *"No rush — come back and run `/coapply:setup` again whenever, or just paste your resume
  here anytime and I'll build it then."* Then continue.

When the import hands back (or they skip), continue to Step 2. Don't block setup on this —
billing and tier below can be set either way.

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

## Step 6 — Done (and, if the profile's ready, invite the first job)

This is the activation moment — keep it last, with nothing after it.

- **If the profile is filled in** (the resume import ran, or they hand-filled the minimum) —
  invite the first application now, low-pressure, with a visible out, and mention the optional
  voice step:
  > You're all set. Paste a job link or description and I'll build your first application now —
  > or say "done" and come back whenever. *(Optional, anytime: add a couple of things you've
  > written, with `/coapply:add`, so letters sound like you.)*

  If they paste a job, proceed as if they ran `/coapply:start` with it. If they say done, fine.
- **If the profile isn't filled in yet** (they skipped):
  > You're set up. When you're ready, build your profile from your resume by running
  > `/coapply:setup` again, or fill in `identity.md`, `skills-experience.md`, and one resume by
  > hand — then run `/coapply:start <job posting>`.

Then add this short "good to know" so they're never surprised:

> A couple of things worth knowing:
> - Your profile edits **save automatically** — there's no save button; every change is written as it's made, so closing a window never loses it. (One exception: when you first set up from a resume, nothing's written until you review the draft and type **SAVE** — after that, edits auto-save like everything else.)
> - You can run **as many applications in parallel as you want** — each gets its own folder.
> - Just don't edit the **same** profile file in two windows at once (there's no merge — the last save wins).
