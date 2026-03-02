#' Generate a human-readable manifest of all targets for the GitHub release
#'
#' Creates a JSON file mapping target names to descriptions and file hashes
#' from the targets store. Useful for cross-referencing hash-based filenames
#' in the GitHub release with human-readable target names.
#'
#' @return Path to manifest file
#' @export
#'
generate_release_manifest <- function() {
  
  # Target descriptions
  descriptions <- c(
    vegmap_shp = "Vegetation map shapefile (from GitHub release vegmap2024)",
    remnants_shp = "Vegetation remnants shapefile (manual download)",
    capenature_fires_shp = "Fire extent shapefile (manual download)",
    country.parquet = "Country boundary geometry (derived from geodata)",
    domain_boundary.parquet = "Study domain boundary (intersection of vegetation map and country)",
    domain_bbox.parquet = "50km-buffered download boundary (locked to prevent re-downloads)",
    domain_nc = "Domain raster grid with pixel IDs, remnants, and distance-to-remnants",
    vegmap_nc = "Vegetation map rasterized to analysis grid",
    climate_chelsa = "CHELSA bioclimatic variables (19 NetCDF files: bio01-bio19)",
    elevation_task_id = "AppEEARS task ID for NASADEM elevation download (task submission only)",
    elevation = "NASADEM elevation data (resampled to analysis grid, masked to domain)"
  )
  
  # Build JSON string directly to avoid complex object serialization
  json_lines <- c("{", "  \"targets\": [")
  
  for (i in seq_along(descriptions)) {
    target_name <- names(descriptions)[i]
    description <- descriptions[i]
    # Escape quotes in description
    description <- gsub('"', '\\"', description, fixed = TRUE)
    comma <- if (i < length(descriptions)) "," else ""
    json_lines <- c(json_lines, sprintf('    {"name": "%s", "description": "%s"}%s', target_name, description, comma))
  }
  
  json_lines <- c(json_lines, "  ]", "}")
  json_manifest <- paste(json_lines, collapse = "\n")
  
  # Write to file
  out_file <- "data/target_outputs/TARGET_MANIFEST.json"
  writeLines(json_manifest, con = out_file)
  
  out_file  # Return the file path for targets
}
