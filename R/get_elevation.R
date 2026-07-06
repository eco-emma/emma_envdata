#' @title Submit NASADEM elevation request via AppEEARS
#' @description Submits an AppEEARS area request for NASADEM elevation data
#' over the provided domain polygon. Returns task ID for polling.
#' @author EMMA Team
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param targets_store Path to the targets object store directory (default
#'   \code{"_targets/objects"}). If \code{elevation.tif} exists here the
#'   submission is skipped entirely.
#' @param temp_directory Path to the AppEEARS download temp directory. If raw
#'   GeoTIFF files are already present here (but not yet in the targets store),
#'   the AppEEARS submission is skipped and the data are reprocessed locally.
#' @param verbose Logical for progress messages
#' @return Character string: AppEEARS task ID, \code{"cached"} when the
#'   processed result already exists in the targets store, or
#'   \code{"cached_temp"} when raw AppEEARS downloads exist in the temp
#'   directory and only need to be reprocessed.

submit_elevation_task <- function(
  domain_vector,
  targets_store  = "_targets/objects",
  temp_directory = "data/temp/appeears/elevation_nasadem/",
  verbose        = TRUE
) {

  # 1. Check targets store — elevation.tif already fully processed
  elev_obj <- file.path(targets_store, "elevation.tif")
  if (file.exists(elev_obj)) {
    if (verbose) message("elevation.tif found in targets store — skipping AppEEARS submission")
    return("cached")
  }

  # 2. Check temp directory — raw AppEEARS download exists but not yet processed
  if (dir.exists(temp_directory)) {
    raw_tifs <- list.files(temp_directory, pattern = "\\.tif$",
                           full.names = TRUE, recursive = TRUE)
    srtm_tifs <- raw_tifs[grepl("SRTMGL3", raw_tifs)]
    if (length(srtm_tifs) > 0) {
      if (verbose) message("Raw AppEEARS elevation data found in ", temp_directory,
                           " — skipping submission, will reprocess")
      return("cached_temp")
    }
  }

  # 3. Neither exists — submit a new AppEEARS task
  ensure_appeears_auth()
  # Convert domain vector to sf, fix geometry, simplify, merge, and reproject to WGS84 (required by AppEEARS)
  domain_sf <- st_as_sf(domain_vector) |>
    st_transform(crs = 4326) |>
    geojsonsf::sf_geojson(simplify = FALSE) |>
    jsonlite::fromJSON()

  # Build AppEEARS request with proper structure
  req <- list(
    task_type = "area",
    task_name = paste0("NASADEM_", format(Sys.time(), "%Y%m%d%H%M%S")),
    params = list(
      dates = list(list(
        startDate = "02-11-2000",
        endDate = "02-11-2000"
      )),
      layers = list(list(
        product = "SRTMGL3_NC.003",
        layer = "SRTMGL3_DEM"
      )),
      output = list(
        format = list(type = "geotiff"),
        projection = "native"
      ),
      geo = domain_sf
    )
  )

  # Submit task
  if (verbose) message("Submitting AppEEARS elevation task...")
  task <- tryCatch(
    appeears::rs_request(
      request  = req,
      user     = Sys.getenv("EARTHDATA_USER"),
      transfer = FALSE,
      verbose  = verbose
    ),
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("exceeded.*maximum.*requests|too many requests",
                msg, ignore.case = TRUE)) {
        # Rate limit hit — stop() so the target is marked errored and
        # can be retried on the next tar_make().
        stop(
          "AppEEARS daily request limit reached for elevation task. ",
          "Re-run the pipeline tomorrow to retry.\n",
          "Original error: ", msg,
          call. = FALSE
        )
      }
      stop(e)  # re-throw non-rate-limit errors unchanged
    }
  )

  task_id <- task$get_task_id()
  if (verbose) message("Task submitted with ID: ", task_id)

  task_id
}


#' @title Download and process NASADEM elevation from AppEEARS
#' @description Polls for completion of AppEEARS task and downloads results,
#' then resamples elevation to domain grid and writes to GeoTIFF.
#' Handles three sentinels from \code{submit_elevation_task()}:
#' \itemize{
#'   \item \code{"cached"} — elevation.tif already in targets store; skip entirely.
#'   \item \code{"cached_temp"} — raw AppEEARS GeoTIFFs already in \code{temp_directory};
#'         skip polling/download and reprocess directly.
#'   \item Any other string — treat as an AppEEARS task ID; poll, download, then process.
#' }
#' @author EMMA Team
#' @param task_id Character string: AppEEARS task ID or sentinel from
#'   \code{submit_elevation_task()}
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param domain_raster A SpatRaster (domain.tif) defining the output grid and mask
#' @param temp_directory Temporary working directory for downloads
#' @param cleanup Logical; delete temp files after processing
#' @param verbose Logical for progress messages
#' @return SpatRaster of elevation on the domain grid

