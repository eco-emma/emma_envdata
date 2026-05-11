Agents in this repository
-------------------------

This folder contains lightweight "agents" to help maintain code quality and project workflow.

Available agents
- tidyverse — checks code style with `lintr` and optionally formats with `styler`.
- geostat — performs basic spatial data QA (CRS consistency, missing-value checks) using `terra`/`sf`.
- ci — orchestrates agent checks (runs the other agent scripts); used by CI.

Run locally
- Lint only: `Rscript scripts/agents/tidyverse_check.R`
- Format (apply tidyverse style): `Rscript scripts/agents/tidyverse_check.R --fix`
- Geospatial checks: `Rscript scripts/agents/geostat_check.R`
- Run all checks: `Rscript scripts/agents/ci_check.R`

See the individual `.agent.md` files for agent responsibilities and rules.
