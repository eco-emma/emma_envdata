Name: tidyverse
Role: Enforce and optionally apply tidyverse-style formatting and lint rules for R code.

Responsibilities:
- Report `lintr` lints for `R/` and top-level R scripts.
- Optionally apply `styler` formatting when run with `--fix`.
- Prefer `tidyverse_style()` settings: 2-space indentation, max width 80, use pipes consistently.

How to run:
- Lint only: `Rscript scripts/agents/tidyverse_check.R`
- Apply formatting: `Rscript scripts/agents/tidyverse_check.R --fix`

Notes:
- The agent should not rewrite files unless explicitly invoked with `--fix`.
- Complaints should be actionable and point to file and line numbers.
