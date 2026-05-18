---
description: "CI and pre-commit orchestrator. Runs geostat, tidyverse lint, stats, and geo_accuracy checks in sequence. Use before committing or in CI to get a full pipeline health report."
tools: [read, search, execute, agent]
agents: [geostat, stats, geo_accuracy]
---

Orchestrate a full pre-commit review of the codebase. Run each sub-check in order,
collect results, and produce a single summary report.

## Steps

1. **Lint** — check R/ directory files for tidyverse style issues:
   ```
   Rscript scripts/agents/tidyverse_check.R
   ```
2. **Geospatial metadata QA** — invoke the `geostat` agent on `data/` and `R/`.
3. **Statistical checks** — invoke the `stats` agent on any modelling or
   aggregation scripts that changed since the last commit.
4. **Geospatial accuracy** — invoke the `geo_accuracy` agent on any spatial
   processing scripts that changed since the last commit.

## Output

Print a consolidated report:
```
[PASS|WARN|FAIL]  lint
[PASS|WARN|FAIL]  geostat
[PASS|WARN|FAIL]  stats
[PASS|WARN|FAIL]  geo_accuracy
```

Exit non-zero if any check returns FAIL.

## Notes
- Skip checks that have no relevant changed files (report as SKIP).
- Be lightweight — do not re-run expensive checks on unchanged files.
