# CoApply — command reference

Every CoApply command is typed **inside Claude Code** (open a terminal, run `claude`, then type the
command at the prompt). They're all namespaced `/coapply:…`. This page is the quick reference; for the
full walkthrough see [`README.md`](README.md), or run `/coapply:help` in Claude Code.

> **Open the hub:** `/coapply:hub` — your visual command center, served locally at
> **http://127.0.0.1:7878/**. See [The hub](#the-hub) below.

---

## Getting started

| Command | What it does |
| --- | --- |
| `/coapply:setup` | Set up CoApply — build your profile from your resume (or fill it in by hand), check billing, pick a budget tier. Re-run it to redo an existing profile from a new resume. |
| `/coapply:help` | How CoApply works — commands, setup, and the go/no-go gate. |
| `/coapply:tier` | View or change your budget tier (`lite` / `standard` / `full`). |

## Applying to a role

| Command | What it does |
| --- | --- |
| `/coapply:start <url-or-text>` | Begin an application from a job posting — paste a URL or the posting text. Researches the company, scores your fit, **pauses at the human gate**, then (if you say go) writes the cover letter, tailors your resume, drafts outreach, and preps you for the interview. |
| `/coapply:start` | With **no argument**, picks up the roles you staged in the hub's apply queue and hands you one `/coapply:start <url>` per staged job. |
| `/coapply:resume <run-slug>` | Resume a paused or interrupted application run. |
| `/coapply:list` | List your recent application runs. Add `--notion` to include your Notion tracker (if connected). |

## Finding roles

| Command | What it does |
| --- | --- |
| `/coapply:discover` | Check your **watchlist** — the companies you keep a list of — for open roles worth applying to, as a pick-list. |
| `/coapply:discover --auto` | **Auto mode** — no watchlist needed; searches public ATS boards straight from your target roles, then runs the finds through the same pick-list. |
| `/coapply:discover add <careers or ATS board URL>` | Add a company to your watchlist. |

## Tuning & feedback

| Command | What it does |
| --- | --- |
| `/coapply:add <plain-language rule, example, or fact>` | Add something to your profile in plain language so future applications match you better — e.g. "from now on always…", "remember this", "save this as an example". |
| `/coapply:feedback` | Send a bug or idea to CoApply's maintainer — either points you to the issue page, or drafts a ready-to-paste issue from your words. |

---

## The hub

Run **`/coapply:hub`** to open the hub — a private web page served **only on your own machine**
(`127.0.0.1`, loopback, nothing leaves your computer). It renders your whole funnel in one place —
**surfaced roles → the gate → your runs** — with grouping (by seniority or category lane), a filter &
sort lens, and a reversible apply queue.

Once it's running it lives at:

> **http://127.0.0.1:7878/**

It's idempotent — if the hub is already up, re-running `/coapply:hub` just reuses it. To stop it, end
the background server process (or close the Claude Code session). The hub is optional; CoApply works
fully without it.

### Running the hub from source (maintainers)

If you're working on CoApply from a clone (not the installed plugin), you can start the server
directly. Point `--runs-dir` at **your own** profile's runs folder:

```bash
python3 hub/server.py --runs-dir <your-profile>/runs --host 127.0.0.1
```

It binds `127.0.0.1:7878` and prints the URL. It never binds a non-loopback host (that's enforced —
see `scripts/audit.sh` §16).
