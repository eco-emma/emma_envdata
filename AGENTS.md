# Agent instructions — emma_envdata

## R style (required)

All R code and agent-authored R changes must follow the
[tidyverse style guide](https://style.tidyverse.org/).

- Format with [`styler`](https://styler.r-lib.org/) (`styler::style_file()` /
  `styler::style_dir()`) before committing.
- Prefer tidyverse idioms (`dplyr`, `tidyr`, `purrr`, `ggplot2`, `readr`,
  `tibble`) and the native pipe `|>`.
- Project-specific R guidance (script shape, comments, geospatial notes) lives
  in `.github/instructions/r-style.instructions.md` and `.clinerules/r-style.md`.
  Those files defer to the tidyverse guide for formatting.

## Agent personas

Canonical personas: `.github/agents/*.agent.md` (shared with Copilot and Cline).
See `CLAUDE.md` and `.clinerules/agents.md` for invocation maps.
