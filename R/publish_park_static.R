#!/usr/bin/env Rscript
# =============================================================================
# Publish park products to eco-emma/emma_envdata@static_data
#
# Primary path (first publish): run on CCR after merging this branch.
# See internal status / PR body for exact CCR steps.
#
# GHA-capable fallback (later): workflow_dispatch job `publish-parks` runs this
# script; it downloads domain.tif from static_data when no local path is set.
#
# Usage:
#   Rscript R/publish_park_static.R
#   Rscript R/publish_park_static.R --no-upload
#   PARK_DOMAIN_TIF=/path/to/domain.tif Rscript R/publish_park_static.R
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
do_upload <- !("--no-upload" %in% args)

r_files <- list.files("R", pattern = "^[^.].*\\.R$", full.names = TRUE)
r_files <- r_files[
  !basename(r_files) %in% c(
    "backfill_stac_release.R",
    "ci_appeears_update.R",
    "publish_park_static.R"
  )
]
for (f in r_files) source(f, local = FALSE)

# Quiet package load when DESCRIPTION is present
if (file.exists("DESCRIPTION") && exists("load_description_packages")) {
  tryCatch(load_description_packages(verbose = FALSE), error = function(e) {
    message("Package preload skipped: ", conditionMessage(e))
  })
}

domain_tif <- Sys.getenv("PARK_DOMAIN_TIF", unset = "")
if (!nzchar(domain_tif)) domain_tif <- NULL

repo <- Sys.getenv("TAR_GH_RELEASE_REPO", unset = "eco-emma/emma_envdata")

message("publish_park_static: upload=", do_upload, " repo=", repo)
files <- publish_park_static_products(
  out_dir = "data/target_outputs",
  work_dir = "data/temp/parks",
  domain_tif = domain_tif,
  repo = repo,
  upload = do_upload,
  verbose = TRUE
)

message("Done. Products:\n", paste(" -", files, collapse = "\n"))
