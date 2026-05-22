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
find_missing_months <- function(output_dir, dataset = "modis_vi", start_date = "2000-02-18", end_date = NULL) {
  
  # Create full monthly sequence
  all_months <- generate_monthly_sequence(start_date, end_date)
  
  # Check which ones already exist as processed NetCDF files OR skip markers.
  # A .skip file means AppEEARS returned no data for that month (e.g. pre-launch,
  # complete cloud cover) — it is not a failure, so do not retry it.
  # NC pattern matches both single-file outputs (dataset_YYYYMM.nc) and
  # sensor-split outputs (dataset_YYYYMM_terra.nc, dataset_YYYYMM_aqua.nc).
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  pattern_nc   <- paste0("^", dataset, "_\\d{6}.*\\.nc$")
  pattern_skip <- paste0("^", dataset, "_\\d{6}\\.skip$")
  existing_nc   <- list.files(output_dir, pattern = pattern_nc)
  existing_skip <- list.files(output_dir, pattern = pattern_skip)
  existing_files <- c(existing_nc, existing_skip)
  
  if (length(existing_files) == 0) {
    return(all_months)
  }
  
  # Extract YYYYMM as the first 6-digit sequence in each filename.
  # Works for: dataset_YYYYMM.nc, dataset_YYYYMM_terra.nc, dataset_YYYYMM.skip, etc.
  existing_dates <- regmatches(existing_files, regexpr("\\d{6}", existing_files))
  
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

  ensure_appeears_auth()
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
#' If the task is not found (e.g. expired after 14 days), and domain_vector
#' plus month_end are supplied, the task is automatically re-submitted.
#' @author EMMA Team
#' @param task_id Character string with AppEEARS task ID
#' @param month_start Start date for monthly period (YYYY-MM-DD)
#' @param domain_vector SpatVector or sf polygon used to re-submit if the task
#'   has expired. Optional; if NULL a missing-status error is raised instead.
#' @param month_end End date for monthly period (YYYY-MM-DD). Required only
#'   when domain_vector is provided for automatic re-submission.
#' @param temp_directory Temporary working directory for downloads
#' @param cleanup Logical to delete temporary files after processing. Defaults to TRUE on GitHub Actions (GITHUB_ACTIONS env var), FALSE on local execution.
#' @param verbose Logical for progress messages
#' @return Character path to temporary directory containing downloaded NetCDF files and metadata
#' @export
download_modis_vi_netcdf <- function(
  task_id,
  month_start,
  domain_vector = NULL,
  month_end = NULL,
  temp_directory = "data/temp/appeears/modis_vi/",
  cleanup = Sys.getenv("GITHUB_ACTIONS") == "true",
  verbose = TRUE
) {

  ensure_appeears_auth()
  month_start <- as.Date(month_start)
  yyyymm <- format(month_start, "%Y%m")

  # Check if this month was already processed into a grid NC; if so, skip re-downloading.
  # vi_modis_netcdf_to_grid() writes vi_modis_YYYYMM_terra.nc when it completes.
  cache_dir <- "data/target_outputs/modis_vi"
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  terra_nc_done <- file.path(cache_dir, paste0("vi_modis_", yyyymm, "_terra.nc"))

  if (file.exists(terra_nc_done)) {
    if (verbose) message("Grid NC found for ", yyyymm, " — skipping AppEEARS download")
    dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
    return(temp_directory)
  }
  
  # Each branch gets its own subdirectory to avoid race conditions when
  # parallel tar_make_future() workers run multiple months simultaneously.
  temp_directory <- file.path(temp_directory, yyyymm)
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  # Poll for task completion
  if (verbose) message("Polling task ", task_id, " for completion...")
  
  max_retries <- 15  # 15 minutes at 60s intervals; error = "continue" on target handles retry
  retry_count <- 0
  task_status <- "pending"
  null_retries <- 0L  # consecutive null-status responses; AppEEARS may lag ~1-2 min after submission

  repeat {
    retry_count <- retry_count + 1

    # Check task status
    task_info   <- appeears::rs_list_task(task_id = task_id, user = Sys.getenv("EARTHDATA_USER"))
    task_status <- task_info$status

    # AppEEARS returns no 'status' field when the task is not found.  Allow 3
    # consecutive null responses before treating as expired — a freshly submitted
    # task may not be visible in the list endpoint for a minute or two.
    if (is.null(task_status) || length(task_status) == 0) {
      null_retries <- null_retries + 1L
      if (null_retries <= 10L) {
        if (verbose) message("Task ", task_id, " not yet visible in AppEEARS (",
                             null_retries, "/10) — retrying...")
        Sys.sleep(60)
        next
      }
      null_retries <- 0L
      if (!is.null(domain_vector) && !is.null(month_end)) {
        if (verbose) {
          message(
            "[AppEEARS] Task ", task_id, " not found (likely expired) — re-submitting for ", yyyymm
          )
        }
        task_id     <- submit_modis_vi(
          domain_vector = domain_vector,
          month_start   = month_start,
          month_end     = as.Date(month_end),
          verbose       = verbose
        )
        retry_count <- 0
        next
      }
      stop(
        "AppEEARS task ", task_id, " returned no status field.\n",
        "The task likely expired (AppEEARS retains results for ~14 days).\n",
        "Pass domain_vector and month_end to enable automatic re-submission, ",
        "or run tar_invalidate(vi_modis_task_ids) to force re-submission."
      )
    }
    null_retries <- 0L

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
    skip_file <- file.path(cache_dir, paste0("vi_modis_", yyyymm, ".skip"))
    writeLines(
      c(paste("Month:", yyyymm), "Reason: AppEEARS returned no NetCDF files", paste("Timestamp:", Sys.time())),
      con = skip_file
    )
    if (verbose) message("Created skip marker: ", skip_file)
    if (cleanup) unlink(temp_directory, recursive = TRUE, force = TRUE)
    return(skip_file)
  }
  
  if (verbose) message("Downloaded ", length(nc_paths), " NetCDF files to ", temp_directory)
  
  # Return temp directory so vi_modis_netcdf_to_grid() can access the actual files.
  # No sentinel NC is written here; the grid NC written by vi_modis_netcdf_to_grid()
  # acts as the persistent marker that prevents re-downloading.
  return(temp_directory)
}


#' @title Convert MODIS VI AppEEARS NetCDF files to domain-aligned raster grids
#' @description Processes raw AppEEARS NetCDF downloads for one month:
#'   applies QA masking, handles multiple spatial tiles via mosaicing, and
#'   reprojects to the domain grid.  Outputs two NetCDF files — one for
#'   Terra (MOD13A1) and one for Aqua (MYD13A1) — each containing two
#'   variables: \code{EVI} (EVI×100, QA-masked) and \code{doy}
#'   (composite day-of-year, per pixel).  Both variables share a time
#'   dimension whose steps are the nominal start dates of each 16-day
#'   composite period present in the download.
#'
#'   If AppEEARS returned no files (skip path received or empty directory),
#'   all-NA grids are still written so that \code{find_missing_months()}
#'   treats the month as complete and does not retry it.
#'
#' @param netcdf_directory Character.  Path to directory containing raw
#'   AppEEARS NC files, or path to a \code{.skip} marker returned by
#'   \code{download_modis_vi_netcdf()} when no data were available.
#' @param domain_raster Character path or SpatRaster.  Must contain a
#'   \code{pid} layer defining the model grid.
#' @param month_start Date or "YYYY-MM-DD".  First day of the month —
#'   used for naming output files and as the time stamp for all-NA grids.
#' @param out_dir Character.  Output directory for the two sensor NCs.
#' @param cleanup Logical.  Delete the raw AppEEARS temp files after
#'   writing the grid NCs?  Defaults to TRUE on GitHub Actions.
#' @param verbose Logical.  Print progress messages?
#'
#' @return Character vector of length 2:
#'   \code{c("out_dir/vi_modis_YYYYMM_terra.nc", "out_dir/vi_modis_YYYYMM_aqua.nc")}.
#'   Both files are always written (all-NA when no source data exist).
#' @export
vi_modis_netcdf_to_grid <- function(
  netcdf_directory,
  domain_raster,
  month_start,
  out_dir  = "data/target_outputs/modis_vi/",
  cleanup  = Sys.getenv("GITHUB_ACTIONS") == "true",
  verbose  = TRUE
) {
  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  # Per-branch terra tempdir prevents race conditions under parallel tar_make_future()
  terra_tmp <- file.path(getwd(), "data/temp/terra", yyyymm)
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terra::terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_terra_nc <- file.path(out_dir, paste0("vi_modis_", yyyymm, "_terra.nc"))
  out_aqua_nc  <- file.path(out_dir, paste0("vi_modis_", yyyymm, "_aqua.nc"))

  # Load domain template (needed even for the all-NA fallback)
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))

  # Helper: write an all-NA two-variable NC for one sensor (EVI + doy)
  write_empty_sensor_nc <- function(out_nc, t_date) {
    empty_r <- terra::setValues(domain_template[[1]], NA_real_)
    terra::time(empty_r) <- t_date
    terra::writeCDF(empty_r, out_nc,
                    varname  = "EVI",
                    longname = "EVI x100 (QA-masked, no data)",
                    overwrite = TRUE, verbose = FALSE)
    terra::writeCDF(empty_r, out_nc,
                    varname  = "doy",
                    longname = "Composite day of year (no data)",
                    append   = TRUE, verbose = FALSE)
  }

  # Determine source NC files — handle both directory path and skip-file path
  nc_paths <- character(0)
  if (!grepl("\\.skip$", netcdf_directory) && dir.exists(netcdf_directory)) {
    nc_paths <- list.files(netcdf_directory, pattern = "\\.nc$",
                           full.names = TRUE, recursive = TRUE)
  }

  if (length(nc_paths) == 0) {
    if (verbose) message("No source NCs for ", yyyymm, " — writing all-NA grid files")
    write_empty_sensor_nc(out_terra_nc, month_start)
    write_empty_sensor_nc(out_aqua_nc,  month_start)
    if (cleanup && !grepl("\\.skip$", netcdf_directory) && dir.exists(netcdf_directory)) {
      unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    }
    return(c(out_terra_nc, out_aqua_nc))
  }

  # Read QA lookup tables (AppEEARS includes them alongside the NC files)
  qa_lookup <- list.files(netcdf_directory, pattern = "VI-Quality.*\\.csv$",
                          full.names = TRUE, recursive = TRUE)
  if (!length(qa_lookup)) {
    stop("QA lookup table not found in netcdf_directory; cannot QA-mask VI data")
  }
  keep_values <- parse_qa(qa_lookup)
  if (!length(keep_values)) stop("No good-quality QA entries found in lookup tables")

  if (verbose) {
    message("Processing ", length(nc_paths), " NC files for ", yyyymm,
            " (", length(keep_values), " QA keep values)")
  }

  # Classify each NC as Terra (MOD13A1) or Aqua (MYD13A1)
  detect_sensor <- function(nc_path) {
    sensor <- "terra"
    tryCatch({
      nc_obj <- ncdf4::nc_open(nc_path)
      attrs  <- ncdf4::ncatt_get(nc_obj, 0)
      ncdf4::nc_close(nc_obj)
      for (val in attrs) {
        if (is.character(val) && grepl("MYD13", val, ignore.case = TRUE)) {
          sensor <- "aqua"
          break
        }
      }
    }, error = function(e) invisible(NULL))
    sensor
  }

  sensor_labels <- vapply(nc_paths, detect_sensor, character(1L))
  terra_ncs <- nc_paths[sensor_labels == "terra"]
  aqua_ncs  <- nc_paths[sensor_labels == "aqua"]
  if (verbose) {
    message("Sensor split: ", length(terra_ncs), " Terra NC(s), ",
            length(aqua_ncs), " Aqua NC(s)")
  }

  # Process one set of same-sensor NC files → (EVI stack, doy stack) aligned to domain.
  # Multiple NCs may cover different spatial tiles for the same time step and
  # are mosaiced before reprojection.
  process_sensor_ncs <- function(ncs, keep_values, domain_template, verbose) {
    if (length(ncs) == 0L) return(NULL)

    # Collect all unique time values (as numeric days since epoch) across all NCs
    all_t_numeric <- unique(unlist(lapply(ncs, function(p) {
      r       <- terra::rast(p)
      evi_idx <- which(grepl("EVI", names(r), ignore.case = TRUE) &
                       !grepl("Quality|composite_day", names(r), ignore.case = TRUE))
      if (length(evi_idx) == 0L) return(NULL)
      as.numeric(terra::time(r[[evi_idx]]))
    })))
    all_t_numeric <- sort(all_t_numeric[is.finite(all_t_numeric)])
    if (length(all_t_numeric) == 0L) return(NULL)

    evi_layers <- vector("list", length(all_t_numeric))
    doy_layers <- vector("list", length(all_t_numeric))
    valid_t    <- logical(length(all_t_numeric))

    for (ti in seq_along(all_t_numeric)) {
      t_val     <- all_t_numeric[ti]
      evi_tiles <- list()
      doy_tiles <- list()

      for (nc_path in ncs) {
        r <- terra::rast(nc_path)

        evi_idx <- which(grepl("EVI", names(r), ignore.case = TRUE) &
                         !grepl("Quality|composite_day", names(r), ignore.case = TRUE))
        qa_idx  <- which(grepl("VI_Quality|vi_quality|Quality", names(r), ignore.case = TRUE))
        doy_idx <- which(grepl("composite_day_of_the_year", names(r), ignore.case = TRUE))

        if (length(evi_idx) == 0L) next

        # Find the layer(s) for this specific time step
        r_times <- as.numeric(terra::time(r[[evi_idx]]))
        t_match <- which(r_times == t_val)
        if (length(t_match) == 0L) next

        i_evi <- evi_idx[t_match[1L]]
        i_qa  <- qa_idx[min(t_match[1L], length(qa_idx))]
        i_doy <- doy_idx[min(t_match[1L], length(doy_idx))]

        # Apply QA mask; scale EVI by 100 (matches existing parquet schema)
        keep_mask  <- terra::app(r[[i_qa]], function(x) x %in% keep_values)
        evi_masked <- terra::mask(r[[i_evi]], keep_mask, maskvalue = FALSE) |>
                      terra::app(function(x) as.integer(round(x * 100)))
        doy_masked <- terra::mask(r[[i_doy]], keep_mask, maskvalue = FALSE)

        evi_tiles[[length(evi_tiles) + 1L]] <- evi_masked
        doy_tiles[[length(doy_tiles) + 1L]] <- doy_masked
      }

      if (length(evi_tiles) == 0L) next

      # Mosaic spatial tiles for this time step
      if (length(evi_tiles) == 1L) {
        evi_m <- evi_tiles[[1L]]
        doy_m <- doy_tiles[[1L]]
      } else {
        evi_m <- do.call(terra::mosaic, c(evi_tiles, list(fun = "mean")))
        doy_m <- do.call(terra::mosaic, c(doy_tiles, list(fun = "first")))
      }

      # Reproject to domain grid and mask to domain pixels
      evi_proj <- terra::project(evi_m, domain_template, method = "average")
      doy_proj <- terra::project(doy_m, domain_template, method = "mode")
      domain_mask <- !is.na(domain_template[["pid"]])
      evi_proj <- terra::mask(evi_proj, domain_mask, maskvalue = FALSE)
      doy_proj <- terra::mask(doy_proj, domain_mask, maskvalue = FALSE)

      evi_layers[[ti]] <- evi_proj
      doy_layers[[ti]] <- doy_proj
      valid_t[ti]      <- TRUE
    }

    keep_ti <- which(valid_t)
    if (length(keep_ti) == 0L) return(NULL)

    evi_stack <- do.call(c, evi_layers[keep_ti])
    doy_stack <- do.call(c, doy_layers[keep_ti])
    t_dates   <- as.Date(all_t_numeric[keep_ti], origin = "1970-01-01")
    terra::time(evi_stack) <- t_dates
    terra::time(doy_stack) <- t_dates

    list(evi = evi_stack, doy = doy_stack)
  }

  terra_data <- process_sensor_ncs(terra_ncs, keep_values, domain_template, verbose)
  aqua_data  <- process_sensor_ncs(aqua_ncs,  keep_values, domain_template, verbose)

  # Write output NC for each sensor.  EVI and doy share the same time dimension
  # within each sensor file, so terra::writeCDF append=TRUE works correctly.
  write_sensor_nc <- function(sensor_data, out_nc, sensor_label, verbose) {
    if (is.null(sensor_data)) {
      # No valid composites for this sensor — write single all-NA time step
      if (verbose) message("No valid composites for ", sensor_label, " in ", yyyymm,
                           " — writing all-NA NC")
      write_empty_sensor_nc(out_nc, month_start)
    } else {
      terra::writeCDF(sensor_data$evi, out_nc,
                      varname  = "EVI",
                      longname = paste0("EVI x100 QA-masked (", sensor_label, ")"),
                      overwrite = TRUE, verbose = FALSE)
      terra::writeCDF(sensor_data$doy, out_nc,
                      varname  = "doy",
                      longname = paste0("Composite day of year (", sensor_label, ")"),
                      append   = TRUE, verbose = FALSE)
      n_steps <- if (is.null(sensor_data)) 0L else terra::nlyr(sensor_data$evi)
      if (verbose) message("Wrote ", n_steps, " time step(s) → ", basename(out_nc))
    }
  }

  write_sensor_nc(terra_data, out_terra_nc, "Terra/MOD13A1", verbose)
  write_sensor_nc(aqua_data,  out_aqua_nc,  "Aqua/MYD13A1",  verbose)

  if (cleanup) {
    unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }

  c(out_terra_nc, out_aqua_nc)
}


