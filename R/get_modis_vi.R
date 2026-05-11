#' @title Generate monthly sequences for MODIS/VIIRS VI downloads
#' @description Creates a data frame of all months to download based on a date range.
#' @param start_date Start date (YYYY-MM-DD), default 2000-02-18 (MODIS Terra start)
#' @param end_date End date (YYYY-MM-DD), default today
#' @return Data frame with columns: month_start, month_end, date_str (YYYYMM format)
#' @export
generate_monthly_sequence <- function(start_date = "2000-02-18", end_date = NULL) {
  if (is.null(end_date)) {
    end_date <- Sys.Date()
  }
  
  start_date <- as.Date(start_date)
  end_date <- as.Date(end_date)
  
  # Generate all month starts from beginning month
  month_starts <- seq(as.Date(cut(start_date, "month")), end_date, by = "month")
  month_ends <- c(month_starts[-1] - 1, end_date)
  
  # Trim if extends past end_date
  valid_idx <- month_starts <= end_date
  month_starts <- month_starts[valid_idx]
  month_ends <- month_ends[valid_idx]
  
  data.frame(
    month_start = month_starts,
    month_end = pmin(month_ends, end_date),
    date_str = format(month_starts, "%Y%m"),
    row.names = NULL
  )
}


#' @title Identify missing monthly submissions from output directory
#' @description Compares generated monthly sequence with existing downloaded NetCDF files
#' @param output_dir Directory containing downloaded raw NetCDF files
#' @param dataset Name of dataset (e.g., "modis_vi", "viirs_vi") used in filename pattern
#' @param start_date Start date for sequence (YYYY-MM-DD)
#' @param end_date End date for sequence (YYYY-MM-DD), default is today
#' @return Data frame of months that haven't been downloaded yet
#' @export
identify_missing_vi <- function(output_dir, dataset = "modis_vi", start_date = "2000-02-18", end_date = NULL) {
  
  # Create full monthly sequence
  all_months <- generate_monthly_sequence(start_date, end_date)
  
  # Check which ones already exist as downloaded NetCDF files OR skip markers.
  # A .skip file means AppEEARS returned no data for that month (e.g. pre-launch,
  # complete cloud cover) — it is not a failure, so do not retry it.
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  pattern_nc   <- paste0("^", dataset, "_\\d{6}_monthly\\.nc$")
  pattern_skip <- paste0("^", dataset, "_\\d{6}_monthly\\.skip$")
  existing_nc   <- list.files(output_dir, pattern = pattern_nc)
  existing_skip <- list.files(output_dir, pattern = pattern_skip)
  existing_files <- c(existing_nc, existing_skip)
  
  if (length(existing_files) == 0) {
    return(all_months)
  }
  
  # Extract YYYYMM from existing files and convert to match date_str
  # Format: <dataset>_<YYYYMM>_monthly.nc
  pattern_prefix <- paste0("^", dataset, "_")
  existing_dates <- existing_files %>%
    gsub(pattern_prefix, "", .) %>%
    gsub("_monthly\\.nc$", "", .)
  
  # Return only missing months
  missing <- all_months[!all_months$date_str %in% existing_dates, ]
  
  if (nrow(missing) == 0) {
    message("All months already downloaded in ", output_dir)
    return(data.frame())
  }
  
  missing
}



