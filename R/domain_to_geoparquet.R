#' @title Convert domain raster to geoparquet
#' @description Converts the domain raster (with pid and coordinates) to a geoparquet file
#' for use as a spatial reference for dynamic data
#' @param domain_raster_file Path to domain NetCDF file (from domain_rasterize)
#' @param out_file Output geoparquet file path
#' @param verbose Logical for progress messages
#' @return Character path to the written geoparquet file
#' @details Extracts the pid layer from the domain raster, converts to a point geometry
#' with coordinates, and writes as a geoparquet file for efficient spatial queries
#' @import terra
#' @import sf
#' @import sfarrow

domain_to_geoparquet <- function(
  domain_raster_file,
  out_file = "data/target_outputs/domain.parquet",
  verbose = TRUE
) {

  # Load the pid layer from the domain raster (accepts file path or SpatRaster from tar_terra_rast)
  domain_raster <- if (is.character(domain_raster_file)) {
    terra::rast(domain_raster_file, subds = "pid")
  } else {
    domain_raster_file[["pid"]]
  }
  
  # Convert raster to dataframe with coordinates
  # This gives us x, y coordinates and the pid value for each non-NA cell
  df <- terra::as.data.frame(domain_raster, xy = TRUE, na.rm = TRUE)
  colnames(df) <- c("x", "y", "pid")
  
  # Convert to spatial points dataframe
  sp_df <- sf::st_as_sf(df, coords = c("x", "y"), crs = terra::crs(domain_raster))
  
  if (verbose) message("Converting to geoparquet: ", nrow(sp_df), " pixels")
  
  # Ensure output directory exists
  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  
  # Write as geoparquet using sfarrow
  sfarrow::st_write_parquet(sp_df, out_file)
  
  if (verbose) message("Domain geoparquet written to: ", out_file)
  
  invisible(out_file)
}