#' @title Extract QA-good values from AppEEARS lookup table
#' @description Helper function to extract pixel QA flag values that meet quality criteria.
#' Filters based on: VI quality, no adjacent cloud, no shadow, no snow, over land, low aerosol.
#' @param qa_lookup_files Character vector of paths to VI Quality lookup CSV files
#' @return Integer vector of QA flag values that pass all quality filters
#' @keywords internal
parse_qa <- function(qa_lookup_files) {
  
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


#' @title Convert MODIS VI sensor NetCDF grids to parquet format
#' @description Reads the two sensor NC files produced by
#'   \code{vi_modis_netcdf_to_grid()} and extracts one row per valid
#'   (non-NA EVI) pixel per 16-day composite.  The \code{date} column
#'   contains the per-pixel composite day-of-year converted to days
#'   since 1970-01-01, preserving the actual observation date rather
#'   than the nominal month start.
#'
#' @param nc_files Character vector of length 2:
#'   \code{c("vi_modis_YYYYMM_terra.nc", "vi_modis_YYYYMM_aqua.nc")} as
#'   returned by \code{vi_modis_netcdf_to_grid()}.
#' @param domain_raster Character path or SpatRaster containing a \code{pid}
#'   layer.
#' @param month_start Date or "YYYY-MM-DD".  Used for output file naming and
#'   for converting composite day-of-year to a calendar date (year context).
#' @param out_dir Character.  Output directory for parquet files.
#' @param verbose Logical.  Print progress messages?
#'
#' @return Character path to the output parquet file
#'   (\code{dynamic_modis_vi_YYYYMM.parquet}), or a \code{.skip} path if
#'   all grid layers are NA.
#'
#' @details
#' Parquet schema (one row per observation):
#' \describe{
#'   \item{pid}{int32 — pixel ID from domain grid}
#'   \item{date}{int32 — days since 1970-01-01, from per-pixel composite DOY}
#'   \item{variable}{int32 — sensor code: 1 = Terra (MOD13A1), 2 = Aqua (MYD13A1)}
#'   \item{value}{int32 — EVI × 100}
#' }
#' @export
vi_modis_netcdf_to_parquet <- function(
  nc_files,
  domain_raster,
  month_start,
  out_dir  = "data/target_outputs/modis_vi/",
  verbose  = TRUE
) {
  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  parquet_file <- file.path(out_dir, paste0("dynamic_modis_vi_", yyyymm, ".parquet"))

  # Load domain for pid values
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))
  pid_vec  <- terra::values(domain_template[["pid"]])[, 1]
  ref_year <- as.integer(format(month_start, "%Y"))
  year_start_epoch <- as.integer(as.Date(paste0(ref_year, "-01-01")) - as.Date("1970-01-01"))

  # Detect sensor code from filename: _terra_ → 1, _aqua_ → 2
  sensor_code <- function(nc_path) {
    if (grepl("_terra_", basename(nc_path))) 1L else 2L
  }

  # Extract observations from one sensor NC (EVI + doy variables, N time steps)
  extract_sensor_obs <- function(nc_path) {
    s_id  <- sensor_code(nc_path)
    evi_r <- tryCatch(terra::rast(nc_path, subds = "EVI"),
                      error = function(e) NULL)
    doy_r <- tryCatch(terra::rast(nc_path, subds = "doy"),
                      error = function(e) NULL)
    if (is.null(evi_r) || is.null(doy_r)) {
      if (verbose) message("Could not read subdatasets from: ", basename(nc_path))
      return(NULL)
    }
    n_steps <- terra::nlyr(evi_r)
    obs <- vector("list", n_steps)
    for (ti in seq_len(n_steps)) {
      evi_v <- terra::values(evi_r[[ti]])[, 1]
      doy_v <- terra::values(doy_r[[ti]])[, 1]
      valid <- !is.na(evi_v) & !is.na(doy_v) & !is.na(pid_vec)
      if (!any(valid)) next
      # Convert composite day-of-year to days since 1970-01-01
      epoch_dates <- as.integer(year_start_epoch + as.integer(doy_v[valid]) - 1L)
      obs[[ti]] <- tibble::tibble(
        pid      = as.integer(pid_vec[valid]),
        date     = epoch_dates,
        variable = s_id,
        value    = as.integer(evi_v[valid])
      )
    }
    dplyr::bind_rows(obs)
  }

  all_obs <- purrr::map(nc_files, function(nc) {
    tryCatch(extract_sensor_obs(nc),
             error = function(e) {
               warning("Failed to process ", basename(nc), ": ", conditionMessage(e))
               NULL
             })
  })

  df <- dplyr::bind_rows(purrr::compact(all_obs)) |>
        dplyr::filter(!is.na(.data$value))

  if (nrow(df) == 0L) {
    if (verbose) message("No valid VI observations for ", yyyymm, " — writing skip marker")
    skip_file <- file.path(out_dir, paste0("vi_modis_", yyyymm, ".skip"))
    writeLines(
      c(paste("Month:", yyyymm),
        "Reason: All-NA after reading sensor grid NCs",
        paste("Timestamp:", Sys.time())),
      skip_file
    )
    return(skip_file)
  }

  unlink(parquet_file)
  if (verbose) message("Writing ", nrow(df), " observations → ", basename(parquet_file))
  arrow::write_parquet(df, sink = parquet_file, compression = "gzip")

  parquet_file
}