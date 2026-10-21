#!/usr/bin/env Rscript
# =============================================================================
# Audit VI parquet filename vs content dates (MODIS + VIIRS)
#
# Lists misaligned / duplicate-value assets under the CCR product dirs (or
# paths you pass). Optionally deletes flagged local files and matching GitHub
# release assets so the next tar_make() can regenerate from COGs.
#
# Usage (inside Apptainer from `bash R/ccr_startup.sh shell`):
#   Rscript R/audit_vi_parquet_dates.R
#   Rscript R/audit_vi_parquet_dates.R --out data/target_outputs/vi_parquet_date_audit.csv
#   Rscript R/audit_vi_parquet_dates.R --no-hash
#   Rscript R/audit_vi_parquet_dates.R --delete-local --dry-run
#   Rscript R/audit_vi_parquet_dates.R --delete-local --delete-remote
#
# See docs/VI_PARQUET_REALIGN.md for the full CCR regenerate / republish flow.
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

out_csv <- flag_value(
  "--out",
  "data/target_outputs/vi_parquet_date_audit.csv"
)
hash_values <- !has_flag("--no-hash")
delete_local <- has_flag("--delete-local")
delete_remote <- has_flag("--delete-remote")
# Default is report-only. Deletes run only when --delete-* is set and
# --dry-run is not.
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
  "audit_vi_parquet_dates: out=", out_csv,
  " hash_values=", hash_values,
  " delete_local=", delete_local,
  " delete_remote=", delete_remote,
  " dry_run=", dry_run,
  " repo=", repo
)

report <- audit_vi_parquet_dirs(
  out_csv = out_csv,
  hash_values = hash_values,
  verbose = TRUE
)

flagged <- report[report$status != "ok", , drop = FALSE]
message(
  "Flagged ", nrow(flagged), " / ", nrow(report),
  " (statuses: ",
  paste(names(sort(table(flagged$status), decreasing = TRUE)), collapse = ", "),
  ")"
)

if (!nrow(flagged)) {
  message("Nothing to delete — all audited files aligned.")
  quit(status = 0)
}

if (dry_run) {
  message(
    "Dry run — not deleting. Sample flagged:\n",
    paste(
      " -", utils::head(flagged$file, 20L), " [", utils::head(flagged$status, 20L), "]",
      collapse = "\n"
    )
  )
  message(
    "Re-run with --delete-local and/or --delete-remote (without --dry-run) ",
    "after inspecting ", out_csv
  )
  quit(status = 0)
}

if (delete_local) {
  for (p in flagged$path) {
    if (file.exists(p)) {
      unlink(p)
      message("Deleted local: ", p)
    }
  }
}

if (delete_remote) {
  token <- .gh_upload_token(verbose = TRUE)
  by_tag <- split(flagged$file, vi_parquet_release_tag(flagged$file))
  for (tag in names(by_tag)) {
    if (is.na(tag) || !nzchar(tag)) {
      next
    }
    gh_delete_release_assets_by_name(
      repo = repo,
      release_tag = tag,
      asset_names = by_tag[[tag]],
      token = token,
      verbose = TRUE
    )
  }
}

message(
  "Next: regenerate missing composites from COGs/AppEEARS, then ",
  "tar_make(c(upload_vi_modis, upload_vi_viirs)) — see docs/VI_PARQUET_REALIGN.md"
)
