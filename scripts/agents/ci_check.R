#!/usr/bin/env Rscript
message("Running CI agent: orchestrating agent checks")
status <- 0

run <- function(cmd) {
  message("Running: ", paste(cmd, collapse = " "))
  res <- system2(cmd[1], args = cmd[-1], stdout = "", stderr = "")
  if (res != 0) {
    message("Command failed with exit ", res)
  }
  res
}

# tidyverse checks
if (file.exists("scripts/agents/tidyverse_check.R")) {
  res <- run(c("Rscript", "scripts/agents/tidyverse_check.R"))
  status <- max(status, res)
}

# geospatial checks
if (file.exists("scripts/agents/geostat_check.R")) {
  res <- run(c("Rscript", "scripts/agents/geostat_check.R"))
  status <- max(status, res)
}

if (status != 0) {
  message("One or more agent checks failed. Exit status: ", status)
} else {
  message("All agent checks completed successfully.")
}

quit(status = status)
