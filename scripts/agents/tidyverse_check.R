#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
fix <- "--fix" %in% args

repo_root <- normalizePath(".")
message("Running tidyverse agent (linting)")
if (!requireNamespace("lintr", quietly = TRUE)) {
  message("Package 'lintr' is not installed. Install it to run lints: install.packages('lintr')")
  quit(status = 0)
}
if (fix && !requireNamespace("styler", quietly = TRUE)) {
  message("Package 'styler' is not installed. Install it to apply formatting: install.packages('styler')")
  quit(status = 0)
}

lint_paths <- c("R")
lint_files <- unlist(lapply(lint_paths, function(p) if (dir.exists(p)) lintr::list_files(p) else character(0)))
if (length(lint_files) == 0) {
  message("No R files found under R/ to lint.")
} else {
  lints <- lintr::lint_dir("R")
  if (length(lints) > 0) {
    print(lints)
  } else {
    message("No lints found.")
  }
}

if (fix) {
  message("Applying `styler::style_dir('R')`")
  tryCatch({
    styler::style_dir("R", scope = "tokens")
    message("Styling applied to R/ files.")
  }, error = function(e) {
    message("styler failed: ", e$message)
    quit(status = 2)
  })
}

message("tidyverse agent finished")
