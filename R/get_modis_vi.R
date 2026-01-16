#' @title Submit MODIS NDVI and EVI request via AppEEARS
#' @description Submits an AppEEARS area request for MOD13Q1.061 and MYD13Q1.061 NDVI, EVI, and QA
#' (250m resolution, 16-day composite) over the provided domain. In prime mode downloads full history 
#' (2000-present), in update mode downloads from last available date to present.
#' @author EMMA Team
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param mode Either "prime" (2000-present) or "update" (from last available date to present)
#' @param verbose Logical for progress messages
#' @return Character string with AppEEARS task ID

submit_modis_vi_task <- function(
  domain_vector,
  mode = c("prime", "update"),
  verbose = TRUE
) {
  mode <- match.arg(mode)
  
  # Convert domain vector to sf, fix geometry, simplify, merge, and reproject to WGS84 (required by AppEEARS)
  domain_sf <- st_as_sf(domain_vector) %>%
    st_simplify(dTolerance = 100, preserveTopology = TRUE) %>%
    st_buffer(0) %>%
    st_make_valid() %>%
    st_transform(crs = 4326) %>%
    geojsonsf::sf_geojson(simplify = FALSE) %>%
    jsonlite::fromJSON()

  # Determine date range based on mode
  if (mode == "prime") {
    start_date <- "2000-02-18"  # MODIS Terra start
    end_date <- as.character(Sys.Date())
  } else {  # update mode
    # Check the last date in the historical file
    hist_file <- "data/target_outputs/modis_vi_historical.nc"
    if (file.exists(hist_file)) {
      tryCatch({
        r <- terra::rast(hist_file)
        tt <- terra::time(r)
        if (!is.null(tt) && length(tt) > 0) {
          last_date <- max(as.Date(tt))
          start_date <- as.character(last_date + 1)  # Start from next day
          end_date <- as.character(Sys.Date())
        } else {
          if (verbose) message("Could not extract time from historical file, using default start date")
          start_date <- "2000-02-18"
          end_date <- as.character(Sys.Date())
        }
      }, error = function(e) {
        if (verbose) message("Error reading historical file: ", conditionMessage(e), ". Using default start date")
        start_date <<- "2000-02-18"
        end_date <<- as.character(Sys.Date())
      })
    } else {
      if (verbose) message("Historical file not found, defaulting to 2000-02-18")
      start_date <- "2000-02-18"
      end_date <- as.character(Sys.Date())
    }
  }

  if (verbose) message("AppEEARS request (", mode, " mode): ", start_date, " to ", end_date)

  # Resolve layer names dynamically
  ndvi_layer <- "250m_16_days_NDVI"
  evi_layer <- "250m_16_days_EVI"
  qa_layer <- "250m_16_days_VI_Quality"
  
  try({
    lyr <- appeears::rs_layers("MOD13Q1.061")
    cand_cols <- intersect(c("Layer", "Name", "layer", "name"), names(lyr))
    if (length(cand_cols)) {
      vals <- unlist(lapply(cand_cols, function(cc) lyr[[cc]]))
      ndvi_cand <- vals[grepl("NDVI", vals, ignore.case = TRUE)][1]
      evi_cand <- vals[grepl("EVI", vals, ignore.case = TRUE)][1]
      qa_cand <- vals[grepl("VI.*Quality|Quality", vals, ignore.case = TRUE)][1]
      if (!is.na(ndvi_cand)) ndvi_layer <- ndvi_cand
      if (!is.na(evi_cand)) evi_layer <- evi_cand
      if (!is.na(qa_cand)) qa_layer <- qa_cand
    }
  }, silent = TRUE)

  if (verbose) message("Using layers: ", ndvi_layer, ", ", evi_layer, ", ", qa_layer)

  # Build request payload - NDVI, EVI, and QA from both MOD13Q1.061 (Terra) and MYD13Q1.061 (Aqua) in one request
  req <- list(
    task_type = "area",
    task_name = paste0("MODIS_VI_", mode, "_", format(Sys.time(), "%Y%m%d%H%M%S")),
    params = list(
      dates = list(list(
        startDate = format(as.Date(start_date), "%m-%d-%Y"),
        endDate = format(as.Date(end_date), "%m-%d-%Y")
      )),
      layers = list(
        # MOD13Q1.061 (Terra)
        list(product = "MOD13Q1.061", layer = ndvi_layer),
        list(product = "MOD13Q1.061", layer = evi_layer),
        list(product = "MOD13Q1.061", layer = qa_layer),
        # MYD13Q1.061 (Aqua)
        list(product = "MYD13Q1.061", layer = ndvi_layer),
        list(product = "MYD13Q1.061", layer = evi_layer),
        list(product = "MYD13Q1.061", layer = qa_layer)
      ),
      output = list(
        format = list(type = "netcdf4"),
        projection = "native"
      ),
      geo = domain_sf
    )
  )

  # Submit task
  if (verbose) message("Submitting AppEEARS MODIS VI task...")
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


#' @title Download and process MODIS NDVI and EVI from AppEEARS
#' @description Polls for completion of AppEEARS task and downloads results,
#' then processes into a NetCDF file with NDVI, EVI, and QA variables.
#' In prime mode writes to historical file, in update mode writes to update file.
#' @author EMMA Team
#' @param task_id Character string with AppEEARS task ID (from submit_modis_vi_task)
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param domain_raster A SpatRaster (domain.tif) defining the output grid and mask
#' @param mode Either "prime" or "update"
#' @param out_dir Output directory (default: "data/target_outputs")
#' @param temp_directory Temporary working directory for downloads
#' @param verbose Logical for progress messages
#' @return Character path to output NetCDF file

download_modis_vi_results <- function(
  task_id,
  domain_vector,
  domain_raster,
  mode = c("prime", "update"),
  out_dir = "data/target_outputs",
  temp_directory = "data/temp/raw_data/modis_vi/",
  verbose = TRUE
) {
  mode <- match.arg(mode)
  
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
  
  # Load the NetCDF files
  nc_paths <- list.files(temp_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)
  if (length(nc_paths) == 0) {
    stop("No NetCDF files downloaded from AppEEARS")
  }

  if (verbose) message("Reading ", length(nc_paths), " NetCDF files from AppEEARS")
  
  # Read all layers from the AppEEARS output
  raster_stack <- terra::rast(nc_paths)
  
  # Ensure we have a SpatRaster template (accept path or raster)
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster

  # Project to domain CRS/grid and mask to domain
  if (verbose) message("Projecting MODIS VI data to domain CRS/grid")
  
  # Resample each band to domain grid
  resampled_stack <- terra::project(raster_stack, domain_template, method = "average")
  
  # Mask to domain (NA where domain is NA)
  mask_layer <- if ("domain" %in% names(domain_template)) domain_template[["domain"]] else domain_template
  masked_stack <- terra::mask(resampled_stack, mask_layer)

  # Determine output filename based on mode
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (mode == "prime") {
    out_file <- file.path(out_dir, "modis_vi_historical.nc")
  } else {
    out_file <- file.path(out_dir, "modis_vi_update.nc")
  }
  
  unlink(out_file)

  if (verbose) message("Writing NetCDF: ", out_file)
  
  # Use terra::writeCDF to write the full stack with metadata
  terra::writeCDF(
    masked_stack,
    filename = out_file,
    overwrite = TRUE,
    compression = 9
  )

  # Add global attributes
  nc <- ncdf4::nc_open(out_file, write = TRUE)
  ncdf4::ncatt_put(nc, 0, "title", paste0("MODIS NDVI and EVI (", mode, " mode) resampled to domain"))
  ncdf4::ncatt_put(nc, 0, "source", "MOD13Q1.061 and MYD13Q1.061 (250m, 16-day composite) via AppEEARS")
  ncdf4::ncatt_put(nc, 0, "history", paste0("created: ", Sys.time()))
  ncdf4::ncatt_put(nc, 0, "Conventions", "CF-1.8")
  ncdf4::nc_close(nc)

  # Cleanup
  unlink(temp_directory, recursive = TRUE, force = TRUE)
  gc()
  unlink(terra_tmp, recursive = TRUE, force = TRUE)

  if (verbose) message("MODIS VI data saved to: ", out_file)
  out_file
}
