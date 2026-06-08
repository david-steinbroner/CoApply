# Your profile (this is where you make CoApply *yours*)

CoApply generates applications from **your** material. These files are that material — your experience, your voice, how you want to be positioned. The quality of every run depends on what's here, so it's worth doing well once.

## Setup

1. **Copy this folder** to your profile location (default: a `profile/` folder CoApply reads from — see the main README for where to point it).
2. **Set it up from your resume.** Run `/coapply:setup` and paste your resume (or give the file path) — CoApply drafts these files from it and shows you everything before saving. No resume? It'll ask about your experience instead. Prefer to do it by hand? Fill in each file below — replace every `<placeholder>` and the italic _instructions_, and delete guidance you don't need.
3. **Run `/coapply:start <a job posting>`.** The more complete your profile, the better the output.

> Tip: you don't have to fill everything in at once. Setting up from your resume gets the essentials in fast; come back and deepen it anytime — **the more you put in, the better CoApply gets.**

## The files

| File | What it's for |
|---|---|
| `skills-experience.md` | Your master reference — every role, achievement, metric, and story CoApply can draw from. The single most important file. |
| `voice-profile.md` | How you write, so cover letters and outreach sound like *you*, not generic AI. |
| `positioning-modes.md` | Pre-defined ways to frame yourself for different kinds of role (e.g. a teacher's "Classroom Lead" vs "Curriculum Designer" framing). CoApply picks the right mode per job. |
| `portfolio-links.md` | Case studies, project links, hosted cover letters — anything you'd link a hiring manager to. |
| `resumes/` | One or more resume variants in markdown. CoApply recommends which to send and which bullets to swap per job. |

## Privacy

These files stay on **your** machine. CoApply reads them locally and writes output locally. Nothing is uploaded anywhere except to your own Claude. Keep your filled-in profile out of any public repo (the template ships as `profile.example/`; your real one should be gitignored).
