#!/usr/bin/env Rscript

# This is a helper script to run the pipeline.
# Choose how to execute the pipeline below.
# See https://books.ropensci.org/targets/hpc.html
# to learn about your options.

source('R/tar_release_storage.R')

# Run pipeline; upload to GitHub release only if tar_make() succeeds (it errors on failure)
targets::tar_make()
tar_upload_github_release(
  repo = Sys.getenv("TAR_GH_RELEASE_REPO"),
  tag = Sys.getenv("TAR_GH_RELEASE_TAG"),
  cache_dir = Sys.getenv("TAR_GH_RELEASE_CACHE_DIR"),
  verbose = TRUE
)
# targets::tar_make_clustermq(workers = 2) # nolint
# targets::tar_make_future(workers = 2) # nolint
