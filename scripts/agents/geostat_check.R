#!/usr/bin/env Rscript
message("Running geostat agent checks")
if (!requireNamespace("terra", quietly = TRUE)) {
  message("Package 'terra' is not installed. Install it to run geospatial checks: install.packages('terra')")
  quit(status = 0)
}
if (!requireNamespace("sf", quietly = TRUE)) {
  message("Package 'sf' is not installed. Some vector checks will be skipped.")
}

library(terra)
library(fs)

data_dirs <- c("data", "data/raw", "data/target_outputs")
found <- FALSE
crs_list <- list()
issues <- list()

for (d in data_dirs) {
  if (!dir_exists(d)) next
  found <- TRUE
  rasters <- dir_ls(d, recurse = TRUE, regexp = "\\\.(tif|tiff|grd)$", ignore_case = TRUE)
  if (length(rasters) == 0) next
  for (r in rasters) {
    try({
      rr <- terra::rast(r)
      crs_list[[r]] <- terra::crs(rr)
    }, silent = TRUE)
  }
}

if (!found) {
  message("No data directories found (expected at least one of: data, data/raw, data/target_outputs).")
}

unique_crs <- unique(unlist(crs_list))
if (length(unique_crs) > 1) {
  message("CRS mismatch detected among raster files:")
  for (i in seq_along(crs_list)) message(names(crs_list)[i], " -> ", crs_list[[i]])
  quit(status = 2)
} else if (length(unique_crs) == 1) {
  message("All inspected rasters share the same CRS: ", unique_crs)
} else {
  message("No raster CRSs could be determined from inspected files.")
}

message("geostat agent finished")
