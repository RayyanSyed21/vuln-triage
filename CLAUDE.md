# Project

CSDS 553 (MLOps) Case Study 1, WPI. Solo, graded, due Sep 14.
Product: vulnerability triage assistant. Paste a security alert, get a
severity call and a remediation step.

Architecture: ONE Gradio app with a radio toggle selecting between a
remote API backend (HF Inference Providers) and a locally executed
Transformers model. Deployed to a HF Space. Code on GitHub, synced to
the Space by a GitHub Action.

# How to work with me

I am learning this stack and must explain every line in a recorded
video and a written report.
- Explain the concept before writing code.
- Small diffs I can read, not large rewrites.
- When I hit an error, teach me to read it, don't just fix it.
- Work in steps. Stop and let me run things.
- Ask before installing packages or editing requirements.txt.

# Constraints

- Free HF tier, about $0.10/month of credits. Keep max_tokens tight.
  Never suggest paid plans or paid hardware.
- Local model must run on Spaces CPU Basic: 2 vCPU, 16 GB, no GPU.
  Sub-1B models or a distilled encoder classifier only.
- Never print, log, or commit HF_TOKEN. It lives in .env (gitignored),
  a Space secret, and a GitHub secret.
- Pin gradio in requirements.txt; keep sdk_version in README.md
  frontmatter matching exactly.

# Remaining deliverables

1b. Action syncing GitHub to the Space (10 pts)
2a. Local model backend (15 pts)
2b. Action running pytest (10 pts)
3.  Discord webhook when the action completes (10 pts)
4.  1-2 page report: performance, cost at 1000 users, risks (20 pts)
5.  2-3 minute VC pitch video (20 pts)
6.  Extra credit: automatic failover remote to local (10 pts)

Sections 4i and 4j of the report are marked Human only. Do not draft
them. Do not write the video script for me.
