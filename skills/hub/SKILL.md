---
name: hub
description: Open the hub — CoApply's local visual command center for your whole funnel (surfaced roles → the gate → runs), served on 127.0.0.1 from your own machine. Triggers on "open the hub", "show my pipeline", "open my dashboard", "show the funnel", "where am I in my applications".
argument-hint: ""
---

# CoApply — Hub launcher

The hub is CoApply's **returnable home**: a single local page that renders the whole funnel in one
place — **discover (surfaced roles) → the gate → runs** — joined by the `fp`/`discoveryFp`
fingerprint. It is a **thin lens over the files you already have**: it reads the curated discover
ledger (`surfaced.json`) and your run folder, and writes exactly one thing — a queue (a shopping
list the human gate picks up). It **never submits, never runs an agent, never leaves your machine**
(it binds `127.0.0.1` only — loopback, not the LAN).

Your job in this skill is only to **launch the local server and point the user at the URL.** All the
product surface lives in the page; you do not render the funnel here.

## Step 0 — Resolve paths (do this first)

Run this **bare** — don't capture it in `VAR="$(…)"` (that can't be allowlisted and would prompt
every run). It resolves the saved profile folder and probes readiness:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/profile-status.sh"
```

It prints `PROFILE_DIR=… RUNS_DIR=… WRITABLE=… IDENTITY=… SKILLS=… RESUME=… PLACEHOLDERS=…`. Use
the printed `PROFILE_DIR` and `RUNS_DIR` as absolute paths from here on, and hand the **real
absolute `RUNS_DIR`** to the server (subprocesses can't resolve `${…}` — never pass a literal).

**First-run routing — warm route, never a raw abort.** Map the flags to one `STATE`:
- `PROFILE_DIR` empty → **`not-set`**: they haven't set a Profile folder yet. Walk them in:
  > The hub needs a profile folder first. **1.** Make a new empty folder, e.g. `~/coapply-profile`.
  > **2.** Run `/plugin`, open **CoApply**, set **Profile folder** to it. **3.** Run
  > **`/coapply:setup`**. Then re-run `/coapply:hub`.

  Then stop — don't start a server pointing at nothing.
- `WRITABLE=no` → **`bad-path`**: their saved folder isn't there/writable. Re-point it via
  `/plugin` → CoApply → **Profile folder**, then re-run `/coapply:hub`. Then stop.
- otherwise → **`ok`**, continue. (The hub does **not** require a filled-in profile — with no
  `surfaced.json` or runs yet it simply renders its empty states, which name the chat commands to
  run next. That is the intended onboarding surface, so don't gate on `IDENTITY`/`RESUME` here.)

## Step 1 — Launch the server (start-or-reuse) and open the page

Make sure the runs folder exists, then start the local server in the **background** so it keeps
serving after this turn. Pass the resolved absolute `RUNS_DIR` (substitute the real path you read in
Step 0 — never a `${…}` literal):

```bash
mkdir -p "<ABS RUNS_DIR>"
python3 "${CLAUDE_PLUGIN_ROOT}/hub/server.py" --runs-dir "<ABS RUNS_DIR>" --host 127.0.0.1
```

Run that **in the background** (it blocks while serving). It binds `127.0.0.1:7878` and prints the
URL to stdout. **It is idempotent:** if the hub is already running, the new process can't bind the
port and exits 1 — that is not an error, it means *reuse the one already up*. Either way the URL is:

> **http://127.0.0.1:7878/**

Open it for the user and also print it as a clickable line (some terminals won't auto-open):
- macOS: `open "http://127.0.0.1:7878/"`
- Linux: `xdg-open "http://127.0.0.1:7878/"`

If `python3` isn't found, tell them the hub needs Python 3 (already a CoApply dependency) and stop.

## Step 2 — Orient the user (one short message), then stop

Tell them, briefly:
- The hub is **open at http://127.0.0.1:7878/** and is **local-only** — it runs on their machine,
  binds loopback, and sends nothing anywhere.
- What they'll see: **surfaced roles** up top (run `/coapply:discover` to fill it), a **staging gate**
  in the middle, and their **runs** below. Selecting roles and "Add to apply queue" stages them — it
  **sends nothing**; each still stops at the human gate. To act on the queue, they run **`/coapply:start`**
  with no argument back here in chat, and you'll hand them one `/coapply:start <url>` per staged job.
- To stop the server later: end the background process (e.g. close the session, or `kill` the
  `hub/server.py` process). Re-running `/coapply:hub` just reuses it.

Do **not** run any agent, fetch anything, or write any file in this skill beyond launching the
server. The hub is the face; the engine stays in the other skills.
