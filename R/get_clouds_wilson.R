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
#'   from EarthEnv, reprojects to the domain grid, and returns a
#'   3-band SpatRaster for storage as a COG via geotargets::tar_terra_rast().
#'
#' @param domain          An sf or SpatVector polygon defining the study domain.
#' @param domain_raster   SpatRaster or file path to domain raster (defines target grid).
#' @param temp_directory  Character. Directory for downloaded raw TIFs. Files are kept
#'   so re-running (e.g. after tar_invalidate) skips the 3 x ~700MB downloads.
#' @param cleanup         Logical. Delete raw downloads after processing?
#' @param verbose         Logical. Print progress messages? Default TRUE.
#'
#' @return A 3-band SpatRaster (EPSG:9221, 500m) with bands:
#'   MODCF_meanannual, MODCF_seasonality_concentration, MODCF_seasonality_theta.
#' @export
get_clouds_wilson <- function(
    domain,
    domain_raster,
    temp_directory = "data/temp/appeears/clouds_wilson/",
    cleanup        = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose        = TRUE) {


  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  # Extend timeout for large file downloads
  old_timeout <- getOption("timeout")
  options(timeout = 600)
  on.exit(options(timeout = old_timeout), add = TRUE)

  # ── Layer definitions ────────────────────────────────────────────────────
  # Each layer is a publicly available GeoTIFF from EarthEnv.
  # long_name and units follow CF conventions for the output file
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
      "Direction of Peak Cloud Seasonality",
      "degrees",
      "https://data.earthenv.org/cloud/MODCF_seasonality_theta.tif"
  )

  # Load domain template for reprojection (EPSG:9221, 500m)
  domain_template <- if (is.character(domain_raster)) {
    terra::rast(domain_raster)
  } else {
    domain_raster
  }

  # Pre-compute domain extent in WGS84 once — same for all layers
  domain_extent_wgs84 <- terra::ext(terra::project(domain_template, "EPSG:4326"))

  # ── Download each layer ──────────────────────────────────────────────────
  if (verbose) message("Downloading ", nrow(cloud_layers), " MODCF layers from EarthEnv ...")

  raster_list <- purrr::map(seq_len(nrow(cloud_layers)), function(i) {
    layer_name <- cloud_layers$layer_name[[i]]
    url        <- cloud_layers$url[[i]]
    dest_file  <- file.path(temp_directory, paste0(layer_name, ".tif"))

    if (!file.exists(dest_file)) {
      if (verbose) message("  Downloading: ", basename(url))
      tryCatch(
        download.file(url, destfile = dest_file, mode = "wb", quiet = !verbose),
        error = function(e) stop("Failed to download ", url, ": ", conditionMessage(e))
      )
    } else {
      if (verbose) message("  Already cached: ", basename(dest_file))
    }

    # Crop to domain extent in WGS84 before reprojecting to EPSG:9221 500m grid;
    # bilinear resampling appropriate for continuous percentage/index layers
    if (verbose) message("  Reprojecting to domain grid: ", layer_name)

    terra::rast(dest_file) |>
      terra::crop(domain_extent_wgs84) |>
      terra::project(domain_template, method = "bilinear") |>
      terra::mask(domain_template[["pid"]])
  })

  # ── Stack, name, and annotate with metadata ─────────────────────────────
  cloud_stack <- terra::rast(raster_list)
  names(cloud_stack) <- cloud_layers$layer_name

  # Dataset-level provenance (survives COG round-trip via GDAL metadata)
  terra::metags(cloud_stack) <- c(
    source       = "EarthEnv MODCF — Wilson et al. 2016, doi:10.1111/geb.12523",
    date_created = as.character(Sys.Date())
  )

  # Per-layer long names and units — stored as GDAL band fields that survive
  # COG round-trips (unlike terra::metags at layer level)
  terra::longnames(cloud_stack) <- cloud_layers$long_name
  terra::units(cloud_stack)     <- cloud_layers$units

  # Scale factors: bands 1-2 stored as integer percent * 100, band 3 as
  # degrees * 10 (i.e. raw / scale = physical value)
  terra::scoff(cloud_stack) <- cbind(
    scale  = c(0.01, 0.01, 0.1),
    offset = c(0,    0,    0)
  )

  if (cleanup) {
    unlink(temp_directory, recursive = TRUE, force = TRUE)
    if (verbose) message("Cleaned up temp directory: ", temp_directory)
  }

  if (verbose) message(
    "Cloud cover processing complete (", terra::nlyr(cloud_stack), " layers)."
  )
  cloud_stack
}
