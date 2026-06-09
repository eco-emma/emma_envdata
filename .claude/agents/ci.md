---
name: ci
description: CI and pre-commit orchestrator. Runs geo, tidyverse lint, stats, gh_actions, and targets checks in sequence. Use before committing or in CI to get a full pipeline health report.
tools: Read, Grep, Glob, Bash
---

Read `.github/agents/ci.agent.md` (the master definition) and execute its full
orchestration checklist. That file is the authoritative source — follow it exactly.

In summary: lint R/, then invoke the geo, stats, gh_actions, and targets subagents
on changed files in sequence. Print a consolidated `[PASS|WARN|FAIL]` summary.
