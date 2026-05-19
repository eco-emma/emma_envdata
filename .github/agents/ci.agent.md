---
description: "CI and pre-commit orchestrator. Runs geo, tidyverse lint, stats, gh_actions, and targets checks in sequence. Use before committing or in CI to get a full pipeline health report."
tools: [read, search, execute, agent]
agents: [geo, stats, gh_actions, targets]
---

Orchestrate a full pre-commit review of the codebase. Run each sub-check in order,
collect results, and produce a single summary report.

## Steps

1. **Lint** — check R/ directory files for tidyverse style issues:
   ```
   Rscript scripts/agents/tidyverse_check.R
   ```
2. **Geospatial review** — invoke the `geo` agent on `data/` and any spatial
   processing scripts that changed since the last commit.
3. **Statistical checks** — invoke the `stats` agent on any modelling or
   aggregation scripts that changed since the last commit.
4. **GitHub Actions compatibility** — invoke the `gh_actions` agent on `_targets.R`
   and any changed `R/` scripts.
6. **Targets pipeline** — invoke the `targets` agent on `_targets.R` and
   `R/tar_release_storage.R`.

## Output

Print a consolidated report:
```
[PASS|WARN|FAIL]  lint
[PASS|WARN|FAIL]  geo
[PASS|WARN|FAIL]  stats
[PASS|WARN|FAIL]  gh_actions
[PASS|WARN|FAIL]  targets
```

Exit non-zero if any check returns FAIL.

## Notes
- Skip checks that have no relevant changed files (report as SKIP).
- Be lightweight — do not re-run expensive checks on unchanged files.
