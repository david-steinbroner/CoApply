# Security

CoApply is a Claude Code plugin that runs in your environment and reads your personal career information. Here's its security posture and how to report a problem.

## What it does and doesn't touch

- **Reads:** your profile folder (the one you configure) and the plugin's own engine files.
- **Writes:** only your runs folder (application output).
- **Never:** sends your data anywhere except your own Claude (no server, no telemetry, no third party), submits applications on your behalf, or logs into job sites.

These are enforced invariants, not just intentions — see `PRINCIPLES.md`.

## Supply-chain note

Installing any plugin grants its prompts agency in your Claude Code session. CoApply holds itself to what you'd want from anything you install: no network exfiltration, no `curl | sh`, no hidden instructions in command/skill descriptions, no attempts to suppress your own tooling or reviews. If you ever see a CoApply prompt doing something outside the bounds above, treat it as a bug and report it.

## Reporting a vulnerability

Please **don't** open a public issue for a security problem. Instead, report it privately via the repository's security advisory feature (GitHub → Security → Report a vulnerability) or to the maintainer directly. Include what you found, how to reproduce it, and the impact. You'll get an acknowledgment and a fix timeline.

## Your responsibility

Your profile and runs live on your machine. Keep your filled-in profile out of any public repository — the templates ship as `profile.example/`; your real profile should stay private (and is gitignored by default if kept inside the repo).
