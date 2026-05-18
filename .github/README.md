# GitHub Copilot Customisation

This directory contains custom agents and always-on instructions for GitHub Copilot
Chat in VS Code.

---

## Always-on instructions

`instructions/r-style.instructions.md` — applied automatically to every `*.R` file.
Enforces tidyverse idioms, script-style (top-to-bottom, minimal abstraction), and
comment standards. No invocation needed.

---

## Custom agents (`agents/`)

Agents appear in the Copilot Chat agent picker (the mode selector next to the chat
input). Select one from the dropdown, or type its name after `@` in the chat input.

### How to invoke

```
@<agent-name> <your request>
```

Example:
```
@stats review R/process_burn_dates.R for assumption violations
@commenter document R/get_clouds_wilson.R
@coder_alpha implement a function that downloads MODIS tiles for a given month
```

To run all three competing coders on the same problem, send the same prompt to each:
```
@coder_alpha implement X
@coder_beta implement X
@coder_gamma implement X
```
Then pick the best solution or synthesise across them.

---

## Agent reference

### Review agents — read-only, raise issues for coders to fix

| Agent | Invoke when you want to… |
|---|---|
| `@stats` | Check statistical assumptions, sample sizes, data leakage, uncertainty |
| `@geo_accuracy` | Check CRS choices, resampling methods, spatial join correctness |
| `@science` | Get a peer-reviewer-style critique of analytical design and methods |
| `@geostat` | Quick metadata QA: CRS consistency, resolution mismatches, missing files |

### Coding agents — produce working R code

| Agent | Philosophy |
|---|---|
| `@coder_alpha` | Correctness-first: readable, conventional, explicit sanity checks |
| `@coder_beta` | Performance-first: memory-efficient, chunk-based, parallelism-aware |
| `@coder_gamma` | Minimalist: fewest lines, no abstraction, inline everything |

### Documentation agent

| Agent | Invoke when you want to… |
|---|---|
| `@commenter` | Review or add scientific comments, section headers, and unit annotations |

### Orchestrator

| Agent | Invoke when you want to… |
|---|---|
| `@ci` | Run a full pre-commit sweep: lint + geostat + stats + geo_accuracy |

---

## Typical workflows

**Before committing:**
```
@ci
```

**Writing new processing code:**
1. Draft with `@coder_alpha`, `@coder_beta`, and `@coder_gamma` in parallel.
2. Pick or synthesise the best solution.
3. Run `@geo_accuracy` and `@stats` on the result.
4. Run `@commenter` to fill in documentation.

**Reviewing a script for scientific soundness:**
```
@science review R/process_dynamic_data.R
@stats review R/process_dynamic_data.R
@geo_accuracy review R/process_dynamic_data.R
```
