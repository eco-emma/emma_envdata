#' @title Submit NASADEM elevation request via AppEEARS
#' @description Submits an AppEEARS area request for NASADEM elevation data
#' over the provided domain polygon. Returns task ID for polling.
#' @author EMMA Team
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param verbose Logical for progress messages
#' @return Character string with AppEEARS task ID

submit_elevation_task <- function(
  domain_vector,
  verbose = TRUE
) {

  ensure_appeears_auth()
  # Convert domain vector to sf, fix geometry, simplify, merge, and reproject to WGS84 (required by AppEEARS)
  domain_sf <- st_as_sf(domain_vector) %>%
    st_simplify(dTolerance = 100, preserveTopology = TRUE) %>%
    st_buffer(0) %>%
    st_make_valid() %>%
    st_transform(crs = 4326) %>%
    geojsonsf::sf_geojson(simplify = FALSE) %>%
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
  task <- appeears::rs_request(
    request = req,
    user = Sys.getenv("EARTHDATA_USER"),
    transfer = FALSE,
    verbose = verbose
  )
  
  task_id <- task$get_task_id()
  if (verbose) message("Task submitted with ID: ", task_id)
  
  task_id
}


#' @title Download and process NASADEM elevation from AppEEARS
#' @description Polls for completion of AppEEARS task and downloads results,
#' then resamples elevation to domain grid and writes to GeoTIFF.
#' @author EMMA Team
#' @param task_id Character string with AppEEARS task ID (from submit_elevation_task)
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param domain_raster A SpatRaster (domain.tif) defining the output grid and mask
#' @param out_file Output GeoTIFF file path
#' @param temp_directory Temporary working directory for downloads
#' @param verbose Logical for progress messages
#' @return SpatRaster of elevation on the domain grid

download_elevation_results <- function(
  task_id,
  domain_vector,
  domain_raster,
  temp_directory = "data/temp/appeears/elevation_nasadem/",
  verbose = TRUE
) {

  ensure_appeears_auth()
  # Ensure clean temp directory
  unlink(temp_directory, recursive = TRUE, force = TRUE)
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  # Clean terra temp
  terra_tmp <- file.path(getwd(), "data/temp/terra")
  unlink(terra_tmp, recursive = TRUE, force = TRUE)
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  # Reconnect to task and poll for completion
  if (verbose) message("Polling task ", task_id, " for completion...")
  
  # Poll for task completion using rs_list_task
  max_retries <- 120  # 2 hours at 60s intervals
  retry_count <- 0
  task_status <- "pending"
  
  repeat {
    retry_count <- retry_count + 1
    
    # Check task status
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
  
  # Load the GeoTIFF file
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

  # Cleanup temp downloads
  unlink(temp_directory, recursive = TRUE, force = TRUE)
  gc()
  unlink(terra_tmp, recursive = TRUE, force = TRUE)

  if (verbose) message("Elevation processing complete.")
  elev_masked
}




