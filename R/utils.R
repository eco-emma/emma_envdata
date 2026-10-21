# CLI entry scripts under R/ must never be sourced by other R files or by
# tar_source(). Each publish_*.R bootstraps by sourcing sibling helpers; if any
# CLI entry is left in that list, they cross-source each other forever and R
# dies with "node stack overflow" inside library() (seen on CCR/Apptainer).
pipeline_cli_entry_basenames <- c(
  "audit_vi_parquet_dates.R",
  "backfill_stac_release.R",
  "ci_appeears_update.R",
  "publish_inat_data.R",
  "publish_park_static.R",
  "publish_vi_viirs_parquet.R",
  "publish_weather.R"
)

# Return paths of pipeline helper scripts (excludes CLI entry points above).
list_pipeline_r_files <- function(dir = "R") {
  r_files <- list.files(dir, pattern = "^[^.].*\\.R$", full.names = TRUE)
  r_files[!basename(r_files) %in% pipeline_cli_entry_basenames]
}

# Source all pipeline helpers once. Used by R/publish_*.R CLI entries.
source_pipeline_r <- function(dir = "R") {
  for (f in list_pipeline_r_files(dir)) {
    source(f, local = FALSE)
  }
  invisible(TRUE)
}

# Download all assets from the static_data GitHub release into data/target_outputs/.
# Called at the top of _targets.R before tar_make() so that NC files written as
# side-effects by cue="never" targets (domain.nc, vegmap.nc, CHELSA, clouds_wilson)
# are present on disk even when those targets are restored from the targets cache.
# Skips files that already exist.  Errors are non-fatal: a message is printed and
# execution continues so that a missing release does not abort unrelated targets.
restore_static_data <- function(repo, out_dir = "data/target_outputs", skip_patterns = NULL, verbose = TRUE) {
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
      if (!is.null(skip_patterns) && grepl(skip_patterns, asset[["name"]])) {
        if (verbose) message("Skipping static file (cue=never target): ", asset[["name"]])
        next
      }
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

# Generate the complete MODIS/VIIRS 16-day composite schedule between two dates.
# Anchor date 2000-02-18 is the first MODIS Terra 16-day composite period.
# Returns a tibble with one row per composite; composite_date = period start,
# composite_end = period end (start + 15 days).
generate_composite_sequence <- function(start_date, end_date) {
  anchor     <- as.Date("2000-02-18")
  start_date <- as.Date(start_date)
  end_date   <- as.Date(end_date)
  n_steps    <- floor(as.numeric(end_date - anchor) / 16)
  all_dates  <- anchor + (0:n_steps * 16L)
  dates      <- all_dates[all_dates >= start_date & all_dates <= end_date]
  tibble::tibble(
    composite_date = dates,
    composite_end  = dates + 15L
  )
}

# Keep only composite windows missing one or more expected COG assets on a
# GitHub release tag. This avoids reprocessing historical composites that are
# already complete in release storage.
filter_pending_composites <- function(composites, gh_release_tag, prefixes,
                                      repo = Sys.getenv(
                                        "TAR_GH_RELEASE_REPO",
                                        unset = "eco-emma/emma_envdata"
                                      ),
                                      verbose = TRUE) {
  if (!nrow(composites)) return(composites)

  yyyymmdd <- format(as.Date(composites$composite_date), "%Y%m%d")
  missing_release_assets <- purrr::map_lgl(yyyymmdd, function(date_key) {
    expected_assets <- paste0(prefixes, date_key, ".tif")
    !all(purrr::map_lgl(expected_assets, function(asset_name) {
      gh_release_has_asset(repo, gh_release_tag, asset_name, verbose = FALSE)
    }))
  })

  pending <- composites[missing_release_assets, , drop = FALSE]

  if (verbose) {
    message(
      "Composite windows for release '", gh_release_tag, "': ",
      nrow(composites) - nrow(pending), " already complete, ",
      nrow(pending), " pending"
    )
  }

  pending
}

# Keep only calendar months whose burn COG is missing from a GitHub release.
# Mirrors filter_pending_composites() for the monthly burn pipelines.
filter_pending_months <- function(months, gh_release_tag, prefix,
                                  repo = Sys.getenv(
                                    "TAR_GH_RELEASE_REPO",
                                    unset = "eco-emma/emma_envdata"
                                  ),
                                  verbose = TRUE) {
  if (!nrow(months)) return(months)

  yyyymm <- format(as.Date(months$month_start), "%Y%m")
  missing_release_assets <- !vapply(
    yyyymm,
    function(ym) {
      gh_release_has_asset(
        repo, gh_release_tag, paste0(prefix, ym, ".tif"), verbose = FALSE
      )
    },
    logical(1)
  )

  pending <- months[missing_release_assets, , drop = FALSE]

  if (verbose) {
    message(
      "Months for release '", gh_release_tag, "': ",
      nrow(months) - nrow(pending), " already complete, ",
      nrow(pending), " pending"
    )
  }

  # GitHub Actions cannot finish a multi-year AppEEARS backfill in one job.
  # Keep the newest N missing months so weekly runs make forward progress;
  # full history belongs on the CCR prime. Override with CI_APPEEARS_MAX_MONTHS
  # (empty / 0 = no cap).
  if (nrow(pending) && nzchar(Sys.getenv("GITHUB_ACTIONS"))) {
    max_n <- Sys.getenv("CI_APPEEARS_MAX_MONTHS", unset = "24")
    if (nzchar(max_n) && max_n != "0") {
      max_n <- suppressWarnings(as.integer(max_n))
      if (!is.na(max_n) && max_n > 0L && nrow(pending) > max_n) {
        ord <- order(pending$month_start, decreasing = TRUE)
        keep <- sort(ord[seq_len(max_n)])
        if (verbose) {
          message(
            "[filter_pending_months] GITHUB_ACTIONS cap: newest ", max_n,
            " of ", nrow(pending), " pending months for '", gh_release_tag, "'"
          )
        }
        pending <- pending[keep, , drop = FALSE]
      }
    }
  }

  pending
}

# Generate a sequence of calendar months between two dates.
# Returns a tibble with one row per month; month_start = first day of month,
# month_end = last day of month.
generate_monthly_sequence <- function(start_date, end_date) {
  start_date <- as.Date(start_date)
  end_date   <- as.Date(end_date)
  month_starts <- seq(
    from = as.Date(format(start_date, "%Y-%m-01")),
    to   = as.Date(format(end_date,   "%Y-%m-01")),
    by   = "month"
  )
  month_ends <- as.Date(format(month_starts + 31L, "%Y-%m-01")) - 1L
  tibble::tibble(
    month_start = month_starts,
    month_end   = month_ends
  )
}
