#!/usr/bin/env python3
"""check-tiering.py — verify a run's per-agent models against the tier map.

CoApply's Model map (master-apply.md Step 3) decides which model each agent runs on:
tier × agent-class → model. Since 0.11.3 the orchestrator records the *actual* model it
passed into each artifact's `model` field in `_run.json`. This script is the independent
check: it reads a finished `_run.json` and confirms every dispatched agent's recorded
model matches what the tier map says it should be. It's the tiering ground-truth read —
observability for any run, and the objective pass/fail for the tiering dogfood (roadmap #3).

The EXPECTED map below mirrors master-apply.md Step 3. audit.sh §14 guards the source
copy; if you change the tiers there, change them here (and vice-versa). A verifier must
encode the expected values independently — that's the point.

Usage:
    check-tiering.py <run-folder>        # one run (folder holding a _run.json)
    check-tiering.py <runs-dir>          # newest run under a runs/ dir
    check-tiering.py <runs-dir> --all    # every run under a runs/ dir

Exit 0 = every dispatched agent matched its expected model. Exit 1 = a mismatch, a missing
model on a done/failed agent, or an unknown tier/class. Exit 2 = bad arguments / no run found.
"""
import json
import os
import sys

# tier -> class -> expected model alias. Mirrors master-apply.md Step 3 (audit §14 guards it).
EXPECTED = {
    "lite":     {"mechanical": "haiku", "reasoning": "haiku",  "voice": "sonnet"},
    "standard": {"mechanical": "haiku", "reasoning": "sonnet", "voice": "sonnet"},
    "full":     {"mechanical": "haiku", "reasoning": "sonnet", "voice": "opus"},
}
# Classes that don't run an LLM agent — their model legitimately stays null.
NON_AGENT_CLASSES = {"tool"}
# Statuses where a model is *expected* to have been recorded (the agent was dispatched).
DISPATCHED = {"done", "failed"}

GREEN, RED, DIM, YEL, RST = "\033[32m", "\033[31m", "\033[2m", "\033[33m", "\033[0m"
if not sys.stdout.isatty():
    GREEN = RED = DIM = YEL = RST = ""


def find_run_json(path):
    return os.path.join(path, "_run.json") if os.path.isfile(os.path.join(path, "_run.json")) else None


def list_runs(runs_dir):
    """Direct child dirs of runs_dir that hold a _run.json, newest first by _run.json mtime."""
    out = []
    try:
        entries = os.listdir(runs_dir)
    except OSError:
        return out
    for name in entries:
        d = os.path.join(runs_dir, name)
        rj = find_run_json(d)
        if rj:
            out.append((os.path.getmtime(rj), d))
    out.sort(reverse=True)
    return [d for _, d in out]


def check_run(run_dir):
    """Return (ok, tier, rows) where rows = [(name, cls, expected, actual, verdict)]."""
    rj = find_run_json(run_dir)
    if not rj:
        return False, None, [("(no _run.json)", "", "", "", "MISSING-FILE")]
    with open(rj, encoding="utf-8") as fh:
        raw = json.load(fh)

    tier = raw.get("tier")
    tier_map = EXPECTED.get(tier)
    rows, ok = [], True

    for a in raw.get("artifacts") or []:
        if not isinstance(a, dict):
            continue
        name = a.get("name", "?")
        cls = a.get("class")
        model = a.get("model")
        status = a.get("status")

        # Not dispatched (pending/skipped/conditional) or a non-agent tool row: nothing to verify.
        if cls in NON_AGENT_CLASSES:
            rows.append((name, cls or "-", "-", model or "null", "SKIP"))
            continue
        if status not in DISPATCHED:
            rows.append((name, cls or "-", "-", model or "null", "SKIP(%s)" % (status or "?")))
            continue

        if tier_map is None:
            rows.append((name, cls or "-", "?", model or "null", "UNKNOWN-TIER"))
            ok = False
            continue
        if cls not in tier_map:
            rows.append((name, cls or "-", "?", model or "null", "UNKNOWN-CLASS"))
            ok = False
            continue

        expected = tier_map[cls]
        if model is None:
            rows.append((name, cls, expected, "null", "NOT-RECORDED"))
            ok = False
        elif model == "inherited":
            rows.append((name, cls, expected, model, "INHERITED"))
            ok = False
        elif model == expected:
            rows.append((name, cls, expected, model, "OK"))
        else:
            rows.append((name, cls, expected, model, "MISMATCH"))
            ok = False

    return ok, tier, rows


def print_run(run_dir, ok, tier, rows):
    print("\n%s%s%s   tier=%s" % (DIM, os.path.basename(run_dir.rstrip("/")), RST, tier or "?"))
    print("  %-22s %-11s %-9s %-9s %s" % ("agent", "class", "expected", "actual", "verdict"))
    for name, cls, expected, actual, verdict in rows:
        if verdict == "OK":
            col = GREEN
        elif verdict.startswith("SKIP"):
            col = DIM
        else:
            col = RED
        print("  %-22s %-11s %-9s %-9s %s%s%s" % (name, cls, expected, actual, col, verdict, RST))
    tag = (GREEN + "PASS" + RST) if ok else (RED + "FAIL" + RST)
    print("  → %s" % tag)


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("-")]
    do_all = "--all" in argv[1:]
    if len(args) != 1:
        print(__doc__)
        return 2
    target = args[0]
    if not os.path.isdir(target):
        print("not a directory: %s" % target)
        return 2

    if find_run_json(target):
        runs = [target]
    else:
        runs = list_runs(target)
        if not runs:
            print("no runs (no child folder holds a _run.json) under: %s" % target)
            return 2
        if not do_all:
            runs = runs[:1]

    all_ok = True
    for run_dir in runs:
        ok, tier, rows = check_run(run_dir)
        print_run(run_dir, ok, tier, rows)
        all_ok = all_ok and ok

    print("")
    if all_ok:
        print("%sAll dispatched agents matched the tier map.%s" % (GREEN, RST))
        return 0
    print("%sTiering ground-truth check FAILED — see rows above.%s" % (RED, RST))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
