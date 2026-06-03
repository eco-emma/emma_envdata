# ============================================================================
# Soil Data — SoilGrids v2 (ISRIC)
# ============================================================================
# Downloads soil property data from the ISRIC SoilGrids v2 WCS API.
# Replaces the broken GCFR / RDryad source.
#
# SoilGrids v2 documentation: https://www.isric.org/explore/soilgrids
# WCS endpoint docs:          https://www.isric.org/explore/soilgrids/faq-soilgrids
# Licence: CC BY 4.0
#
# --- URL version pin ---
# The ISRIC WCS base URL has changed twice since 2022. If downloads fail with
# HTTP 4xx/5xx errors, check https://www.isric.org/explore/soilgrids/faq-soilgrids
# for the current endpoint and update SOILGRIDS_WCS_BASE below.
#
# Current pinned version: maps.isric.org (confirmed working 2026-05)
SOILGRIDS_WCS_BASE <- "https://maps.isric.org/mapserv?map=/map/{property}.map"
#
# Properties requested (0–30cm depth, mean estimate):
#   soc   (g/kg)    : Soil organic carbon
#   clay  (g/kg)    : Clay content
#   sand  (g/kg)    : Sand content
#   phh2o (pH × 10) : pH in water
#   bdod  (kg/dm³)  : Bulk density
#
# Strategy:
#   SoilGrids provides Cloud-Optimised GeoTIFFs (COGs) via WCS.
#   We use httr2 to query the WCS endpoint for each property/depth combination,
#   download the COG, crop to domain, reproject, and depth-average to 0-30cm.
# ============================================================================


