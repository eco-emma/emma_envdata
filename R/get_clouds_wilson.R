# ============================================================================
# Cloud Cover — Wilson MODCF Dataset
# ============================================================================
# Downloads the Wilson et al. (2016) MODIS Cloud Frequency (MODCF) dataset.
# This provides long-term cloud climatology derived from Terra MODIS observations,
# and is used as a covariate for NDVI quality and environmental context.
#
# Dataset: EarthEnv MODIS Cloud Frequency (Wilson et al. 2016, Global Ecology and
#   Biogeography, doi:10.1111/geb.12523)
# Source:  https://data.earthenv.org/cloud
# Layers:
#   - MODCF_meanannual           : Mean annual cloud frequency (0–100%)
#   - MODCF_seasonality_concentration : Concentration of seasonality (0–1)
#   - MODCF_seasonality_rgb_cloudmonth: Month of peak cloud frequency (1–12)
# Resolution: ~1km (0.00833° WGS84)
# ============================================================================


#' @title Download and process MODCF cloud frequency data
#'
#' @description Downloads the Wilson et al. MODIS Cloud Frequency (MODCF) GeoTIFFs
#'   from EarthEnv, reprojects to the domain grid, and writes a multi-layer NetCDF.
#'
#' @param domain          An sf or SpatVector polygon defining the study domain.
#' @param domain_raster   SpatRaster or file path to domain.nc (defines target grid).
#' @param temp_directory  Character. Directory for downloaded raw TIFs.
#' @param out_file        Character. Output NetCDF path.
#' @param cleanup         Logical. Delete raw downloads after writing NetCDF?
#' @param verbose         Logical. Print progress messages? Default TRUE.
#'
#' @return Character path to the output NetCDF file.
#' @export
get_clouds_wilson <- function(
    domain,
    domain_raster,
    temp_directory = "data/temp/appeears/clouds_wilson/",
    out_file       = "data/target_outputs/clouds_wilson.nc",
    cleanup        = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose        = TRUE) {

  # Return cached file if it already exists (avoids re-downloading on local runs)
  if (file.exists(out_file)) {
    if (verbose) message("Cloud cover file already exists: ", out_file)
    return(out_file)
  }

  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)

  # Extend timeout for large file downloads
  old_timeout <- getOption("timeout")
  options(timeout = 600)
  on.exit(options(timeout = old_timeout), add = TRUE)

  # ── Layer definitions ────────────────────────────────────────────────────
  # Each layer is a publicly available GeoTIFF from EarthEnv.
  # long_name and units follow CF conventions for the output NetCDF.
  cloud_layers <- tibble::tribble(
    ~layer_name,                         ~long_name,                              ~units,  ~url,
    "MODCF_meanannual",
      "Mean Annual Cloud Frequency",
      "percent",
      "https://data.earthenv.org/cloud/MODCF_meanannual.tif",
    "MODCF_seasonality_concentration",
      "Cloud Seasonality Concentration",
      "unitless",
      "https://data.earthenv.org/cloud/MODCF_seasonality_concentration.tif",
    "MODCF_seasonality_theta",
      "Month of Peak Cloud Frequency",
      "month (1-12)",
      "https://data.earthenv.org/cloud/MODCF_seasonality_theta.tif"
  )

  # Load domain template for reprojection
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster

  # ── Download each layer ──────────────────────────────────────────────────
  if (verbose) message("Downloading ", nrow(cloud_layers), " MODCF layers from EarthEnv ...")

  raster_list <- purrr::pmap(cloud_layers, function(layer_name, long_name, units, url) {
    dest_file <- file.path(temp_directory, paste0(layer_name, ".tif"))

    if (!file.exists(dest_file)) {
      if (verbose) message("  Downloading: ", basename(url))
      tryCatch(
        download.file(url, destfile = dest_file, mode = "wb", quiet = !verbose),
        error = function(e) stop("Failed to download ", url, ": ", conditionMessage(e))
      )
    } else {
      if (verbose) message("  Already cached: ", basename(dest_file))
    }

    # Read, clip to domain extent, reproject to domain grid (bilinear for continuous data)
    if (verbose) message("  Reprojecting: ", layer_name)
    domain_extent <- terra::ext(terra::project(domain_template, "EPSG:4326"))

    terra::rast(dest_file) |>
      terra::crop(domain_extent) |>
      terra::project(domain_template, method = "bilinear") |>
      terra::mask(domain_template[["pid"]])  # mask to valid domain pixels
  })

  # ── Combine into multi-layer SpatRaster and write NetCDF ─────────────────
  if (verbose) message("Writing multi-layer cloud cover NetCDF ...")

  cloud_stack <- terra::rast(raster_list)
  names(cloud_stack) <- cloud_layers$layer_name

  # Write with CF-1.8 metadata
  terra::writeCDF(
    cloud_stack,
    filename  = out_file,
    overwrite = TRUE,
    varname   = "cloud_frequency",
    longname  = paste(cloud_layers$long_name, collapse = "; "),
    unit      = paste(cloud_layers$units, collapse = "; ")
  )

  if (verbose) message("Cloud cover NetCDF written: ", out_file)

  if (cleanup) {
    unlink(temp_directory, recursive = TRUE, force = TRUE)
    if (verbose) message("Cleaned up temp directory: ", temp_directory)
  }

  out_file
}
