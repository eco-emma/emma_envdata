#' @title Download NASADEM elevation via AppEEARS and resample to domain
#' @description Submits an AppEEARS area request for NASADEM elevation data
#' over the provided domain polygon, downloads, and resamples to domain grid.
#' @author EMMA Team
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param domain_raster A SpatRaster (domain.tif) defining the output grid and mask
#' @param temp_directory Temporary working directory for downloads
#' @param verbose Logical for progress messages
#' @return SpatRaster with elevation resampled to domain, with metadata

get_release_elevation_nasadem_appears <- function(
  domain_vector,
  domain_raster,
  temp_directory = "data/temp/raw_data/elevation_nasadem/",
  verbose = TRUE
) {

  # Package checks
  required_pkgs <- c("appeears", "terra", "sf", "lubridate", "jsonlite")
  missing <- required_pkgs[!sapply(required_pkgs, requireNamespace, quietly = TRUE)]
  if (length(missing)) {
    stop("Required packages missing: ", paste(missing, collapse = ", "))
  }

  # Ensure clean temp directory
  if (dir.exists(temp_directory)) {
    unlink(temp_directory, recursive = TRUE, force = TRUE)
  }
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  # Clean terra temp
  terra_tmp <- file.path(getwd(), "data/temp/terra")
  unlink(terra_tmp, recursive = TRUE, force = TRUE)
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  # Convert domain vector to sf and reproject to WGS84 (required by AppEEARS)
  domain_sf <- st_as_sf(domain_vector)
  domain_wgs84 <- st_transform(domain_sf, crs = 4326)
  
  # Write to GeoJSON and read back as plain list (avoids geo_list serialization issues)
  aoi_path <- file.path(temp_directory, "aoi.geojson")
  suppressWarnings(sf::st_write(domain_wgs84, aoi_path, driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE))
  aoi_json <- jsonlite::read_json(aoi_path, simplifyVector = FALSE)

  if (verbose) message("Submitting AppEEARS NASADEM request over domain polygon")

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
        format = list(type = "netcdf4"),
        projection = "native"
      ),
      geo = aoi_json
    )
  )

  # Convert request to JSON string (rs_request/task$download expect JSON text)
  req_json <- jsonlite::toJSON(req, auto_unbox = TRUE)

  # Submit and poll for completion
  if (verbose) message("Submitting AppEEARS task...")
  task <- appeears::rs_request(
    request = req_json, 
    user = Sys.getenv("EARTHDATA_USER"),
    path = temp_directory,
    transfer = FALSE,
    verbose = verbose
  )
  
  if (verbose) message("Task submitted: ", task$get_task_id())

  # Poll for completion using task object methods
  max_retries <- 60
  retry_count <- 0
  
  repeat {
    retry_count <- retry_count + 1
    task$update_status(verbose = FALSE)
    
    if (task$is_success()) {
      if (verbose) message("Task completed successfully")
      break
    }
    
    if (task$is_failed()) {
      stop("AppEEARS task failed")
    }
    
    if (retry_count >= max_retries) {
      stop("Task polling timed out after ", max_retries * 10, " seconds")
    }
    
    if (verbose) message("Task status: ", task$get_status(), " (", retry_count, "/", max_retries, ")")
    Sys.sleep(10)
  }

  # Download results
  if (verbose) message("Downloading files for task: ", task$get_task_id())
  task$download(verbose = verbose)
  
  # Load the NetCDF file
  nc_paths <- list.files(temp_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)
  if (length(nc_paths) == 0) {
    stop("No NetCDF files downloaded from AppEEARS")
  }

  if (verbose) message("Reading elevation data from: ", nc_paths[1])
  elev_raster <- terra::rast(nc_paths[grepl(nc_paths, pattern = "SRTMGL3_NC.003_90m_aid0001.nc")])

  # Resample to domain grid using bilinear interpolation
  if (verbose) message("Resampling elevation to domain grid")
  elev_resampled <- terra::resample(elev_raster, domain_raster, method = "average")

  # Mask to domain (NA where domain is NA)
  elev_masked <- terra::mask(elev_resampled, domain_raster)

  # Set metadata
  names(elev_masked) <- "elevation"
  units(elev_masked) <- "meters"

  metags(elev_masked) <- c(
    "elevation_long_name" = "NASADEM elevation above mean sea level",
    "elevation_source" = "NASADEM_HGT.001 via AppEEARS",
    "date_generated" = as.character(Sys.time()),
    "crs" = as.character(crs(elev_masked)),
    "Conventions" = "CF-1.8"
  )

  # Cleanup
  unlink(temp_directory, recursive = TRUE, force = TRUE)
  gc()
  unlink(terra_tmp, recursive = TRUE, force = TRUE)

  if (verbose) message("Elevation data ready")
  elev_masked
}




