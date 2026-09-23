# CoApply

Put more care into the jobs you actually want.

CoApply helps you decide whether a role is worth pursuing, then prepare an application based on your own experience. Give it a job posting and your background. It researches the role, explains the fit, and waits for your decision before drafting.

You review the work and send it yourself. CoApply does not submit applications for you.

## What it helps with

- Understanding a role and how it fits your experience.
- Drafting a cover letter and tailoring your resume.
- Preparing outreach and interview notes.
- Keeping application materials together so you can return to them later.

The amount of research and writing depends on the budget tier you choose. You can change it with `/coapply:tier`.

## Get started

CoApply runs in [Claude Code](https://claude.com/claude-code). You'll need your own Claude Code access; its usage costs and limits still apply.

Inside Claude Code, run:

```text
/plugin marketplace add david-steinbroner/CoApply
/plugin install coapply@coapply-marketplace
```

Choose user scope if you want it available across projects. Create a separate, empty folder for your profile and application files, then select that folder when prompted.

Run `/coapply:setup` to fill in your background and choose a budget. Start with your identity, work experience, and a resume. Then paste a job link or description after:

```text
/coapply:start
```

CoApply will show you its assessment and ask whether to continue. Check the facts and wording in every draft before using it.

## Come back when you need it

- `/coapply:list` shows your recent applications.
- `/coapply:resume` picks up an interrupted application.
- `/coapply:add` saves preferences and examples of your writing.
- `/coapply:discover` helps find roles on public job boards.
- `/coapply:hub` opens an optional local view of your applications.
- `/coapply:help` explains the available commands.

See [the command guide](COMMANDS.md) for the full reference.

To check for updates, run `/plugin marketplace update coapply-marketplace`, then restart Claude Code. Your profile and application files live separately from the plugin.

## Privacy and limits

Your files are saved on your computer and processed through your Claude Code session. Optional integrations can send information to the services you connect. Automatic job discovery also sends role and location search terms to a search provider.

Discovery covers selected public job boards and won't find every opening. Drafts still need your judgment, and no application tool can promise an interview.

Read [the project principles](PRINCIPLES.md) and [security guidance](SECURITY.md) for more detail.

## About

Built by David Steinbroner with Claude Code, with human decisions and review built into the workflow.

Contributions are covered in [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MIT](LICENSE).
