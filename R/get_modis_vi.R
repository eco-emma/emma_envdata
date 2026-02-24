#' @title Submit MODIS NDVI and EVI request via AppEEARS
#' @description Submits an AppEEARS area request for MOD13Q1.061 and MYD13Q1.061 NDVI, EVI, and QA
#' (250m resolution, 16-day composite) over the provided domain. In prime mode downloads full history 
#' (2000-present), in update mode downloads from last available date to present.
#' @author EMMA Team
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param mode Either "prime" (2000-present) or "update" (from last available date to present)

#' @param start_date Optional. Start date for MODIS data (YYYY-MM-DD). If NULL, determined by mode.
#' @param end_date Optional. End date for MODIS data (YYYY-MM-DD). If NULL, determined by mode.
#' @param verbose Logical for progress messages
#' @return Character string with AppEEARS task ID

submit_modis_vi_task <- function(
  domain_vector,
  mode = c("prime", "update"),
  start_date = NULL,
  end_date = NULL,
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

  # Determine date range
  if (is.null(start_date) || is.null(end_date)) {
    if (mode == "prime") {
      start_date2 <- "2000-02-18"  # MODIS Terra start
      end_date2 <- as.character(Sys.Date())
    } else {  # update mode
      hist_file <- "data/target_outputs/modis_vi_historical.nc"
      if (file.exists(hist_file)) {
        tryCatch({
          r <- terra::rast(hist_file)
          tt <- terra::time(r)
          if (!is.null(tt) && length(tt) > 0) {
            last_date <- max(as.Date(tt))
            start_date2 <- as.character(last_date + 1)  # Start from next day
            end_date2 <- as.character(Sys.Date())
          } else {
            if (verbose) message("Could not extract time from historical file, using default start date")
            start_date2 <- "2000-02-18"
            end_date2 <- as.character(Sys.Date())
          }
        }, error = function(e) {
          if (verbose) message("Error reading historical file: ", conditionMessage(e), ". Using default start date")
          start_date2 <<- "2000-02-18"
          end_date2 <<- as.character(Sys.Date())
        })
      } else {
        if (verbose) message("Historical file not found, defaulting to 2000-02-18")
        start_date2 <- "2000-02-18"
        end_date2 <- as.character(Sys.Date())
      }
    }
    if (is.null(start_date)) start_date <- start_date2
    if (is.null(end_date)) end_date <- end_date2
  }

  if (verbose) message("AppEEARS request (", mode, " mode): ", start_date, " to ", end_date)

  # Resolve layer names dynamically
  ndvi_layer <- "250m_16_days_NDVI"
  evi_layer <- "250m_16_days_EVI"
  qa_layer <- "250m_16_days_VI_Quality"
  vi_date <- "250m_16_days_composite_day_of_the_year"
  
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
  terra_tmp <- file.path(getwd(), "data/temp/terra")
  
  # Check if NC files already exist in temp directory
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
  existing_nc_files <- list.files(temp_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)
  
  if (length(existing_nc_files) > 0) {
    if (verbose) message("Found existing NetCDF files in temp directory, skipping download")
  } else {
    # Ensure clean temp directory for new download
    unlink(temp_directory, recursive = TRUE, force = TRUE)
    dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

    # Clean terra temp
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
  }
  
  # Load the NetCDF files
  nc_paths <- list.files(temp_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)
  if (length(nc_paths) == 0) {
    stop("No NetCDF files downloaded from AppEEARS")
  }

  if (verbose) message("Reading ", length(nc_paths), " NetCDF files from AppEEARS")
  
  # Apply QA mask to EVI layers using the VI_Quality lookup table provided by AppEEARS
  qa_lookup <- list.files(
    temp_directory,
    pattern = "(VI-Quality-lookup).*\\.csv$",
    full.names = TRUE,
    recursive = TRUE
  )
  if (!length(qa_lookup)) {
    stop("QA lookup table (VI_Quality*.csv) not found in temp_directory; cannot mask EVI")
  }

  extract_keep <- function(path) {
    tab <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
    value_col <- names(tab)[grepl("value", tolower(names(tab)))][1]
    if (is.null(tab)) return(NULL)
    desc_col <- names(tab)[grepl("modland", tolower(names(tab)))][1]
    if (is.na(value_col) || is.na(desc_col)) return(NULL)
    vals <- tab[[value_col]][grepl("vi produced with good quality", tolower(tab[[desc_col]]))]
    vals[!is.na(vals)]
  }

  keep_values <- unique(unlist(lapply(qa_lookup, extract_keep)))
  if (!length(keep_values)) {
    stop("No 'good quality' entries found in any QA table; refusing to proceed")
  }

  mask_evi_with_qa <- function(stack) {
    vi_idx <- which(grepl("EVI|NDVI", names(stack), ignore.case = TRUE))
    evi_idx <- which(grepl("EVI", names(stack), ignore.case = TRUE))
    qa_idx  <- which(grepl("Quality", names(stack), ignore.case = TRUE))
    if (!length(vi_idx) || !length(qa_idx)) return(stack)
    if (length(evi_idx) != length(qa_idx)) {
      stop("EVI and QA band counts differ in AppEEARS file; cannot mask")
    }
    qa_r  <- stack[[qa_idx]]
    keep_mask <- terra::app(qa_r, function(x) x %in% keep_values)
    # Mask both VIs: NA where keep_mask is FALSE (bad QA), keep where TRUE (good QA)
    terra::mask(stack[[vi_idx]], keep_mask, maskvalue = FALSE)
  
  }

  raster_stack <- do.call(c, lapply(nc_paths, function(p) mask_evi_with_qa(terra::rast(p))))
  
  # Ensure we have a SpatRaster template (accept path or raster)
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster

  # Project to domain CRS/grid and mask to domain
  if (verbose) message("Projecting MODIS VI data to domain CRS/grid")
  
  # Resample each band to domain grid
  resampled_stack <- terra::project(raster_stack, domain_template, method = "average")
  
  # Mask to domain (NA where domain is NA)
  mask_layer <- if ("domain" %in% names(domain_template)) domain_template[["domain"]] else domain_template
  masked_stack <- terra::mask(resampled_stack, mask_layer)

  # Add pixel ID layer from domain grid
  if (!"pid" %in% names(domain_template)) {
    stop("domain_raster must include a 'pid' layer")
  }
  pid_raster <- terra::mask(domain_template[["pid"]], mask_layer)
  names(pid_raster) <- "pid"
  output_stack <- c(masked_stack, pid_raster)

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
    output_stack,
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
  if (mode == "update") {
    unlink(temp_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }

  if (verbose) message("MODIS VI data saved to: ", out_file)
  out_file
}


# ============================================================================
# MONTHLY DOWNLOAD APPROACH (Recommended for resilience & incremental updates)
# ============================================================================
# The following functions implement month-by-month downloading instead of
# single monolithic requests. This allows:
# - Parallel downloads (multiple months simultaneously)
# - Resilience to individual month failures
# - Natural incremental updates (download only missing months)
# - Better GitHub Actions compatibility (avoid 6-hour timeout with small requests)
# ============================================================================


#' @title Submit 16-day MODIS VI request via AppEEARS
#' @description Submits an AppEEARS area request for a single 16-day window of MOD13Q1.061 and MYD13Q1.061
#' NDVI, EVI, and QA (250m resolution, 16-day composite).
#' @author EMMA Team
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param window_start Start date for the 16-day window (YYYY-MM-DD)
#' @param window_end End date for the 16-day window (YYYY-MM-DD)
#' @param verbose Logical for progress messages
#' @return Character string with AppEEARS task ID
#' @details Uses same domain transformation and layer resolution as submit_modis_vi_task(),
#' but for a single 16-day window instead of the full date range.
#' @export
submit_modis_vi_window <- function(
  domain_vector,
  window_start,
  window_end,
  verbose = TRUE
) {

  # Convert domain vector to sf, fix geometry, simplify, merge, and reproject to WGS84
  domain_sf <- st_as_sf(domain_vector) %>%
    st_simplify(dTolerance = 100, preserveTopology = TRUE) %>%
    st_buffer(0) %>%
    st_make_valid() %>%
    st_transform(crs = 4326) %>%
    geojsonsf::sf_geojson(simplify = FALSE) %>%
    jsonlite::fromJSON()

  # Validate dates
  window_start <- as.Date(window_start)
  window_end <- as.Date(window_end)
  
  if (verbose) {
    message("AppEEARS MODIS VI 16-day window request: ", format(window_start, "%Y-%m-%d"), 
            " to ", format(window_end, "%Y-%m-%d"))
  }

  # Resolve layer names dynamically (same as full-range version)
  ndvi_layer <- "250m_16_days_NDVI"
  evi_layer <- "250m_16_days_EVI"
  qa_layer <- "250m_16_days_VI_Quality"
  date_layer <- "_250m_16_days_composite_day_of_the_year"
  
  try({
    lyr <- appeears::rs_layers("MOD13Q1.061")
    cand_cols <- intersect(c("Layer", "Name", "layer", "name"), names(lyr))
    if (length(cand_cols)) {
      vals <- unlist(lapply(cand_cols, function(cc) lyr[[cc]]))
      ndvi_cand <- vals[grepl("NDVI", vals, ignore.case = TRUE)][1]
      evi_cand <- vals[grepl("EVI", vals, ignore.case = TRUE)][1]
      qa_cand <- vals[grepl("VI.*Quality|Quality", vals, ignore.case = TRUE)][1]
      date_cand <- vals[grepl("composite_day_of_the_year", vals, ignore.case = TRUE)][1]
      if (!is.na(ndvi_cand)) ndvi_layer <- ndvi_cand
      if (!is.na(evi_cand)) evi_layer <- evi_cand
      if (!is.na(qa_cand)) qa_layer <- qa_cand
      if (!is.na(date_cand)) date_layer <- date_cand
    }
  }, silent = TRUE)

  if (verbose) message("Using layers: ", ndvi_layer, ", ", evi_layer, ", ", qa_layer, ", ", date_layer)

  # Build request payload for single 16-day window
  req <- list(
    task_type = "area",
    task_name = paste0("MODIS_VI_", format(window_start, "%Y%m%d"), "_", format(Sys.time(), "%H%M%S")),
    params = list(
      dates = list(list(
        startDate = format(window_start, "%m-%d-%Y"),
        endDate = format(window_end, "%m-%d-%Y")
      )),
      layers = list(
        # MOD13Q1.061 (Terra)
        list(product = "MOD13Q1.061", layer = ndvi_layer),
        list(product = "MOD13Q1.061", layer = evi_layer),
        list(product = "MOD13Q1.061", layer = qa_layer),
        list(product = "MOD13Q1.061", layer = date_layer),
        # MYD13Q1.061 (Aqua)
        list(product = "MYD13Q1.061", layer = ndvi_layer),
        list(product = "MYD13Q1.061", layer = evi_layer),
        list(product = "MYD13Q1.061", layer = qa_layer),
        list(product = "MYD13Q1.061", layer = date_layer)
      ),
      output = list(
        format = list(type = "netcdf4"),
        projection = "native"
      ),
      geo = domain_sf
    )
  )

  # Submit task
  if (verbose) message("Submitting AppEEARS MODIS VI 16-day window task...")
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


#' @title Download and process MODIS VI for a single 16-day window
#' @description Polls for completion of AppEEARS task and downloads results,
#' then processes into a NetCDF file with NDVI, EVI, and QA variables for that 16-day window.
#' @author EMMA Team
#' @param task_id Character string with AppEEARS task ID
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param domain_raster A SpatRaster (domain.tif) defining the output grid and mask
#' @param window_start Start date for 16-day window (YYYY-MM-DD)
#' @param out_dir Output directory for 16-day window NetCDF files
#' @param temp_directory Temporary working directory for downloads
#' @param verbose Logical for progress messages
#' @return Character path to output NetCDF file (format: modis_vi_YYYYMMDD_16d.nc)
#' @details
#' Implements AppEEARS polling with timeout protection and QA masking.
#' Output is a single 16-day window of data; multiple outputs are aggregated separately.
#' @export
download_modis_vi_window <- function(
  task_id,
  domain_vector,
  domain_raster,
  window_start,
  out_dir = "data/target_outputs/modis_vi_windows",
  temp_directory = "data/temp/raw_data/modis_vi_window/",
  cleanup = TRUE,
  verbose = TRUE
) {
  
  terra_tmp <- file.path(getwd(), "data/temp/terra")
  window_start <- as.Date(window_start)
  date_str <- format(window_start, "%Y%m%d")
  
  # Clean and create temp directory
  unlink(temp_directory, recursive = TRUE, force = TRUE)
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
  
  # Clean terra temp
  unlink(terra_tmp, recursive = TRUE, force = TRUE)
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  # Poll for task completion
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

  # Download results
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
    # No data available for this window (common for edge cases, polar regions, etc.)
    if (verbose) message("No NetCDF files returned from AppEEARS for window ", date_str, " - writing skip marker")
    
    # Create a lightweight skip marker file instead of fake data
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    skip_file <- file.path(out_dir, paste0("modis_vi_", date_str, "_16d.skip"))
    
    writeLines(
      c(
        paste("Window:", date_str),
        paste("Task ID:", task_id),
        paste("Reason: No NetCDF files returned from AppEEARS"),
        paste("Note: Possible causes - polar region, cloud cover, instrument malfunction, or outside data availability period"),
        paste("Timestamp:", Sys.time())
      ),
      skip_file
    )
    
    if (verbose) message("Created skip marker: ", skip_file)
    
    # Cleanup
    if(cleanup) {
      unlink(temp_directory, recursive = TRUE, force = TRUE)
      gc()
      unlink(terra_tmp, recursive = TRUE, force = TRUE)
    }
    
    return(skip_file)
  }

  if (verbose) message("Reading ", length(nc_paths), " NetCDF files from AppEEARS")
  
  # Apply QA mask to VI layers
  qa_lookup <- list.files(
    temp_directory,
    pattern = "(VI-Quality-lookup).*\\.csv$",
    full.names = TRUE,
    recursive = TRUE
  )
  if (!length(qa_lookup)) {
    stop("QA lookup table (VI_Quality*.csv) not found in temp_directory; cannot mask VI data")
  }

  extract_keep <- function(path) {
    tab <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
    value_col <- names(tab)[grepl("value", tolower(names(tab)))][1]
    if (is.null(tab)) return(NULL)
    desc_col <- names(tab)[grepl("modland", tolower(names(tab)))][1]
    if (is.na(value_col) || is.na(desc_col)) return(NULL)
    vals <- tab[[value_col]][grepl("vi produced with good quality", tolower(tab[[desc_col]]))]
    vals[!is.na(vals)]
  }

  keep_values <- unique(unlist(lapply(qa_lookup, extract_keep)))
  if (!length(keep_values)) {
    stop("No 'good quality' entries found in any QA table; refusing to proceed")
  }

  mask_vi_with_qa <- function(stack, domain_template) {
    evi_idx <- which(grepl("EVI", names(stack), ignore.case = TRUE))
    ndvi_idx <- which(grepl("NDVI", names(stack), ignore.case = TRUE))
    qa_idx  <- which(grepl("Quality", names(stack), ignore.case = TRUE))
    date_idx <- which(grepl("composite_day_of_the_year", names(stack), ignore.case = TRUE))
    if (!length(evi_idx) || !length(qa_idx)) return(stack)
    if (length(evi_idx) != length(qa_idx)) {
      stop("EVI and QA band counts differ in AppEEARS file; cannot mask")
    }
    qa_r  <- stack[[qa_idx]]
    keep_mask <- terra::app(qa_r, function(x) x %in% keep_values)
    # mask both VIs: NA where keep_mask is FALSE (bad QA), keep where TRUE (good QA), then project to domain grid, then scale NDVI/EVI by 100 for 8-bit storage
    evi <- terra::mask(stack[[evi_idx]], keep_mask, maskvalue = FALSE) |> terra::project(domain_template, method = "average") |> terra::app(function(x) x * 100)
    ndvi <- terra::mask(stack[[ndvi_idx]], keep_mask, maskvalue = FALSE) |> terra::project(domain_template, method = "average") |> terra::app(function(x) x * 100)
    date <- terra::mask(stack[[date_idx]], keep_mask, maskvalue = FALSE) |> terra::project(domain_template, method = "mode")
    c(date, ndvi, evi)  # Ensure date layer is included and masked; NDVI/EVI scaled by 100
  }

  # Project to domain grid
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster

  raster_stack <- do.call(c, lapply(nc_paths, function(p) mask_vi_with_qa(terra::rast(p), domain_template)))
  
  # Mask to domain
  mask_layer <- if ("domain" %in% names(domain_template)) domain_template[["domain"]] else domain_template
  masked_stack <- terra::mask(raster_stack, mask_layer)

  # Add pixel ID layer
  if (!"pid" %in% names(domain_template)) {
    stop("domain_raster must include a 'pid' layer")
  }
  pid_raster <- terra::mask(domain_template[["pid"]], mask_layer)
  names(pid_raster) <- "pid"
  output_stack <- c(masked_stack, pid_raster)

  # Write 16-day window output
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, paste0("modis_vi_", date_str, "_16d.nc"))
  
  unlink(out_file)

  if (verbose) message("Writing NetCDF: ", out_file)
  
  terra::writeCDF(
    output_stack,
    filename = out_file,
    overwrite = TRUE,
    compression = 9
  )

  # Add global attributes
  nc <- ncdf4::nc_open(out_file, write = TRUE)
  ncdf4::ncatt_put(nc, 0, "title", paste0("MODIS NDVI and EVI for 16-day window starting ", date_str, " resampled to domain"))
  ncdf4::ncatt_put(nc, 0, "source", "MOD13Q1.061 and MYD13Q1.061 (250m, 16-day composite) via AppEEARS")
  ncdf4::ncatt_put(nc, 0, "history", paste0("created: ", Sys.time()))
  ncdf4::ncatt_put(nc, 0, "Conventions", "CF-1.8")
  ncdf4::ncatt_put(nc, 0, "note_scaling", "NDVI and EVI values are scaled by 100 for 8-bit storage. Divide by 100 to recover original values.")
  ncdf4::ncatt_put(nc, 0, "scale_factor_ndvi_evi", 0.01)
  ncdf4::nc_close(nc)

  # Cleanup
  if(cleanup) {
    unlink(temp_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }

  if (verbose) message("MODIS VI 16-day window data saved to: ", out_file)
  out_file
}
