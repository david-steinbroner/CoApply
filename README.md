# CoApply

**Your partner for the jobs you actually want. It drafts, you decide, you send — never an auto-bot.**

You give CoApply a job description. It researches the company, scores how well you fit, **pauses to let you decide whether the role is worth it**, and then writes a cover letter, tailors your resume, drafts an outreach email, and preps you for the interview — all in your own voice, grounded in your real experience.

The "co-" is the whole point. CoApply works *with* you, not *for* you: it doesn't mass-submit, it doesn't scrape job sites, and it never applies on your behalf. You bring your story, you make the call on each job, and you hit submit yourself. CoApply just makes the application *genuinely good*.

---

## What you need first

CoApply runs inside **Claude Code** — a tool from Anthropic that lets Claude work on your computer. If you don't have it yet:

1. Go to **[claude.com/claude-code](https://claude.com/claude-code)** and follow the install steps for your computer (Mac, Windows, or Linux).
2. You'll sign in with a Claude account. (Using Claude Code requires a paid Claude plan or API credits — that's Anthropic's cost, not ours.)

That's the only prerequisite. **You don't need to touch GitHub or write code** — though you should be comfortable working inside Claude Code (a terminal-based tool). CoApply installs and sets up from there in a few short commands.

---

## Install (about 2 minutes)

1. **Open Claude Code.** Open your Terminal app and type:
   ```
   claude
   ```
   Press Enter. You're now in Claude Code — you'll see a prompt where you can type commands.

2. **Add CoApply's catalog.** Type this and press Enter:
   ```
   /plugin marketplace add david-steinbroner/CoApply
   ```
   _(This just tells Claude Code where to find CoApply. Think of it like adding a channel — nothing is installed yet.)_

3. **Install it.** Type:
   ```
   /plugin install coapply@coapply-marketplace
   ```
   Press Enter. Claude Code then walks you through three quick screens:
   - **Where to install** → choose **Install for you (user scope)** — the default. This makes CoApply available in every folder you work in, not just one project.
   - **Profile folder** → Claude Code asks for a folder to hold your profile and your applications. **Make a new empty folder first** (e.g. `~/coapply-profile`), then enter its path here. This folder is *yours* — your profile lives in it, every application is saved into it, and updates never touch it.
   - **Confirmation** → you'll see a line like `Reloaded: 1 plugin…`. **That means it worked.**

> **What just happened?** You didn't download anything manually or touch GitHub directly — Claude Code fetched CoApply for you and saved your profile-folder choice. **Next step:** fill that folder with your details by running `/coapply:setup` (just below).

---

## Set up your profile (first time only)

Run **`/coapply:setup`** — it copies the profile templates into your folder, checks how your runs are billed, and helps you pick a budget tier. Then open and fill in `identity.md`, `skills-experience.md`, and at least one file in `resumes/` — that's enough for a first run. Deepen the rest over time; **the more you add, the better CoApply gets.**

Your profile lives on **your** computer and is never uploaded anywhere except to your own Claude.

---

## Your first application

In Claude Code, type `/coapply:start` followed by a job posting — a link or pasted text:

```
/coapply:start https://jobs.example.com/posting/12345
```

or just `/coapply:start` on its own, and it'll ask you to paste the job description.

Here's what happens:

1. **CoApply researches and scores the role** against your profile.
2. **It stops and shows you a fit read** — a score, the reasons, and any red flags. **This is your decision point.** You say *go* or *no-go*. Nothing expensive happens until you say go. (This is the whole point — you don't waste effort on jobs that aren't a fit.)
3. **On "go," it writes the full package** — cover letter, resume guidance, outreach email, interview prep, follow-up plan — into a folder for that job.
4. **You review it, make it yours, and submit it.** CoApply never submits for you.

Other commands:
- `/coapply:setup` — first-time setup (templates, billing check, budget tier).
- `/coapply:tier` — change your budget tier (lite / standard / full) anytime.
- `/coapply:list` — see your recent applications.
- `/coapply:resume <run>` — pick a run back up if it got interrupted.
- `/coapply:help` — a quick orientation.

---

## How it works (the short version)

CoApply isn't one big prompt — it's a team of focused specialists working in sequence, with **you as the gate in the middle**:

```
  You give it a job
        │
        ▼
  ┌─────────────┐      ┌──────────────┐
  │  Research    │ ───▶ │  Fit score    │
  │ (company,    │      │  + reasons    │
  │  the role)   │      └──────┬───────┘
  └─────────────┘             │
                              ▼
                    ╔══════════════════╗
                    ║   YOU DECIDE      ║   ← go / no-go checkpoint
                    ║   go or no-go     ║
                    ╚════════┬═════════╝
                             │ (only on "go")
                             ▼
              ┌────────────────────────────────┐
              │  Cover letter · Resume tailoring │
              │  Outreach · Interview prep ·     │
              │  Follow-up plan                  │
              └────────────────────────────────┘
                             │
                             ▼
                   You review & submit
```

Everything it writes is drawn from **your** profile and matched to **your** voice, with built-in rules that keep it from sounding like generic AI.

---

## Keeping CoApply up to date

CoApply improves over time — new capabilities, sharper prompts. Getting the latest is **one command** inside Claude Code:

```
/plugin marketplace update coapply-marketplace
```

Then, if there's a new version, Claude Code will offer to update it. That's it.

**You will never lose your work when you update.** CoApply is built in two separate halves:
- **The engine** (the part you just updated) — owned by us, replaced on update.
- **Your stuff** (your profile and your applications) — owned by you, in a separate place the update never touches.

So you always get the newest version *and* keep everything you've written.

---

## Making it your own (optional)

CoApply works great out of the box. When you want to tweak it:
- **Budget tiers are live** — `/coapply:tier` (or `/coapply:setup`) sets `lite` / `standard` / `full` in a `coapply.config.json` you own; it survives updates. (Per-agent *model* selection — running cheaper models on lite — is on the roadmap.)
- **A persistent next-step hint (optional).** CoApply already nudges you at session start and ends every command with a "Next:" line. If you want a reminder always pinned at the bottom of Claude Code, add a status line to your **own** `~/.claude/settings.json` (this is a Claude Code setting, not part of CoApply — and it replaces any status line you already use):
  ```json
  {
    "statusLine": {
      "type": "command",
      "command": "echo '📋 CoApply · /coapply:start <job> · /coapply:list · /coapply:help'"
    }
  }
  ```
  For a richer, dynamic status line (model, cost, git branch), see Claude Code's [status line docs](https://code.claude.com/docs/en/statusline).
- **Deeper changes** (rewriting how a specialist works) are possible too; see `CONTRIBUTING.md` and `CLAUDE.md`.

---

## The dashboard (coming soon)

A local dashboard — a private web page showing your applications, what each step cost, and the gate decisions — is on the roadmap. It'll be an optional add-on; CoApply works fully without it.

---

## Your privacy

- Your profile and your applications **stay on your computer.**
- Nothing is sent anywhere except to **your own** Claude, the same as any Claude Code session — unless you explicitly connect an optional integration (like a Notion tracker, off by default).
- CoApply **never** submits applications for you and **never** logs into job sites on your behalf.
- We don't run a server, we don't see your data, and there's no account to sign up for beyond your own Claude.

---

## Frequently asked

**Do I need to know how to code or use GitHub?**
No. If you can open the Terminal and type the two install commands, you're set.

**Is it free?**
CoApply itself is free. It runs on Claude Code, which needs a paid Claude plan or API credits (that's Anthropic's, not ours).

**Will it apply to jobs for me automatically?**
No, on purpose. You always review and submit yourself. That's what keeps your applications good.

**Can it find jobs for me?**
Not yet — today you bring the job posting. Discovering roles from public job boards is on the roadmap.

**Do I need to save my work before I close?**
No. CoApply writes everything to disk as it goes — every draft, and every edit to your profile, is a real file saved the moment it's made. Closing a session loses the *chat*, never your *work*. If you close in the middle of a run, just reopen and run `/coapply:resume` — finished pieces are kept, and only the unfinished one re-runs.

**Can I run several applications at once, or edit my profile in another window?**
- Run as many applications in parallel as you like — each gets its own folder, so they never collide. ✅
- Running an application in one window while editing a profile doc in another is fine — just not the *same* file.
- The one thing to avoid: two sessions editing the **same** profile file at the same time (e.g., both re-working the same reference doc). There's no merge step, so the last save wins and one change can be lost.

---

## Cost & limits

CoApply runs on **your** Claude Code's model access — it doesn't add a subscription or charge you anything itself. What a run costs depends on how your Claude Code is set up:

- **On a Claude subscription (Pro/Max):** runs draw your plan's usage allowance — no per-token charge. A full run is token-heavy (a dozen agents), so a busy application day can eat into your limits.
- **On an Anthropic API key:** runs bill per-token to that account.
- *Heads-up:* if you have an `ANTHROPIC_API_KEY` set in your environment, Claude Code may bill per-token even on a subscription. `/coapply:setup` checks this for you.

**You control the spend three ways:**
1. **Tiers** — `lite` (just the cover letter, cheapest), `standard` (the core package — outreach, resume guidance, interview prep, follow-up, role analysis, and light company research), `full` (everything in standard, plus live company web research, a work-sample suggestion, application questions, and a Word doc). Set a default in `/coapply:setup`; change anytime with `/coapply:tier`.
2. **The gate** — before any expensive work, CoApply stops, shows an estimated cost to finish, and lets you run full / standard / lite / or stop.
3. **The pre-screen** — obvious no-go roles get flagged before *any* agent runs, so skipping a bad fit is nearly free.

*Optional tracker:* if you want CoApply to log each application to a Notion database, you can connect one during `/coapply:setup`. It's off by default — most people skip it — and nothing is logged anywhere but your own machine unless you turn it on.

## Principles & limits

CoApply runs on a short set of invariants — it always passes a human gate, never auto-submits, never fabricates (every claim traces to your profile), stays in its lane (reads your profile, writes only to your own folders), and never sends your data anywhere but your own Claude — unless you opt into an integration like a Notion tracker. The full list: **[PRINCIPLES.md](PRINCIPLES.md)**.

Available today:
- Guided setup (`/coapply:setup`) copies the `profile.example/` templates into your folder and walks you through billing and a budget tier.
- Budget tiers (`lite` / `standard` / `full`) are live — set a default in setup, change anytime with `/coapply:tier`.

Honest about what it isn't yet:
- Observability is the inspectable run folder + `_run.json`; a richer cost/tracing dashboard is on the roadmap.
- A freelance/proposal mode is planned but not shipped.

---

## How this was built

CoApply was built by David Steinbroner with Claude Code — and it's a working example of the thing it does. The same principle runs through the tool and its own construction: direct AI with clear goals, keep a human at the gate, verify before anything ships, never settle for slop. The product thinking, the architecture, and the decisions are mine; Claude Code is the build loop. If you want to see what "AI-native but human-directed" actually looks like, the commit history is part of the demo.

## License

MIT — see [LICENSE](LICENSE). You're free to use, fork, and build on it.
