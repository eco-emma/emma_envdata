#!/usr/bin/env Rscript
# =============================================================================
# Publish GSOD weather + stations to eco-emma/emma_envdata@weather_data
#
# Primary path (first publish): run on CCR after parks `protected_areas.gpkg`
# exists on `static_data` (Phase B / PR #31 CCR prime).
# See docs/WEATHER_DATA_PUBLISH.md for exact CCR steps.
#
# GHA-capable fallback (later): workflow_dispatch job `publish-weather` runs
# this script. Never stacked with the AppEEARS nightly job.
#
# Usage:
#   Rscript R/publish_weather.R
#   Rscript R/publish_weather.R --no-upload
#   WEATHER_PARKS_GPKG=/path/to/protected_areas.gpkg Rscript R/publish_weather.R
#   WEATHER_MIN_YEAR=1970 Rscript R/publish_weather.R   # full history override
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
do_upload <- !("--no-upload" %in% args)

r_files <- list.files("R", pattern = "^[^.].*\\.R$", full.names = TRUE)
r_files <- r_files[
  !basename(r_files) %in% c(
    "backfill_stac_release.R",
    "ci_appeears_update.R",
    "publish_park_static.R",
    "publish_weather.R"
  )
]
for (f in r_files) source(f, local = FALSE)

if (file.exists("DESCRIPTION") && exists("load_description_packages")) {
  tryCatch(load_description_packages(verbose = FALSE), error = function(e) {
    message("Package preload skipped: ", conditionMessage(e))
  })
}

# GSODR is in adamwilsonlab/emma but may not be listed in DESCRIPTION yet.
if (!requireNamespace("GSODR", quietly = TRUE)) {
  stop("Package GSODR is required (present in adamwilsonlab/emma image).", call. = FALSE)
}

repo <- Sys.getenv("TAR_GH_RELEASE_REPO", unset = "eco-emma/emma_envdata")
parks_gpkg <- Sys.getenv("WEATHER_PARKS_GPKG", unset = "")
if (!nzchar(parks_gpkg)) parks_gpkg <- NULL

message("publish_weather: upload=", do_upload, " repo=", repo)
files <- publish_weather_products(
  out_dir = "data/target_outputs",
  work_dir = "data/temp/weather",
  parks_gpkg = parks_gpkg,
  repo = repo,
  upload = do_upload,
  verbose = TRUE
)

message("Done. Products:\n", paste(" -", files, collapse = "\n"))
