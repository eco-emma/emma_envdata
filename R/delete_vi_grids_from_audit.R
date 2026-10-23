#!/usr/bin/env Rscript
# =============================================================================
# Delete bad VI sensor grid COGs (local + GitHub Releases) so
# filter_pending_composites() re-queues AppEEARS for those dates.
#
# Preferred when parquet remotes were already cleaned (survivor CSV / few
# locals): --from-release-orphans (grid COGs whose YYYYMMDD is missing from
# the matching parquet release).
#
# Other sources:
#   --from-csv PATH          flagged parquet audit rows → sensor COGs
#   --from-local-doy         local COGs failing DOY guard
#   --dates-file PATH        bare YYYYMMDD / basenames
#
# Usage (inside Apptainer from `bash R/ccr_startup.sh shell`):
#   Rscript R/delete_vi_grids_from_audit.R --from-release-orphans --dry-run
#   Rscript R/delete_vi_grids_from_audit.R --from-release-orphans --delete-remote
#   Rscript R/delete_vi_grids_from_audit.R --from-csv … --dry-run
#   Rscript R/delete_vi_grids_from_audit.R --from-local-doy --dry-run
#
# See docs/VI_PARQUET_REALIGN.md § "Delete bad grid COGs".
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)

has_flag <- function(flag) flag %in% args
flag_value <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) {
    return(default)
  }
  args[[i + 1L]]
}

from_csv <- flag_value("--from-csv", NULL)
from_local_doy <- has_flag("--from-local-doy")
from_release_orphans <- has_flag("--from-release-orphans")
dates_file <- flag_value("--dates-file", NULL)
out_csv <- flag_value(
  "--out",
  "data/target_outputs/vi_grid_cog_delete_plan.csv"
)
delete_local <- has_flag("--delete-local")
delete_remote <- has_flag("--delete-remote")
dry_run <- has_flag("--dry-run") || (!delete_local && !delete_remote)
repo <- Sys.getenv("TAR_GH_RELEASE_REPO", unset = "eco-emma/emma_envdata")

source("R/utils.R", local = FALSE)
source_pipeline_r()

if (file.exists("DESCRIPTION") && exists("load_description_packages")) {
  tryCatch(load_description_packages(verbose = FALSE), error = function(e) {
    message("Package preload skipped: ", conditionMessage(e))
  })
}

message(
  "delete_vi_grids_from_audit: dry_run=", dry_run,
  " delete_remote=", delete_remote,
  " delete_local=", delete_local,
  " from_release_orphans=", from_release_orphans,
  " repo=", repo
)

assets <- NULL
source_label <- NULL
explicit_source <- from_release_orphans ||
  (!is.null(from_csv) && nzchar(from_csv)) ||
  from_local_doy ||
  (!is.null(dates_file) && nzchar(dates_file))

# Default with no flags: prefer release orphans (post-parquet-cleanup path).
# Mention any leftover flagged CSVs for optional --from-csv use.
if (!explicit_source) {
  message(
    "No source flag — using --from-release-orphans ",
    "(grid COGs whose date is missing from parquet releases)."
  )
  message(
    "Optional: ls data/target_outputs/vi_parquet_date_audit*.csv* ",
    "if a pre-delete flagged CSV still exists."
  )
  from_release_orphans <- TRUE
}

if (from_release_orphans) {
  source_label <- "release_orphans"
  assets <- vi_grid_assets_from_release_orphans(repo = repo, verbose = TRUE)
  message("Release-orphan plan: ", nrow(assets), " sensor COG asset name(s)")
}

if (is.null(assets) && !is.null(from_csv) && nzchar(from_csv)) {
  source_label <- paste0("parquet_audit:", from_csv)
  assets <- vi_grid_assets_from_parquet_audit(from_csv)
  warn <- attr(assets, "csv_warning")
  if (!is.null(warn) && nzchar(warn)) {
    message("WARNING: ", warn)
    assets <- NULL
    if (!from_local_doy && is.null(dates_file) && !from_release_orphans) {
      message(
        "Falling back to --from-release-orphans ",
        "(survivor CSV cannot map deletes)."
      )
      from_release_orphans <- TRUE
      source_label <- "release_orphans"
      assets <- vi_grid_assets_from_release_orphans(repo = repo, verbose = TRUE)
    }
  } else {
    message(
      "Mapped ", attr(assets, "n_flagged_parquet"), " flagged parquet(s) → ",
      nrow(assets), " sensor COG asset name(s)"
    )
  }
}

