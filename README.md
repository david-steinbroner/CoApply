# CoApply

**Your partner for the jobs you actually want. It drafts, you decide, you send — never an auto-bot.**

You give CoApply a job description. It researches the company, scores how well you fit, **pauses to let you decide whether the role is worth it**, and then writes a cover letter, tailors your resume, drafts an outreach email, and preps you for the interview — all in your own voice, grounded in your real experience.

The "co-" is the whole point. CoApply works *with* you, not *for* you: it doesn't mass-submit, it doesn't scrape job sites, and it never applies on your behalf. You bring your story, you make the call on each job, and you hit submit yourself. CoApply just makes the application *genuinely good*.

---

## What you need first

CoApply runs inside **Claude Code** — a tool from Anthropic that lets Claude work on your computer. If you don't have it yet:

1. Go to **[claude.com/claude-code](https://claude.com/claude-code)** and follow the install steps for your computer (Mac, Windows, or Linux).
2. You'll sign in with a Claude account. (Using Claude Code requires a paid Claude plan or API credits — that's Anthropic's cost, not ours.)

That's the only prerequisite. **You do not need to know how to use GitHub, git, or write any code.** CoApply installs itself from inside Claude Code with two short commands.

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
   Press Enter and confirm. Done — CoApply is now part of your Claude Code.

> **What just happened?** You didn't download anything manually or touch GitHub directly. Claude Code fetched CoApply for you. If those two commands worked, you're fully installed.

---

## Set up your profile (first time only)

CoApply writes *as you*, so it needs to know your experience and voice. You fill this in once, and it makes every future application better.

**The easy way (coming soon):** run `/coapply:setup` and answer a short interview — CoApply builds your profile from your answers (or from a resume you paste in).

**The manual way (available now):** copy the templates from the `profile.example` folder into your own profile folder and fill in each file. Each template has instructions inside it. Start with `skills-experience.md` and one resume — that's enough for a first run. You can deepen it anytime; **the more you add, the better CoApply gets.**

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

Other commands you'll find handy:
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
- **Simple settings** (which model it uses, a cheaper/lighter mode, how strict the gate is) live in a small config file you control — _coming soon_, and they survive updates.
- **Deeper changes** (rewriting how a specialist works) are possible too; see the full docs.

---

## The dashboard (coming soon)

A local dashboard — a private web page showing your applications, what each step cost, and the gate decisions — is on the roadmap. It'll be an optional add-on; CoApply works fully without it.

---

## Your privacy

- Your profile and your applications **stay on your computer.**
- Nothing is sent anywhere except to **your own** Claude, the same as any Claude Code session.
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

---

## Principles & limits

CoApply runs on a short set of invariants — it always passes a human gate, never auto-submits, never fabricates (every claim traces to your profile), stays in its lane (reads your profile, writes only to your runs folder), and never sends your data anywhere but your own Claude. The full list: **[PRINCIPLES.md](PRINCIPLES.md)**.

Honest about what it isn't yet:
- Observability is the inspectable run folder + `_run.json`; a richer cost/tracing dashboard is on the roadmap.
- Guided setup (`/coapply:setup`) is planned — for now you fill in the `profile.example/` templates.
- A cheaper "lite" mode, and freelance/proposal mode, are planned but not shipped.

---

## How this was built

CoApply was built by David Steinbroner with Claude Code — and it's a working example of the thing it does. The same principle runs through the tool and its own construction: direct AI with clear goals, keep a human at the gate, verify before anything ships, never settle for slop. The product thinking, the architecture, and the decisions are mine; Claude Code is the build loop. If you want to see what "AI-native but human-directed" actually looks like, the commit history is part of the demo.

## License

MIT — see [LICENSE](LICENSE). You're free to use, fork, and build on it.
