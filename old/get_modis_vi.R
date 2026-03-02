
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


#' @title Download and process MODIS VI for a monthly period
#' @description Polls for completion of AppEEARS task and downloads results,
#' then processes into a NetCDF file with EVI and QA variables for that monthly period.
#' @author EMMA Team
#' @param task_id Character string with AppEEARS task ID
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param domain_raster A SpatRaster (domain.tif) defining the output grid and mask
#' @param month_start Start date for monthly period (YYYY-MM-DD)
#' @param out_dir Output directory for monthly NetCDF files
#' @param temp_directory Temporary working directory for downloads
#' @param verbose Logical for progress messages
#' @return Character path to output NetCDF file (format: modis_vi_YYYYMM_monthly.nc)
#' @details
#' Implements AppEEARS polling with timeout protection and QA masking.
#' Output is a single month of data; multiple outputs are aggregated separately.
#' @export
download_modis_vi <- function(
  task_id,
  domain_vector,
  domain_raster,
  month_start,
  out_dir = "data/target_outputs/modis_vi",
  temp_directory = "data/temp/raw_data/modis_vi_month/",
  cleanup = TRUE,
  verbose = TRUE
) {
  
  terra_tmp <- file.path(getwd(), "data/temp/terra")
  month_start <- as.Date(month_start)
  # Convert to YYYYMM format used in filenames
  yyyymm <- format(month_start, "%Y%m")
  file_name <- sprintf("modis_vi_%s_monthly.nc", yyyymm)
  
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
    # No data available for this month (common for edge cases, polar regions, etc.)
    if (verbose) message("No NetCDF files returned from AppEEARS for month ", file_name, " - writing skip marker")
    
    # Create a lightweight skip marker file instead of fake data
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    skip_file <- file.path(out_dir, paste0("modis_vi_", yyyymm, "_monthly.skip"))
    
    writeLines(
      c(
        paste("Month:", yyyymm),
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
  

# Vargas et al.,15 pixels with any of the following QA flags were removed: 
# not confidently clear, adjacent to cloud, cloud shadow, snow or ice, thin cirrus cloud, 
# high aerosol loading, solar zenith angle >65 deg, and not over land.

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
    # 1. VI produced with good quality OR VI produced but check other QA (conservative approach)
    # 2. No adjacent cloud detected
    # 3. No cloud shadow (possible shadow = No)
    # 4. No snow/ice (possible snow/ice = No)
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

  keep_values <- unique(unlist(lapply(qa_lookup, extract_keep)))
  if (!length(keep_values)) {
    stop("No 'good quality' entries found in any QA table; refusing to proceed")
  }

  mask_vi_with_qa <- function(stack, domain_template, product_name = "terra") {
    evi_idx <- which(grepl("EVI", names(stack), ignore.case = TRUE))[1]  # Take first EVI layer
    qa_idx  <- which(grepl("Quality", names(stack), ignore.case = TRUE))[1]  # Take first QA layer
    date_idx <- which(grepl("composite_day_of_the_year", names(stack), ignore.case = TRUE))[1]  # Take first date layer
    
    if (is.na(evi_idx) || is.na(qa_idx) || is.na(date_idx)) {
      message("Skipping file: missing EVI (", !is.na(evi_idx), "), QA (", !is.na(qa_idx), "), or date (", !is.na(date_idx), ") layer")
      return(NULL)
    }
    
    qa_r  <- stack[[qa_idx]]
    keep_mask <- terra::app(qa_r, function(x) x %in% keep_values)
    
    # Mask, project, and scale EVI
    evi <- terra::mask(stack[[evi_idx]], keep_mask, maskvalue = FALSE) |> 
           terra::project(domain_template, method = "average") |> 
           terra::app(function(x) x * 100)
    
    # Mask and project date (composite day of year)
    date <- terra::mask(stack[[date_idx]], keep_mask, maskvalue = FALSE) |> 
            terra::project(domain_template, method = "mode")
    
    # Name variables with product suffix
    names(evi) <- paste0("evi_", product_name)
    names(date) <- paste0("date_", product_name)
    
    c(date, evi)  # Return: date layer first, then EVI
  }

  # Project to domain grid
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster

  # Process all files, detecting product from file metadata and extracting time info
  # AppEEARS downloads files grouped by product (MOD13A1 files, then MYD13A1 files)
  all_layers <- list()
  all_times <- numeric()  # Store time values (days since epoch)
  file_counter <- 0
  
  for (nc_path in nc_paths) {
    file_counter <- file_counter + 1
    rast_obj <- terra::rast(nc_path)
    
    # Detect product and extract time dimension
    product_name <- "terra"
    nc_times <- NULL
    
    tryCatch({
      nc <- ncdf4::nc_open(nc_path)
      # Check global attributes for product name
      global_attrs <- names(ncdf4::ncatt_get(nc, 0))
      
      for (attr_name in global_attrs) {
        attr_val <- ncdf4::ncatt_get(nc, 0, attr_name)$value
        if (!is.null(attr_val) && is.character(attr_val)) {
          if (grepl("MYD13", attr_val, ignore.case = TRUE)) {
            product_name <- "aqua"
            break
          } else if (grepl("MOD13", attr_val, ignore.case = TRUE)) {
            product_name <- "terra"
            break
          }
        }
      }
      
      # Extract time values from NetCDF
      if ("time" %in% names(nc$dim)) {
        nc_times <- ncdf4::ncvar_get(nc, "time")
        if (!is.null(nc_times) && length(nc_times) > 0) {
          all_times <- c(all_times, nc_times)
        }
      }
      
      ncdf4::nc_close(nc)
    }, error = function(e) {
      # If reading file fails, use file order heuristic
      if (file_counter > 1) product_name <<- "aqua"
    })
    
    masked_layers <- mask_vi_with_qa(rast_obj, domain_template, product_name = product_name)
    if (!is.null(masked_layers)) {
      all_layers[[length(all_layers) + 1]] <- masked_layers
    }
  }
  
  # Combine all layers into single stack
  if (length(all_layers) == 0) {
    stop("No valid EVI/date layers found after QA masking")
  }
  
  raster_stack <- do.call(c, all_layers)
  
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

  # Write to NetCDF using ncdf4 to ensure separate variables
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, file_name)
  unlink(out_file)

  if (verbose) message("Writing NetCDF with daily time dimension and date-based observation placement: ", out_file)
  
  # Get dimensions and coordinates from output_stack
  nrow <- nrow(output_stack)
  ncol <- ncol(output_stack)
  crs <- terra::crs(output_stack)
  
  # Get actual x and y coordinates from the raster itself
  # These are the coordinates of the cell centers in row/column order
  x_coords <- terra::xFromCol(output_stack, col = 1:ncol)
  y_coords <- terra::yFromRow(output_stack, row = 1:nrow)
  
  # Create daily time dimension for entire month
  # Calculate the number of days in the month by finding last day of month
  year_int <- as.integer(format(month_start, "%Y"))
  month_int <- as.integer(format(month_start, "%m"))
  if (month_int < 12) {
    next_month_first <- as.Date(paste0(year_int, "-", sprintf("%02d", month_int + 1), "-01"))
  } else {
    next_month_first <- as.Date(paste0(year_int + 1, "-01-01"))
  }
  last_day_of_month <- next_month_first - 1
  days_in_month <- as.integer(format(last_day_of_month, "%d"))
  time_coords <- seq(0, days_in_month - 1, by = 1)
  time_units <- paste0("days since ", format(month_start, "%Y-%m-%d"))
  
  if (verbose) message("Using daily time dimension with ", days_in_month, " days")
  
  # Note: terra raster y coordinates are top-to-bottom; NetCDF expects bottom-to-top
  # We will handle the flip during matrix write, coordinates stay in raster order
  
  # Create dimensions with actual coordinates (using UDUNITS-compliant units)
  x_dim <- ncdf4::ncdim_def("x", "m", vals = x_coords)
  y_dim <- ncdf4::ncdim_def("y", "m", vals = y_coords)
  time_dim <- ncdf4::ncdim_def("time", time_units, vals = time_coords, unlim = TRUE)
  
  # Create variables for each unique variable name
  var_list <- list()
  unique_var_names <- unique(names(output_stack))
  
  for (var_name in unique_var_names) {
    if (var_name == "pid") {
      var_list[[var_name]] <- ncdf4::ncvar_def(
        name = var_name,
        units = "1",
        dim = list(x_dim, y_dim),
        missval = NA_real_,
        compression = 9
      )
    } else if (var_name %in% c("date_terra", "date_aqua", "evi_terra", "evi_aqua")) {
      var_list[[var_name]] <- ncdf4::ncvar_def(
        name = var_name,
        units = if (grepl("evi", var_name, ignore.case = TRUE)) "1" else "1",
        dim = list(time_dim, x_dim, y_dim),
        missval = NA_real_,
        compression = 9
      )
    }
  }
  
  # Create NetCDF file
  nc <- ncdf4::nc_create(out_file, var_list)
  
  # Function to convert day-of-year to day-of-month for the given month
  doy_to_dom <- function(doy, year_val, month_val) {
    if (is.na(doy) || !is.finite(doy)) return(NA_integer_)
    # Create date from day-of-year
    date <- as.Date(paste0(year_val, "-01-01")) + (as.integer(doy) - 1)
    # Check if it falls in the target month
    if (lubridate::month(date) == month_val) {
      return(lubridate::mday(date))
    } else {
      return(NA_integer_)
    }
  }
  
  # Get indices for date layers
  date_terra_idx <- which(names(output_stack) == "date_terra")
  date_aqua_idx <- which(names(output_stack) == "date_aqua")
  evi_terra_idx <- which(names(output_stack) == "evi_terra")
  evi_aqua_idx <- which(names(output_stack) == "evi_aqua")
  
  # Write each variable's data using date fields for temporal placement
  for (var_name in unique_var_names) {
    if (var_name == "pid") {
      # pid is constant across time
      matching_indices <- which(names(output_stack) == var_name)
      layer_data <- terra::as.matrix(output_stack[[matching_indices[1]]], wide = TRUE)
      layer_data <- layer_data[nrow(layer_data):1, ]
      layer_data <- t(layer_data)
      ncdf4::ncvar_put(nc, var_name, layer_data)
    } else if (var_name %in% c("date_terra", "date_aqua", "evi_terra", "evi_aqua")) {
      # Time-varying variables: place observations using date fields
      daily_array <- array(NA_real_, dim = c(ncol, nrow, days_in_month))
      
      # Determine which date field and observation index to use
      if (var_name %in% c("evi_terra", "date_terra")) {
        date_idx <- date_terra_idx
        obs_idx <- if (var_name == "evi_terra") evi_terra_idx else date_terra_idx
      } else {
        date_idx <- date_aqua_idx
        obs_idx <- if (var_name == "evi_aqua") evi_aqua_idx else date_aqua_idx
      }
      
      # For each observation, place it at the correct daily time slot based on date field
      if (length(obs_idx) > 0 && length(date_idx) > 0) {
        for (obs_seq in seq_along(obs_idx)) {
          if (obs_seq <= length(date_idx)) {
            obs_layer <- terra::as.matrix(output_stack[[obs_idx[obs_seq]]], wide = TRUE)
            date_layer <- terra::as.matrix(output_stack[[date_idx[obs_seq]]], wide = TRUE)
            
            # Reverse rows and transpose to match NetCDF order
            obs_layer <- obs_layer[nrow(obs_layer):1, ]
            obs_layer <- t(obs_layer)
            date_layer <- date_layer[nrow(date_layer):1, ]
            date_layer <- t(date_layer)
            
            # Convert day-of-year to day-of-month (vectorized apply to matrix)
            dom_matrix <- apply(date_layer, c(1, 2), function(x) {
              doy_to_dom(x, lubridate::year(month_start), lubridate::month(month_start))
            })
            
            # Place observations at correct day-of-month indices
            for (x in 1:ncol) {
              for (y in 1:nrow) {
                if (!is.na(obs_layer[x, y]) && !is.na(dom_matrix[x, y])) {
                  dom_val <- as.integer(dom_matrix[x, y])
                  if (dom_val >= 1 && dom_val <= days_in_month) {
                    daily_array[x, y, dom_val] <- obs_layer[x, y]
                  }
                }
              }
            }
          }
        }
      }
      
      ncdf4::ncvar_put(nc, var_name, daily_array)
    }
  }
  
  # Close file temporarily to add grid_mapping variable properly
  ncdf4::nc_close(nc)
  
  # Reopen file for writing and add grid_mapping variable
  nc <- ncdf4::nc_open(out_file, write = TRUE)
  
  # Add global attributes
  ncdf4::ncatt_put(nc, 0, "title", paste0("MODIS Terra/Aqua EVI for month ", yyyymm, " resampled to domain"))
  ncdf4::ncatt_put(nc, 0, "source", "MOD13A1.061 (Terra) and MYD13A1.061 (Aqua) via AppEEARS")
  ncdf4::ncatt_put(nc, 0, "temporal_resolution", "Daily time dimension; observations placed according to composite day-of-year (16-day composites)")
  ncdf4::ncatt_put(nc, 0, "time_structure", "Irregular: each pixel has observations on days corresponding to date_terra and date_aqua values; missing days are NA")
  ncdf4::ncatt_put(nc, 0, "spatial_resolution", "500m native, resampled to domain grid")
  ncdf4::ncatt_put(nc, 0, "month", yyyymm)
  ncdf4::ncatt_put(nc, 0, "history", paste0("created: ", Sys.time()))
  ncdf4::ncatt_put(nc, 0, "Conventions", "CF-1.8")
  ncdf4::ncatt_put(nc, 0, "note_evi_scaling", "EVI values are scaled by 100 for storage. Divide by 100 to recover original values.")
  ncdf4::ncatt_put(nc, 0, "scale_factor_evi", 0.01)
  ncdf4::ncatt_put(nc, 0, "qa_filter", "Pixels retained: VI produced with good/checkable quality, adjacent cloud=No, cloud shadow=No, snow/ice=No, over land, aerosol loading not high. Excludes: not confidently clear, adjacent to cloud, cloud shadow, snow or ice, high aerosol loading, not over land. Note: Solar zenith angle >65 deg filter not implemented in current QA table version.")
  
  # Get CRS information per CF-1.8 grid_mapping specification
  crs_str <- as.character(crs)
  
  if (!is.na(crs)) {
    # Get WKT in latest format (OGC WKT 2)
    crs_wkt <- terra::crs(output_stack, proj = TRUE)
    
    if (!is.null(crs_wkt) && nchar(crs_wkt) > 0) {
      # Per CF-1.8 Section 5.6.1, store CRS WKT following OGC WKT-CRS standard
      # This attribute is recognized by GDAL, QGIS, and other geospatial tools
      ncdf4::ncatt_put(nc, 0, "crs_wkt", crs_wkt)
      
      # Extract and store EPSG code if available (for quick reference and validation)
      epsg <- tryCatch(as.numeric(gsub("EPSG:", "", crs_str)), error = function(e) NA)
      if (!is.na(epsg)) {
        ncdf4::ncatt_put(nc, 0, "crs_epsg", as.integer(epsg))
      }
    }
  }
  
  # Add coordinate variable attributes per CF-1.8
  # Coordinate variable attributes per CF-1.8 Section 4.1-4.4 and 5.6
  ncdf4::ncatt_put(nc, "time", "axis", "T")
  ncdf4::ncatt_put(nc, "time", "long_name", "Time of composite")
  ncdf4::ncatt_put(nc, "time", "standard_name", "time")
  
  ncdf4::ncatt_put(nc, "x", "axis", "X")
  ncdf4::ncatt_put(nc, "x", "long_name", "X coordinate of projection")
  ncdf4::ncatt_put(nc, "x", "units", "m")
  ncdf4::ncatt_put(nc, "x", "standard_name", "projection_x_coordinate")
  
  ncdf4::ncatt_put(nc, "y", "axis", "Y")
  ncdf4::ncatt_put(nc, "y", "long_name", "Y coordinate of projection")
  ncdf4::ncatt_put(nc, "y", "units", "m")
  ncdf4::ncatt_put(nc, "y", "standard_name", "projection_y_coordinate")
  
  # Add metadata to each data variable
  for (var_name in unique_var_names) {
    if (var_name != "pid") {
      ncdf4::ncatt_put(nc, var_name, "coordinates", "time x y")
    }
    
    # Add units and descriptive names per CF-1.8 Section 3.1 and Appendix A
    if (grepl("evi", var_name, ignore.case = TRUE)) {
      ncdf4::ncatt_put(nc, var_name, "units", "1")  # Dimensionless
      ncdf4::ncatt_put(nc, var_name, "long_name", paste0("Enhanced Vegetation Index (scaled by 100) - ", toupper(sub("evi_", "", var_name))))
      ncdf4::ncatt_put(nc, var_name, "scale_factor", 0.01)  # Divide by 100 to recover original
      ncdf4::ncatt_put(nc, var_name, "valid_min", 0)
      ncdf4::ncatt_put(nc, var_name, "valid_max", 10000)
    } else if (grepl("date", var_name, ignore.case = TRUE)) {
      ncdf4::ncatt_put(nc, var_name, "units", "day")  # Day of year (1-366), not absolute time
      ncdf4::ncatt_put(nc, var_name, "long_name", paste0("Composite day of year - ", toupper(sub("date_", "", var_name))))
      ncdf4::ncatt_put(nc, var_name, "valid_min", 1)
      ncdf4::ncatt_put(nc, var_name, "valid_max", 366)
    }
  }
  
  # Add units to pid variable  
  ncdf4::ncatt_put(nc, "pid", "units", "1")
  ncdf4::ncatt_put(nc, "pid", "long_name", "Pixel ID")
  ncdf4::ncatt_put(nc, "pid", "coordinates", "x y")
  
  # Close the NetCDF file
  ncdf4::nc_close(nc)

  # Cleanup
  if(cleanup) {
    unlink(temp_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }

  if (verbose) message("MODIS VI monthly data saved to: ", out_file)
  out_file
}
