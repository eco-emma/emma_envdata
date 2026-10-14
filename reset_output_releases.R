#!/usr/bin/env Rscript
# Delete output GitHub Releases so a CCR prime can publish a clean set.
#
# Keeps the input releases the pipeline downloads:
#   vegmap2024, manual-data
# Leaves legacy 2022-2024 tags alone (clean_*, raw_*, objects_current, ...).
#
# Dry run (prints the gh commands, deletes nothing):
#   Rscript reset_output_releases.R
#
# Delete, after the MODIS VI tag fix is on the branch you will prime:
#   CONFIRM_RESET_RELEASES=yes Rscript reset_output_releases.R --delete
#
# Then run run_tar_make.sh. Re-enable the Monday cron in
# .github/workflows/targets.yaml only after targets-cache-1..4 and the
# product tags below exist and look complete.

repo <- "eco-emma/emma_envdata"

output_tags <- c(
  paste0("targets-cache-", 1:4),
  "static_data",
  "vi_modis_raster",
  "vi_modis_terra_raster",
  "vi_modis_aqua_raster",
  "vi_viirs_raster",
  "vi_modis_parquet",
  "vi_viirs_parquet",
  "burn_modis_raster",
  "burn_viirs_raster",
  "burn_modis_parquet",
  "burn_viirs_parquet",
  "fireage",
  "stac",
  "stac-vi",
  "stac-burn",
  "stac-static",
  "stac-vi-2000s",
  "stac-vi-2010s",
  "stac-vi-2020s",
  "weather_data",
  "inat_data",
  "readme-assets"
)

keep_tags <- c("vegmap2024", "manual-data")
stopifnot(!any(output_tags %in% keep_tags))

args <- commandArgs(trailingOnly = TRUE)
do_delete <- "--delete" %in% args
confirmed <- identical(Sys.getenv("CONFIRM_RESET_RELEASES"), "yes")

message("Output releases that a fresh CCR prime should recreate:")
for (tag in output_tags) {
  message("  gh release delete ", tag, " --repo ", repo, " --yes --cleanup-tag")
}
message("Kept (inputs): ", paste(keep_tags, collapse = ", "))

if (!do_delete) {
  message("Dry run. Re-run with CONFIRM_RESET_RELEASES=yes and --delete to remove them.")
  quit(save = "no", status = 0)
}

if (!confirmed) {
  stop(
    "Refusing to delete releases. Set CONFIRM_RESET_RELEASES=yes and pass --delete.",
    call. = FALSE
  )
}

if (Sys.which("gh") == "") {
  stop("gh CLI is not on PATH.", call. = FALSE)
}

failed <- character(0)
for (tag in output_tags) {
  status <- system2(
    "gh",
    c("release", "delete", tag, "--repo", repo, "--yes", "--cleanup-tag"),
    stdout = "", stderr = ""
  )
  if (status == 0L) {
    message("Deleted ", tag)
  } else {
    message("Skip or fail (", status, "): ", tag)
    failed <- c(failed, tag)
  }
}

if (length(failed)) {
  message(
    "These tags were not deleted (missing releases exit non-zero, which is fine): ",
    paste(failed, collapse = ", ")
  )
}