download_elevation_results <- function(
  task_id,
  domain_vector,
  domain_raster,
  temp_directory = "data/temp/appeears/elevation_nasadem/",
  cleanup = FALSE,
  verbose = TRUE
) {

  # Sentinel: elevation.tif already fully processed in targets store — nothing to do.
  # tar_cue(mode = "never") on the elevation.tif target means the existing cached
  # object in the store is returned without re-running this function.
  if (identical(task_id, "cached")) {
    if (verbose) message("Sentinel 'cached' \u2014 elevation.tif already in targets store, skipping")
    return(invisible(NULL))
  }

  # Clean terra temp
  terra_tmp <- file.path(getwd(), "data/temp/terra")
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  # Sentinel: raw AppEEARS data already in temp_directory — skip poll/download.
  if (identical(task_id, "cached_temp")) {
    if (verbose) message("Sentinel 'cached_temp' \u2014 reprocessing existing AppEEARS files in ", temp_directory)
    tif_paths <- list.files(temp_directory, pattern = "\\.tif$", full.names = TRUE, recursive = TRUE)
    if (length(tif_paths) == 0) {
      stop("'cached_temp' sentinel set but no .tif files found in ", temp_directory)
    }
  } else {
    # Normal path: poll AppEEARS for task completion, then download
    ensure_appeears_auth()

    # Ensure clean temp directory before downloading
    unlink(temp_directory, recursive = TRUE, force = TRUE)
    dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

    # Poll for task completion using rs_list_task
    if (verbose) message("Polling task ", task_id, " for completion...")
    max_retries <- 120  # 2 hours at 60s intervals
    retry_count <- 0

    repeat {
      retry_count <- retry_count + 1

      task_info <- appeears::rs_list_task(task_id = task_id, user = Sys.getenv("EARTHDATA_USER"))
      task_status <- task_info$status

      if (task_status == "done") {
        if (verbose) message("Task completed successfully")
        break
      }

      if (task_status %in% c("failed", "error")) {
        stop("AppEEARS task ", task_id, " failed with status: ", task_status)
      }

      if (retry_count >= max_retries) {
        stop("Task ", task_id, " polling timed out after ", max_retries, " minutes")
      }

      if (verbose && retry_count %% 10 == 0) {
        message("Task status: ", task_status, " (", retry_count, "/", max_retries, ")")
      }

      Sys.sleep(60)
    }

    # Download results using rs_transfer
    if (verbose) message("Downloading files for task: ", task_id)
    appeears::rs_transfer(
      task_id = task_id,
      user = Sys.getenv("EARTHDATA_USER"),
      path = temp_directory,
      verbose = verbose
    )

    tif_paths <- list.files(temp_directory, pattern = "\\.tif$", full.names = TRUE, recursive = TRUE)
  }

  # ── Process downloaded / pre-existing GeoTIFFs ──────────────────────────────
  tif_paths <- list.files(temp_directory, pattern = "\\.tif$", full.names = TRUE, recursive = TRUE)
  if (length(tif_paths) == 0) {
    stop("No GeoTIFF files downloaded from AppEEARS")
  }

  dem_path <- tif_paths[grepl("SRTMGL3", tif_paths)]
  if (length(dem_path) == 0) dem_path <- tif_paths[1]
  if (verbose) message("Reading elevation data from: ", dem_path[1])
  elev_raster <- terra::rast(dem_path[1])

  # Ensure we have a SpatRaster template (accept path or raster)
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster

  # Project to domain CRS/grid and mask to domain
  if (verbose) message("Projecting elevation to domain CRS/grid")
  elev_on_grid <- terra::project(elev_raster, domain_template, method = "average")

  # Mask to domain (NA where domain is NA)
  mask_layer <- if ("domain" %in% names(domain_template)) domain_template[["domain"]] else domain_template
  elev_masked <- terra::mask(elev_on_grid, mask_layer)

  # Set metadata
  names(elev_masked) <- "elevation"

  # Embed metadata in COG TIFF GDAL metadata (survives COG round-trip)
  terra::metags(elev_masked) <- c(
    date_created = as.character(Sys.Date()),
    source       = "NASADEM_HGT.001 via AppEEARS",
    description  = "NASADEM elevation resampled to 500m domain grid"
  )
  terra::metags(elev_masked, layer = 1) <- c(
    description = "Elevation above mean sea level",
    units       = "metres"
  )

  # Force all raster values into memory before deleting temp dirs.
  # terra::project() / terra::mask() may have spilled to terra_tmp; if we
  # delete that directory first the returned SpatRaster would be file-backed
  # on a non-existent path, causing "raster has no values" in downstream
  # terra::extract() calls (e.g. in combine_static_layers_to_geoparquet).
 # elev_masked <- terra::readAll(elev_masked)

  # Cleanup temp downloads
if (cleanup) {
  unlink(temp_directory, recursive = TRUE, force = TRUE)
  gc()
  unlink(terra_tmp, recursive = TRUE, force = TRUE)
}

  if (verbose) message("Elevation processing complete.")
  elev_masked
}