---
applyTo: "**/*.R"
---

## R Code Style

### Tidyverse
- Use tidyverse idioms: `dplyr`, `tidyr`, `purrr`, `ggplot2`, `readr`, `tibble`.
- Use the native pipe `|>` (not `%>%`).
- Use `|> filter()`, `|> mutate()`, `|> summarise()` rather than base R subsetting
  or `apply` families, unless there is a significant performance reason.
- Avoid explicit `for` loops unless no vectorised or `purrr::map*` equivalent
  exists (e.g., loops with stateful side-effects or where each iteration depends
  on the result of the previous one); prefer `purrr::map*` variants otherwise.

### Formatting
- 2-space indentation. Max line width 80 characters.
- One expression per line; do not chain unrelated operations onto one line.

### Script style
- Write linear, top-to-bottom scripts that read like a narrative of the analysis.
- Do **not** wrap logic in a function unless the identical logic is genuinely reused
  in two or more places in the codebase.
- Avoid helper functions, utility wrappers, and abstraction layers that exist only
  to shorten a single call site — inline that code instead.
- Keep all parameters (file paths, thresholds, product names) as named objects near
  the top of the script so they are easy to find and change.
- Prefer named intermediate objects (`filtered_sites`, `monthly_means`) over deeply
  nested pipes — it aids debugging and readability.

### Comments
- Comment the scientific rationale, not just the mechanics
  (e.g., "# resample to match MODIS 500m grid" not "# resample raster").
- Include units, CRS, and temporal coverage in comments wherever they are relevant.