if ((is.null(assets) || !nrow(assets)) &&
      !is.null(dates_file) && nzchar(dates_file)) {
  if (!file.exists(dates_file)) {
    stop("Missing --dates-file: ", dates_file, call. = FALSE)
  }
  source_label <- paste0("dates_file:", dates_file)
  dates <- trimws(readLines(dates_file, warn = FALSE))
  dates <- dates[nzchar(dates) & !startsWith(dates, "#")]
  # Allow full parquet/COG basenames or bare YYYYMMDD
  yyyymmdd <- vapply(dates, function(x) {
    m <- regexpr("20[0-9]{6}", basename(x), perl = TRUE)
    if (is.na(m) || m < 1L) return(NA_character_)
    substring(basename(x), m, m + 7L)
  }, character(1))
  yyyymmdd <- unique(yyyymmdd[!is.na(yyyymmdd)])
  assets <- vi_grid_assets_from_dates(yyyymmdd)
  message("Dates file → ", length(yyyymmdd), " composite(s) → ",
          nrow(assets), " sensor COG asset name(s)")
}

if ((is.null(assets) || !nrow(assets)) && from_local_doy) {
  source_label <- "local_doy_scan"
  assets <- vi_flag_local_grids_by_doy(verbose = TRUE)
  if (!nrow(assets) && !from_release_orphans) {
    message(
      "Local DOY scan found nothing. Trying --from-release-orphans…"
    )
    source_label <- "release_orphans"
    assets <- vi_grid_assets_from_release_orphans(repo = repo, verbose = TRUE)
  }
}

if (is.null(assets) || !nrow(assets)) {
  message("Nothing to delete.")
  quit(status = 0)
}

assets$source <- source_label
dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(assets, out_csv, row.names = FALSE)
message("Wrote delete plan: ", out_csv, " (", nrow(assets), " rows)")

result <- delete_vi_grid_assets(
  assets = assets,
  repo = repo,
  delete_remote = delete_remote,
  delete_local = delete_local,
  dry_run = dry_run,
  verbose = TRUE
)

if (dry_run) {
  message(
    "Next (real delete):\n",
    "  Rscript R/delete_vi_grids_from_audit.R \\\n",
    "    --from-release-orphans --delete-remote\n",
    "Then invalidate pending (GitHub release changes are invisible to targets):\n",
    "  R -e 'targets::tar_invalidate(any_of(c(\n",
    "    \"vi_modis_pending\",\"vi_viirs_pending\",\n",
    "    \"vi_modis_task_ids\",\"vi_modis_geotiff\",\"vi_modis_grid\",\"vi_modis_parquet\",\n",
    "    \"vi_viirs_task_ids\",\"vi_viirs_geotiff\",\"vi_viirs_grid\",\"vi_viirs_parquet\")))'\n",
    "Then: sbatch --cluster=faculty run_tar_make.sh"
  )
} else {
  message(
    "Deleted remote=", length(result$remote_deleted),
    " local=", length(result$local_deleted),
    ".\n",
    "IMPORTANT: empty raster releases do NOT auto-expand pending — ",
    "vi_*_pending is cached in _targets. Invalidate then remake:\n",
    "  R -e 'targets::tar_invalidate(any_of(c(\n",
    "    \"vi_modis_pending\",\"vi_viirs_pending\",\n",
    "    \"vi_modis_task_ids\",\"vi_modis_geotiff\",\"vi_modis_grid\",\"vi_modis_parquet\",\n",
    "    \"vi_viirs_task_ids\",\"vi_viirs_geotiff\",\"vi_viirs_grid\",\"vi_viirs_parquet\")))'\n",
    "  sbatch --cluster=faculty run_tar_make.sh"
  )
}