#' @title Submit monthly MODIS VI request via AppEEARS
#' @description Submits an AppEEARS area request for MOD13A1.061 and MYD13A1.061
#' EVI, and QA (500m resolution, 16-day composite) for a monthly period.
#' @author EMMA Team
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param month_start Start date for the month (YYYY-MM-DD)
#' @param month_end End date for the month (YYYY-MM-DD)
#' @param verbose Logical for progress messages
#' @return Character string with AppEEARS task ID
#' @export
submit_modis_vi <- function(
  domain_vector,
  month_start,
  month_end,
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
  month_start <- as.Date(month_start)
  month_end <- as.Date(month_end)
  
  if (verbose) {
    message("AppEEARS MODIS VI monthly request: ", format(month_start, "%Y-%m-%d"), 
            " to ", format(month_end, "%Y-%m-%d"))
  }

  # Resolve layer names dynamically (same as full-range version)
  evi_layer <- "_500m_16_days_EVI"
  qa_layer <- "_500m_16_days_VI_Quality"
  date_layer <- "_500m_16_days_composite_day_of_the_year"
  
  try({
    lyr <- appeears::rs_layers("MOD13A1.061")
    cand_cols <- intersect(c("Layer", "Name", "layer", "name"), names(lyr))
    if (length(cand_cols)) {
      vals <- unlist(lapply(cand_cols, function(cc) lyr[[cc]]))
      evi_cand <- vals[grepl("EVI", vals, ignore.case = TRUE)][1]
      qa_cand <- vals[grepl("VI.*Quality|Quality", vals, ignore.case = TRUE)][1]
      date_cand <- vals[grepl("composite_day_of_the_year", vals, ignore.case = TRUE)][1]
      if (!is.na(evi_cand)) evi_layer <- evi_cand
      if (!is.na(qa_cand)) qa_layer <- qa_cand
      if (!is.na(date_cand)) date_layer <- date_cand
    }
  }, silent = TRUE)

  if (verbose) message("Using layers: ", evi_layer, ", ", qa_layer, ", ", date_layer)

  # Build request payload for monthly period
  req <- list(
    task_type = "area",
    task_name = paste0("MODIS_VI_", format(month_start, "%Y%m"), "_", format(Sys.time(), "%H%M%S")),
    params = list(
      dates = list(list(
        startDate = format(month_start, "%m-%d-%Y"),
        endDate = format(month_end, "%m-%d-%Y")
      )),
      layers = list(
        # MOD13A1.061 (Terra)
        list(product = "MOD13A1.061", layer = evi_layer),
        list(product = "MOD13A1.061", layer = qa_layer),
        list(product = "MOD13A1.061", layer = date_layer),
        # MYD13A1.061 (Aqua)
        list(product = "MYD13A1.061", layer = evi_layer),
        list(product = "MYD13A1.061", layer = qa_layer),
        list(product = "MYD13A1.061", layer = date_layer)
      ),
      output = list(
        format = list(type = "netcdf4"),
        projection = "native"
      ),
      geo = domain_sf
    )
  )

  # Submit task
  if (verbose) message("Submitting AppEEARS MODIS VI monthly task...")
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


#' @title Download MODIS VI NetCDF files from AppEEARS
#' @description Polls for completion of AppEEARS task and downloads results.
#' Separates I/O from computation for independent parallelization.
#' @author EMMA Team
#' @param task_id Character string with AppEEARS task ID
#' @param month_start Start date for monthly period (YYYY-MM-DD)
#' @param temp_directory Temporary working directory for downloads
#' @param cleanup Logical to delete temporary files after processing. Defaults to TRUE on GitHub Actions (GITHUB_ACTIONS env var), FALSE on local execution.
#' @param verbose Logical for progress messages
#' @return Character path to temporary directory containing downloaded NetCDF files and metadata
#' @export
download_modis_vi_netcdf <- function(
  task_id,
  month_start,
  temp_directory = "data/temp/raw_data/modis_vi_netcdf/",
  cleanup = Sys.getenv("GITHUB_ACTIONS") == "true",
  verbose = TRUE
) {
  
  month_start <- as.Date(month_start)
  yyyymm <- format(month_start, "%Y%m")
  
  # Check if this month was already downloaded (marker file exists)
  cache_dir <- "data/target_outputs/modis_vi"
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  cache_file <- file.path(cache_dir, paste0("modis_vi_", yyyymm, "_monthly.nc"))
  
  if (file.exists(cache_file)) {
    if (verbose) message("Marker file found for ", yyyymm, " - skipping AppEEARS download")
    # Create minimal temp directory so netcdf_to_parquet gets valid path
    dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
    return(temp_directory)
  }
  
  # Each branch gets its own subdirectory to avoid race conditions when
  # parallel tar_make_future() workers run multiple months simultaneously.
  temp_directory <- file.path(temp_directory, yyyymm)
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

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
  
  # Check if NetCDF files were downloaded
  nc_paths <- list.files(temp_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)
  if (length(nc_paths) == 0) {
    if (verbose) message("No NetCDF files returned from AppEEARS for month ", yyyymm)
    # Write a skip marker so identify_missing_vi() won't retry this month.
    # The marker name matches the pattern recognised by identify_missing_vi().
    skip_file <- file.path(cache_dir, paste0("modis_vi_", yyyymm, "_monthly.skip"))
    writeLines(
      c(paste("Month:", yyyymm), "Reason: AppEEARS returned no NetCDF files", paste("Timestamp:", Sys.time())),
      con = skip_file
    )
    if (verbose) message("Created skip marker: ", skip_file)
    if (cleanup) unlink(temp_directory, recursive = TRUE, force = TRUE)
    return(skip_file)
  }
  
  if (verbose) message("Downloaded ", length(nc_paths), " NetCDF files to ", temp_directory)
  
  # Create persistent marker file to avoid re-downloading this month
  # Check which months have already been downloaded by looking for marker files
  cache_dir <- "data/target_outputs/modis_vi"
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  cache_file <- file.path(cache_dir, paste0("modis_vi_", yyyymm, "_monthly.nc"))
  
  # Write a simple marker file (just needs to exist to be detected by identify_missing_vi)
  cat("", file = cache_file)
  
  if (verbose) message("Created download marker: ", cache_file)
  
  # Return temp directory so netcdf_to_parquet() can access the actual files
  return(temp_directory)
}


#' @title Extract QA-good values from AppEEARS lookup table
#' @description Helper function to extract pixel QA flag values that meet quality criteria.
#' Filters based on: VI quality, no adjacent cloud, no shadow, no snow, over land, low aerosol.
#' @param qa_lookup_files Character vector of paths to VI Quality lookup CSV files
#' @return Integer vector of QA flag values that pass all quality filters
#' @keywords internal
extract_keep_qa_values <- function(qa_lookup_files) {
  
  extract_keep <- function(path) {
    tab <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
    if (is.null(tab)) return(NULL)
    
    # Find required columns (case-insensitive)
    value_col <- names(tab)[grepl("^value$", tolower(names(tab)))][1]
    modland_col <- names(tab)[grepl("modland", tolower(names(tab)))][1]
    adj_cloud_col <- names(tab)[grepl("adjacent.*cloud", tolower(names(tab)))][1]
    snow_col <- names(tab)[grepl("possible.*snow|snow.*ice", tolower(names(tab)))][1]
    shadow_col <- names(tab)[grepl("possible.*shadow", tolower(names(tab)))][1]
    land_col <- names(tab)[grepl("land/water|land.*water", tolower(names(tab)))][1]
    aerosol_col <- names(tab)[grepl("aerosol", tolower(names(tab)))][1]
    
    # Check all required columns are present
    required_cols <- c(value_col, modland_col, adj_cloud_col, snow_col, shadow_col, land_col, aerosol_col)
    if (any(is.na(required_cols))) {
      warning("QA lookup missing required columns. Found: value=", !is.na(value_col), 
              ", modland=", !is.na(modland_col), ", adj_cloud=", !is.na(adj_cloud_col),
              ", snow=", !is.na(snow_col), ", shadow=", !is.na(shadow_col),
              ", land=", !is.na(land_col), ", aerosol=", !is.na(aerosol_col))
      return(NULL)
    }
    
    # Filter for pixels that meet ALL QA criteria:
    # 1. VI produced with good quality
    # 2. No adjacent cloud detected
    # 3. No cloud shadow
    # 4. No snow/ice
    # 5. Over land (not ocean or water)
    # 6. Not high aerosol loading
    keep <- (grepl("vi produced", tolower(tab[[modland_col]]))) &
            (grepl("^no$", tolower(tab[[adj_cloud_col]]))) &
            (grepl("^no$", tolower(tab[[shadow_col]]))) &
            (grepl("^no$", tolower(tab[[snow_col]]))) &
            (grepl("land", tolower(tab[[land_col]]))) &
            (!grepl("high", tolower(tab[[aerosol_col]])))
    
    tab[[value_col]][keep & !is.na(tab[[value_col]])]
  }
  
  unique(unlist(lapply(qa_lookup_files, extract_keep)))
}


#' @title Extract MODIS VI observations from single NetCDF file
#' @description Processes one NetCDF file: detects Terra/Aqua product from metadata, applies QA masking,
#' reprojects to domain grid, and extracts observations in tabular format.
#' @param nc_path Character path to NetCDF file
#' @param domain_template SpatRaster defining output grid and CRS
#' @param keep_values Integer vector of QA flag values that pass quality criteria
#' @param month_start Start date for monthly period (YYYY-MM-DD), used for date conversion
#' @param verbose Logical for progress messages
#' @return Tibble with columns: pid, date, variable, value. Returns NULL if no valid observations found.
#' @keywords internal
extract_vi_observations <- function(
  nc_path,
  domain_template,
  keep_values,
  month_start,
  verbose = TRUE
) {
  
  # Load raster from NetCDF
  rast_obj <- terra::rast(nc_path)
  
  # Detect product (Terra=MOD13 vs Aqua=MYD13) from NetCDF global attributes
  product_name <- "terra"
  sensor_id <- 1L
  
  tryCatch({
    nc <- ncdf4::nc_open(nc_path)
    global_attrs <- names(ncdf4::ncatt_get(nc, 0))
    
    for (attr_name in global_attrs) {
      attr_val <- ncdf4::ncatt_get(nc, 0, attr_name)$value
      if (!is.null(attr_val) && is.character(attr_val)) {
        if (grepl("MYD13", attr_val, ignore.case = TRUE)) {
          product_name <- "aqua"
          sensor_id <- 2L
          break
        } else if (grepl("MOD13", attr_val, ignore.case = TRUE)) {
          product_name <- "terra"
          sensor_id <- 1L
          break
        }
      }
    }
    ncdf4::nc_close(nc)
  }, error = function(e) {
    if (verbose) warning("Could not detect product from NetCDF metadata, defaulting to terra")
  })
  
  # Extract and validate required layer indices
  evi_idx <- which(grepl("EVI", names(rast_obj), ignore.case = TRUE))[1]
  qa_idx  <- which(grepl("Quality", names(rast_obj), ignore.case = TRUE))[1]
  date_idx <- which(grepl("composite_day_of_the_year", names(rast_obj), ignore.case = TRUE))[1]
  
  if (is.na(evi_idx) || is.na(qa_idx) || is.na(date_idx)) {
    if (verbose) {
      message("Skipping file: missing required layers. EVI: ", !is.na(evi_idx), 
              ", QA: ", !is.na(qa_idx), ", Date: ", !is.na(date_idx))
    }
    return(NULL)
  }
  
  # Apply QA mask: keep only pixels with good QA values
  qa_r <- rast_obj[[qa_idx]]
  keep_mask <- terra::app(qa_r, function(x) x %in% keep_values)
  
  # Mask, project, and scale EVI
  evi <- terra::mask(rast_obj[[evi_idx]], keep_mask, maskvalue = FALSE) |> 
         terra::project(domain_template, method = "average") |> 
         terra::app(function(x) x * 100)
  
  # Mask and project date (composite day of year)
  date <- terra::mask(rast_obj[[date_idx]], keep_mask, maskvalue = FALSE) |> 
          terra::project(domain_template, method = "mode")
  
  # Get pid layer from domain
  if (!"pid" %in% names(domain_template)) {
    stop("domain_template must include a 'pid' layer")
  }
  pid_layer <- domain_template[["pid"]]
  
  # Convert rasters to matrices and vectorize
  evi_matrix <- terra::as.matrix(evi, wide = TRUE)
  date_matrix <- terra::as.matrix(date, wide = TRUE)
  pid_matrix <- terra::as.matrix(pid_layer, wide = TRUE)
  
  evi_vec <- as.vector(evi_matrix)
  date_vec <- as.vector(date_matrix)
  pid_vec <- as.vector(pid_matrix)
  
  # Identify valid observations (all three must be non-NA)
  valid_idx <- !is.na(evi_vec) & !is.na(date_vec) & !is.na(pid_vec)
  
  if (!any(valid_idx)) {
    if (verbose) message("No valid observations in ", basename(nc_path))
    return(NULL)
  }
  
  # Convert day-of-year to days-since-epoch
  ref_year <- as.integer(format(month_start, "%Y"))
  year_start <- as.Date(paste0(ref_year, "-01-01"))
  
  doy_to_epoch <- function(doy) {
    if (is.na(doy) || !is.finite(doy)) return(NA_integer_)
    date_obj <- year_start + (as.integer(doy) - 1)
    as.integer(date_obj - as.Date("1970-01-01"))
  }
  
  # Build observation tibble with vectorized date conversion
  obs_df <- tibble::tibble(
    pid = as.integer(pid_vec[valid_idx]),
    date = as.integer(sapply(date_vec[valid_idx], doy_to_epoch)),
    variable = sensor_id,
    value = as.integer(evi_vec[valid_idx])
  )
  
  if (verbose) {
    message("Extracted ", nrow(obs_df), " observations from ", basename(nc_path), " (", product_name, ")")
  }
  
  obs_df
}


#' @title Convert MODIS VI NetCDF files to parquet format
#' @description Processes downloaded NetCDF files: applies QA masking, reprojects to domain grid,
#' and converts observations to parquet format with one row per observation.
#' @author EMMA Team
#' @param netcdf_directory Path to directory containing downloaded NetCDF files and metadata
#' @param domain_raster A SpatRaster (domain.tif) defining the output grid and mask
#' @param month_start Start date for monthly period (YYYY-MM-DD)
#' @param out_dir Output directory for parquet files
#' @param cleanup Logical to delete temporary files after processing. Defaults to TRUE on GitHub Actions (GITHUB_ACTIONS env var), FALSE on local execution.
#' @param verbose Logical for progress messages
#' @return Character path to output parquet file (format: modis_vi_YYYYMM.parquet)
#' @details
#' Parquet schema:
#' - pid (int32): Pixel ID from domain grid
#' - date (int32): Days since epoch (1970-01-01)
#' - variable (int32): Sensor code (1=Terra, 2=Aqua, 3=VIIRS)
#' - value (int32): EVI value × 100
#' 
#' One row per unique observation (pid, date, sensor combination).
#' @export
netcdf_to_parquet <- function(
  netcdf_directory,
  domain_raster,
  month_start,
  out_dir = "data/processed_data/dynamic_parquet/modis_vi",
  cleanup = Sys.getenv("GITHUB_ACTIONS") == "true",
  verbose = TRUE
) {
  
  month_start <- as.Date(month_start)
  yyyymm <- format(month_start, "%Y%m")

  # Use a per-branch terra tempdir to prevent race conditions when multiple
  # months are processed in parallel by tar_make_future().
  terra_tmp <- file.path(getwd(), "data/temp/terra", yyyymm)
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terra::terraOptions(tempdir = terra_tmp, memfrac = 0.8)
  
  # Validate and load NetCDF files
  nc_paths <- list.files(netcdf_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)
  if (length(nc_paths) == 0) {
    if (verbose) message("No NetCDF files found in ", netcdf_directory, " - writing skip marker")
    
    # Create a lightweight skip marker file instead of fake data
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    skip_file <- file.path(out_dir, paste0("modis_vi_", yyyymm, "_monthly.skip"))
    
    writeLines(
      c(
        paste("Month:", yyyymm),
        paste("Reason: No NetCDF files available for processing"),
        paste("Note: Possible causes - polar region, cloud cover, instrument malfunction, or outside data availability period"),
        paste("Timestamp:", Sys.time())
      ),
      skip_file
    )
    
    if (verbose) message("Created skip marker: ", skip_file)
    
    if (cleanup) {
      unlink(netcdf_directory, recursive = TRUE, force = TRUE)
      gc()
      unlink(terra_tmp, recursive = TRUE, force = TRUE)
    }
    
    return(skip_file)
  }
  
  if (verbose) message("Reading ", length(nc_paths), " NetCDF files")
  

# Vargas et al.,15 pixels with any of the following QA flags were removed: 
# not confidently clear, adjacent to cloud, cloud shadow, snow or ice, thin cirrus cloud, 
# high aerosol loading, solar zenith angle >65 deg, and not over land.

  # Apply QA mask to VI layers
  qa_lookup <- list.files(
    netcdf_directory,
    pattern = "(VI-Quality-lookup).*\\.csv$",
    full.names = TRUE,
    recursive = TRUE
  )
  if (!length(qa_lookup)) {
    stop("QA lookup table (VI_Quality*.csv) not found in netcdf_directory; cannot mask VI data")
  }
  
  keep_values <- extract_keep_qa_values(qa_lookup)
  if (!length(keep_values)) {
    stop("No 'good quality' entries found in any QA table; refusing to proceed")
  }
  
  if (verbose) message("Using ", length(keep_values), " QA values for masking")
  
  # Load and validate domain raster
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  
  if (!"pid" %in% names(domain_template)) {
    stop("domain_raster must include a 'pid' layer")
  }
  
  # Get domain mask and valid pids
  mask_layer <- if ("domain" %in% names(domain_template)) domain_template[["domain"]] else domain_template
  pid_raster <- terra::mask(domain_template[["pid"]], mask_layer)
  valid_pids <- unique(terra::values(pid_raster)[, 1])
  valid_pids <- valid_pids[!is.na(valid_pids)]
  
  if (verbose) message("Domain has ", length(valid_pids), " valid pixels")
  
  # Process each NetCDF file independently (call helper once per file)
  all_obs <- list()
  
  for (nc_path in nc_paths) {
    obs <- extract_vi_observations(
      nc_path = nc_path,
      domain_template = domain_template,
      keep_values = keep_values,
      month_start = month_start,
      verbose = verbose
    )
    
    if (!is.null(obs)) {
      # Filter to domain pids
      obs <- obs[obs$pid %in% valid_pids, ]
      if (nrow(obs) > 0) {
        all_obs[[length(all_obs) + 1]] <- obs
      }
    }
  }
  
  if (length(all_obs) == 0) {
    if (verbose) message("No valid observations found after QA masking and domain filtering")
    if (cleanup) {
      unlink(netcdf_directory, recursive = TRUE, force = TRUE)
      gc()
      unlink(terra_tmp, recursive = TRUE, force = TRUE)
    }
    return(NA_character_)
  }
  
  # Bind all observations into single dataframe and drop any NAs (should be none after filtering, but just in case)
  df <- dplyr::bind_rows(all_obs)|>
        dplyr::filter(!is.na(.data$value))
  
  
  # Write to parquet
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  parquet_file <- file.path(out_dir, sprintf("dynamic_modis_vi_%s.parquet", yyyymm))
  
  unlink(parquet_file)
  if (verbose) message("Writing ", nrow(df), " observations to parquet")
  arrow::write_parquet(
    df,
    sink = parquet_file,
    compression = "gzip"
  )
  
  if (verbose) message("Parquet file saved: ", parquet_file)
  
  # Cleanup
  if (cleanup) {
    unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }
  
  parquet_file
}