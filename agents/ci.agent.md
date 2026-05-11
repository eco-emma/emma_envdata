Name: ci
Role: Orchestrate agent checks for continuous integration and developer pre-commit checks.

Responsibilities:
- Run `tidyverse` and `geostat` agent checks and surface their results.
- Exit non-zero if any required checks fail.
- Be lightweight so CI runs quickly.

How to run:
- `Rscript scripts/agents/ci_check.R`

Notes:
- CI workflow is defined in `.github/workflows/agents-check.yml`.
