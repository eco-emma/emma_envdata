# Download all assets from the static_data GitHub release into data/target_outputs/.
# Called at the top of _targets.R before tar_make() so that NC files written as
# side-effects by cue="never" targets (domain.nc, vegmap.nc, CHELSA, clouds_wilson)
# are present on disk even when those targets are restored from the targets cache.
# Skips files that already exist.  Errors are non-fatal: a message is printed and
# execution continues so that a missing release does not abort unrelated targets.
restore_static_data <- function(repo, out_dir = "data/target_outputs", verbose = TRUE) {
  tryCatch({
    # Use .gh_token() to bypass gh package format validation for ghs_ tokens.
    token      <- if (exists(".gh_token", mode = "function")) .gh_token() else Sys.getenv("GITHUB_TOKEN", unset = "")
    owner_repo <- strsplit(repo, "/")[[1]]
    rel <- gh::gh(
      "GET /repos/{owner}/{repo}/releases/tags/{tag}",
      owner  = owner_repo[1],
      repo   = owner_repo[2],
      tag    = "static_data",
      .token = token
    )
    for (asset in rel[["assets"]]) {
      dest <- file.path(out_dir, asset[["name"]])
      if (file.exists(dest)) next  # skip files already present
      r <- httr::GET(
        asset[["url"]],
        httr::add_headers(
          Authorization = paste("token", token),
          Accept        = "application/octet-stream"
        ),
        httr::write_disk(dest, overwrite = TRUE)
      )
      if (httr::http_error(r)) {
        message("Failed to download static file: ", asset[["name"]])
      } else if (verbose) {
        message("Downloaded static file: ", asset[["name"]],
                " (", file.size(dest), " bytes)")
      }
    }
  }, error = function(e) {
    message("Could not restore static data from release: ", conditionMessage(e))
  })
}

# Load all packages listed in DESCRIPTION file (quietly, suppressing startup messages)
load_description_packages <- function(description_file = "DESCRIPTION", quietly = TRUE, verbose = FALSE) {
  # Read DESCRIPTION file
  dcf <- read.dcf(description_file)
  
  # Extract Imports and Depends fields
  imports <- if ("Imports" %in% colnames(dcf)) dcf[1, "Imports"] else ""
  depends <- if ("Depends" %in% colnames(dcf)) dcf[1, "Depends"] else ""
  
  # Combine, split, and clean
  all_text <- paste(imports, depends, sep = ",")
  packages <- trimws(strsplit(all_text, ",")[[1]])
  
  # Remove version specifications (e.g., "ggplot2 (>= 3.0)" -> "ggplot2")
  packages <- sub("\\s*\\(.*\\).*", "", packages)
  
  # Remove empty strings and R itself
  packages <- packages[nzchar(packages) & packages != "R"]
  
  # Load each package with suppressed startup messages
  invisible(sapply(packages, function(pkg) {
    suppressPackageStartupMessages(
      library(pkg, character.only = TRUE, quietly = quietly)
    )
  }))
  
  if (verbose) message(paste("Loaded", length(packages), "packages from DESCRIPTION"))
  invisible(packages)
}