#' @title Download and process SoilGrids v2 soil property data
#'
#' @description Downloads five soil properties from the ISRIC SoilGrids v2 REST API,
#'   averages across the 0–30cm depth interval, reprojects to the domain grid, and
#'   returns a multi-layer SpatRaster for storage as a COG via geotargets::tar_terra_rast().
#'   Properties included: SOC, clay, sand, pH, bulk density.
#'
#' @param domain_raster   SpatRaster or file path to domain raster (defines target grid and CRS).
#' @param temp_directory  Character. Directory for downloaded raw GeoTIFFs.
#' @param cleanup         Logical. Delete raw downloads after processing?
#' @param verbose         Logical. Print progress messages? Default TRUE.
#'
#' @return A 5-band SpatRaster (EPSG:9221, 500m) with bands: soc, clay, sand, phh2o, bdod.
#' @export
get_soilgrid <- function(
    domain_raster,
    temp_directory = "data/temp/appeears/soilgrid/",
    cleanup        = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose        = TRUE) {

  # Return cached file if already processed (avoids re-downloading on local runs)
  # Note: caching is now handled by targets (cue = "never"); this guard is kept
  # only for interactive use outside the pipeline.

  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  old_timeout <- getOption("timeout")
  options(timeout = 600)
  on.exit(options(timeout = old_timeout), add = TRUE)

  # Load domain template for reprojection and bounding box
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster

  # Compute WGS84 bounding box for the API query (SoilGrids requires WGS84 coords)
  domain_wgs84    <- terra::project(domain_template[["pid"]], "EPSG:4326")
  bbox            <- terra::ext(domain_wgs84)

  # ── SoilGrids property × depth layer definitions ────────────────────────
  # depth_range: SoilGrids uses "0-5cm", "5-15cm", "15-30cm" depth intervals.
  # We download all three and average to produce a 0-30cm mean.
  # quantile: "mean" is the expected value of the posterior distribution.
  soil_properties <- tibble::tribble(
    ~property, ~long_name,               ~units,    ~scale_factor,
    "soc",     "Soil_Organic_Carbon",    "g_kg",    10,   # stored as dg/kg in SoilGrids → ÷10
    "clay",    "Clay_Content",           "g_kg",    10,
    "sand",    "Sand_Content",           "g_kg",    10,
    "phh2o",   "pH_in_Water",            "pH",      10,
    "bdod",    "Bulk_Density",           "kg_dm3",  100   # stored as cg/cm3 → ÷100
  )

  depth_intervals <- c("0-5cm", "5-15cm", "15-30cm")

  # ── Download each property × depth combination ──────────────────────────
  if (verbose) message("Downloading SoilGrids layers for ", nrow(soil_properties), " properties ...")

  # Build a grid of all property × depth combinations to process in one pmap() call
  download_grid <- tidyr::expand_grid(
    soil_properties,
    depth = depth_intervals
  )

  # Download function for a single property + depth combination
  download_one_layer <- function(property, long_name, units, scale_factor, depth) {
    # Build WCS URL using the pinned base endpoint (SOILGRIDS_WCS_BASE, defined at top of file).
    # If downloads fail, verify the base URL at https://www.isric.org/explore/soilgrids/faq-soilgrids
    wcs_url <- glue::glue(
      SOILGRIDS_WCS_BASE,
      "&SERVICE=WCS&VERSION=2.0.1&REQUEST=GetCoverage",
      "&COVERAGEID={property}_{depth}_mean",
      "&FORMAT=image/tiff",
      "&SUBSET=long({bbox$xmin},{bbox$xmax})",
      "&SUBSET=lat({bbox$ymin},{bbox$ymax})",
      "&SUBSETTINGCRS=http://www.opengis.net/def/crs/EPSG/0/4326",
      "&OUTPUTCRS=http://www.opengis.net/def/crs/EPSG/0/4326"
    )

    dest_file <- file.path(temp_directory, paste0(property, "_", gsub("-", "", depth), "_mean.tif"))

    if (!file.exists(dest_file)) {
      if (verbose) message("  Downloading: ", property, " ", depth)
      req <- httr2::request(wcs_url) |>
        httr2::req_timeout(300) |>
        httr2::req_retry(max_tries = 3, backoff = ~ 30)

      resp <- httr2::req_perform(req)
      httr2::resp_check_status(resp)
      writeBin(httr2::resp_body_raw(resp), dest_file)
    } else {
      if (verbose) message("  Cached: ", basename(dest_file))
    }

    # Load, scale, crop, reproject to domain
    terra::rast(dest_file) |>
      terra::crop(terra::ext(domain_wgs84)) |>
      # Apply scale factor to convert SoilGrids integer storage units to real units
      terra::app(function(x) x / scale_factor) |>
      terra::project(domain_template, method = "bilinear")
  }

  # Download all layers; iterate by row index so terra's ..1/..2 internals
  # do not conflict with purrr's ..N argument passing
  all_layers <- purrr::map(seq_len(nrow(download_grid)), function(i) {
    row <- download_grid[i, ]
    download_one_layer(
      property     = row$property,
      long_name    = row$long_name,
      units        = row$units,
      scale_factor = row$scale_factor,
      depth        = row$depth
    )
  })

  # ── Average across depth intervals for each property ────────────────────
  # For each property, stack the 3 depth layers and compute the pixel-wise mean.
  # Depth-interval weighting: 0-5cm = 5cm, 5-15cm = 10cm, 15-30cm = 15cm → proportional
  depth_weights <- c("0-5cm" = 5, "5-15cm" = 10, "15-30cm" = 15) / 30

  if (verbose) message("Averaging soil layers across 0–30cm depth interval ...")

  # Split the flat list back into property groups (3 depths each)
  n_props    <- nrow(soil_properties)
  prop_names <- soil_properties$property

  depth_averaged_list <- purrr::map(seq_len(n_props), function(pi) {
    # Extract the 3 depth layers for this property
    n_depths      <- length(depth_intervals)
    layer_indices <- ((pi - 1L) * n_depths + 1L):(pi * n_depths)
    depth_stack   <- terra::rast(all_layers[layer_indices])

    # Weighted average: 0-5cm=5, 5-15cm=10, 15-30cm=15 → sum weights = 30
    weights <- unname(depth_weights[depth_intervals])
    terra::app(depth_stack, fun = function(x) sum(x * weights, na.rm = TRUE)) |>
      terra::mask(domain_template[["pid"]])  # mask per-layer so stack stays multi-source
  })

  names(depth_averaged_list) <- prop_names

  # Stack and name — masking already applied per-layer above
  if (verbose) message("Stacking soil properties and masking to domain ...")

  soil_stack <- terra::rast(depth_averaged_list)
  names(soil_stack) <- prop_names

  # Per-layer long names and units — stored as GDAL band fields that survive
  # COG round-trips
  terra::longnames(soil_stack) <- soil_properties$long_name
  terra::units(soil_stack)     <- soil_properties$units

  # Dataset-level provenance (survives COG round-trip via GDAL metadata)
  terra::metags(soil_stack) <- c(
    source       = "ISRIC SoilGrids v2 (CC BY 4.0)",
    depth        = "0-30cm depth-weighted mean",
    date_created = as.character(Sys.Date())
  )

  if (cleanup) {
    unlink(temp_directory, recursive = TRUE, force = TRUE)
    if (verbose) message("Cleaned up temp directory: ", temp_directory)
  }

  if (verbose) message("Soil properties processing complete (", terra::nlyr(soil_stack), " layers).")
  soil_stack
}
