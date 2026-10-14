#!/usr/bin/env Rscript
# =============================================================================
# Publish iNaturalist invasives to eco-emma/emma_envdata@inat_data
#
# Primary path (first publish): run on CCR after parks_buffer_10km.gpkg is on
# static_data (parks Phase B / PR #31 CCR prime). See docs/INAT_DATA_PUBLISH.md.
#
# GHA-capable later: workflow_dispatch job `publish-inat` runs this script.
# Nightly cron is deferred — keep AppEEARS / weather / iNat as separate jobs.
#
# Usage:
#   Rscript R/publish_inat_data.R
#   Rscript R/publish_inat_data.R --no-upload
#   INAT_AOI_GPKG=/path/to/parks_buffer_10km.gpkg Rscript R/publish_inat_data.R
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
do_upload <- !("--no-upload" %in% args)

r_files <- list.files("R", pattern = "^[^.].*\\.R$", full.names = TRUE)
r_files <- r_files[
  !basename(r_files) %in% c(
    "backfill_stac_release.R",
    "ci_appeears_update.R",
    "publish_park_static.R",
    "publish_inat_data.R"
  )
]
for (f in r_files) source(f, local = FALSE)

if (file.exists("DESCRIPTION") && exists("load_description_packages")) {
  tryCatch(load_description_packages(verbose = FALSE), error = function(e) {
    message("Package preload skipped: ", conditionMessage(e))
  })
}

aoi_gpkg <- Sys.getenv("INAT_AOI_GPKG", unset = "")
if (!nzchar(aoi_gpkg)) aoi_gpkg <- NULL

repo <- Sys.getenv("TAR_GH_RELEASE_REPO", unset = "eco-emma/emma_envdata")

message("publish_inat_data: upload=", do_upload, " repo=", repo)
files <- publish_inat_invasives_product(
  out_dir = "data/target_outputs",
  work_dir = "data/temp/inat",
  aoi_gpkg = aoi_gpkg,
  repo = repo,
  upload = do_upload,
  verbose = TRUE
)

message("Done. Products:\n", paste(" -", files, collapse = "\n"))
