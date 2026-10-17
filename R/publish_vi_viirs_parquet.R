#!/usr/bin/env Rscript
# =============================================================================
# Publish existing local VIIRS VI parquets → eco-emma/emma_envdata@vi_viirs_parquet
#
# Creates the release tag on first upload if missing (same as upload_vi_modis).
# Does NOT rebuild from COGs — uploads files already on disk under
# data/target_outputs/viirs_vi/vi_viirs_YYYYMMDD.parquet.
#
# Prefer CCR (full historical store). GHA cannot invent historical parquets from
# release COGs without re-running the grid→parquet step for every composite.
#
# Usage (inside Apptainer from `bash R/ccr_startup.sh shell`):
#   Rscript R/publish_vi_viirs_parquet.R
#   Rscript R/publish_vi_viirs_parquet.R --dry-run
#
# Or after this branch is on main, via targets:
#   R -e 'targets::tar_make(upload_vi_viirs)'
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
dry_run <- "--dry-run" %in% args

source("R/utils.R", local = FALSE)
source_pipeline_r()

if (file.exists("DESCRIPTION") && exists("load_description_packages")) {
  tryCatch(load_description_packages(verbose = FALSE), error = function(e) {
    message("Package preload skipped: ", conditionMessage(e))
  })
}

repo <- Sys.getenv("TAR_GH_RELEASE_REPO", unset = "eco-emma/emma_envdata")
tag <- "vi_viirs_parquet"
out_dir <- "data/target_outputs/viirs_vi"

files <- list.files(
  out_dir,
  pattern = "^vi_viirs_[0-9]{8}\\.parquet$",
  full.names = TRUE
)
files <- sort(files)

message(
  "publish_vi_viirs_parquet: repo=", repo,
  " tag=", tag,
  " n_files=", length(files),
  " dry_run=", dry_run
)

if (!length(files)) {
  stop(
    "No vi_viirs_YYYYMMDD.parquet files under ", out_dir, ". ",
    "Build them first (tar_make on vi_viirs_parquet) or run on CCR where ",
    "the historical store lives.",
    call. = FALSE
  )
}

message(
  "First/last: ", basename(files[[1]]), " … ", basename(files[[length(files)]])
)

if (dry_run) {
  message("Dry run — not uploading. Sample:\n",
          paste(" -", basename(utils::head(files, 10L)), collapse = "\n"))
  quit(status = 0)
}

uploaded <- upload_to_github_release(
  files = files,
  repo = repo,
  release_tag = tag,
  release_name = "Dynamic VIIRS Vegetation Index",
  verbose = TRUE
)

message(
  "Done. Uploaded/confirmed ", length(uploaded),
  " asset path(s) on tag ", tag, "."
)
