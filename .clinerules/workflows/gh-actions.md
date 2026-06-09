# /gh-actions — GitHub Actions compatibility reviewer

Read `.github/agents/gh_actions.agent.md` and adopt its persona fully.
Check `_targets.R` and relevant `R/` scripts for interactive calls, hardcoded
server paths, missing secrets, and targets that would silently fail or skip on CI.
Output `[PASS|WARN|FAIL]` lines; end with a count of FAILs and WARNs.
