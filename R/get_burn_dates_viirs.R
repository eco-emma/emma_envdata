# ============================================================================
# VIIRS Burned Area (VNP64A1) Download via AppEEARS
# ============================================================================
# Downloads monthly VIIRS VNP64A1.002 burned area data from NASA AppEEARS.
# Structurally identical to get_burn_dates_modis.R — read that file first
# for design rationale and the shared output schema.
#
# VNP64A1.002 product details:
#   - Sensor:     Suomi NPP VIIRS
#   - Resolution: 500m (same grid as MODIS, compatible with domain)
#   - Coverage:   January 2012 – present
#   - Layers:     Burn_Date (day-of-year), QA
#
# Using both MODIS and VIIRS provides:
#   1. Continuity: MODIS Terra is in a degraded orbit and will eventually stop
#   2. Overlap period (2012–present) for cross-validation
#   3. VIIRS has slightly better detection in small fires
# ============================================================================


#' @title Submit monthly VIIRS burned area request via AppEEARS
#'
#' @description Submits a VNP64A1.002 area request for a single calendar month.
#'   Identical request structure to MODIS version; only product code differs.
#'
#' @param domain_vector An sf or SpatVector polygon defining the study domain.
#' @param month_start   Date. First day of the month.
#' @param month_end     Date. Last day of the month.
#' @param verbose       Logical. Print progress messages? Default TRUE.
#'
#' @return Character string: AppEEARS task ID.
#' @export
submit_burn_date_viirs_task <- function(
    domain_vector,
    month_start,
    month_end,
    verbose = TRUE) {
  ensure_appeears_auth()  
  month_start <- as.Date(month_start)
  month_end   <- as.Date(month_end)

  if (verbose) {
    message(
      "Submitting VIIRS burn date task: ",
      format(month_start, "%Y-%m-%d"), " to ", format(month_end, "%Y-%m-%d")
    )
  }

  # Simplify and reproject domain to WGS84 GeoJSON for AppEEARS
  domain_geojson <- domain_vector |>
    sf::st_as_sf() |>
    sf::st_simplify(dTolerance = 100, preserveTopology = TRUE) |>
    sf::st_buffer(0) |>
    sf::st_make_valid() |>
    sf::st_transform(crs = 4326) |>
    geojsonsf::sf_geojson(simplify = FALSE) |>
    jsonlite::fromJSON()

  # Build AppEEARS request for VNP64A1 Burn Date + QA
  req <- list(
    task_type = "area",
    task_name = paste0("VIIRS_BurnDate_", format(month_start, "%Y%m"), "_", format(Sys.time(), "%H%M%S")),
    params = list(
      dates = list(list(
        startDate = format(month_start, "%m-%d-%Y"),
        endDate   = format(month_end,   "%m-%d-%Y")
      )),
      layers = list(
        list(product = "VNP64A1.002", layer = "Burn_Date"),
        list(product = "VNP64A1.002", layer = "QA")
      ),
      output = list(
        format     = list(type = "netcdf4"),
        projection = "native"
      ),
      geo = domain_geojson
    )
  )

  task <- appeears::rs_request(
    request  = req,
    user     = Sys.getenv("EARTHDATA_USER"),
    transfer = FALSE,
    verbose  = verbose
  )

  task_id <- task$get_task_id()
  if (verbose) message("VIIRS burn date task submitted: ", task_id)
  task_id
}


#' @title Download VIIRS burned area NetCDF files from AppEEARS
#'
#' @description Polls until the task completes, downloads the results, and creates
#'   a marker file. Identical to \code{download_burn_date_modis_netcdf()} except
#'   for dataset naming conventions.
#'
#' @param task_id      Character. AppEEARS task ID.
#' @param month_start  Date. First day of the month.
#' @param domain_vector SpatVector or sf polygon used to re-submit if the task
#'   has expired. Optional; if NULL a missing-status error is raised instead.
#' @param month_end   Date. Last day of the month. Required only when
#'   domain_vector is provided for automatic re-submission.
#' @param temp_directory Character. Download directory.
#' @param cleanup      Logical. Delete temp files after conversion?
#' @param verbose      Logical. Print progress messages?
#'
#' @return Character path to temp directory containing downloaded NetCDF files.
#' @export
download_burn_date_viirs_netcdf <- function(
    task_id,
    month_start,
    domain_vector  = NULL,
    month_end      = NULL,
    temp_directory = "data/temp/appeears/burn_dates_viirs/",
    cleanup        = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose        = TRUE) {

  ensure_appeears_auth()
  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  # Skip if grid NC for this month already exists.
  # burn_viirs_netcdf_to_grid() writes burn_viirs_YYYYMM.nc when it completes.
  marker_dir  <- "data/target_outputs/burn_dates_viirs"
  dir.create(marker_dir,      recursive = TRUE, showWarnings = FALSE)
  dir.create(temp_directory,  recursive = TRUE, showWarnings = FALSE)
  grid_nc_done <- file.path(marker_dir, paste0("burn_viirs_", yyyymm, ".nc"))

  if (file.exists(grid_nc_done)) {
    if (verbose) message("VIIRS grid NC found for ", yyyymm, " — skipping download")
    return(temp_directory)
  }

  # Each branch gets its own month-specific subdirectory to prevent race
  # conditions when parallel tar_make_future() workers share base temp_directory.
  temp_directory <- file.path(temp_directory, yyyymm)
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  # Poll AppEEARS for up to 15 minutes; error = "continue" on target handles retry
  if (verbose) message("Polling AppEEARS task ", task_id, " ...")

  max_retries <- 15
  retry_count <- 0
  null_retries <- 0L  # consecutive null-status responses; AppEEARS may lag ~1-2 min after submission

  repeat {
    retry_count <- retry_count + 1

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
        task_id     <- submit_burn_date_viirs_task(
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
        "or run tar_invalidate(burn_viirs_task_ids) to force re-submission."
      )
    }
    null_retries <- 0L

    if (task_status %in% c("done", "failed", "error")) {
      if (verbose) message("Status: ", task_status, " (", retry_count, "/", max_retries, ")")
      break
    }
    if (retry_count >= max_retries) {
      stop("Task ", task_id, " timed out after ", max_retries, " minutes")
    }
    if (verbose && retry_count %% 10 == 0) {
      message("Status: ", task_status, " (", retry_count, "/", max_retries, ")")
    }
    Sys.sleep(60)
  }

  if (task_status %in% c("failed", "error")) {
    stop("AppEEARS task ", task_id, " failed: ", task_status)
  }
  if (task_status != "done") {
    stop("Task ", task_id, " timed out after ", max_retries, " minutes")
  }

  appeears::rs_transfer(
    task_id = task_id,
    user    = Sys.getenv("EARTHDATA_USER"),
    path    = temp_directory,
    verbose = verbose
  )

  nc_paths <- list.files(temp_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)
  if (length(nc_paths) == 0) {
    if (verbose) message("No NetCDF files returned for VIIRS month ", yyyymm)
    skip_file <- file.path(marker_dir, paste0("burn_viirs_", yyyymm, ".skip"))
    writeLines(
      c(paste("Month:", yyyymm), "Reason: No NetCDF returned from AppEEARS", paste("Timestamp:", Sys.time())),
      con = skip_file
    )
    return(skip_file)
  }

  if (verbose) message("Downloaded ", length(nc_paths), " VIIRS NetCDF files for ", yyyymm)
  # Return temp directory; burn_viirs_netcdf_to_grid() acts as the persistent marker.
  temp_directory
}


#' @title Convert VIIRS burned area NetCDF tiles to a domain-aligned raster grid
#' @description Identical workflow to \code{burn_modis_netcdf_to_grid()} but for
#'   VNP64A1 (VIIRS, 375m).  The 375m pixels are resampled to the 500m domain
#'   grid via nearest-neighbour reprojection.  Writes a single NetCDF containing
#'   a \code{burn_doy} variable (burn day-of-year, QA = 0 pixels only).
#'
#' @param netcdf_directory Character.  Path to AppEEARS temp directory or a
#'   \code{.skip} path.
#' @param domain_raster Character path or SpatRaster with a \code{pid} layer.
#' @param month_start Date or "YYYY-MM-DD".
#' @param out_dir Character.  Output directory for the grid NC.
#' @param cleanup Logical.  Delete raw temp files after writing?
#' @param verbose Logical.
#'
#' @return Character path to \code{burn_viirs_YYYYMM.nc}.
#' @export
burn_viirs_netcdf_to_grid <- function(
  netcdf_directory,
  domain_raster,
  month_start,
  out_dir  = "data/target_outputs/burn_dates_viirs/",
  cleanup  = Sys.getenv("GITHUB_ACTIONS") == "true",
  verbose  = TRUE
) {
  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  terra_tmp <- file.path(getwd(), "data/temp/terra", yyyymm)
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terra::terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_nc <- file.path(out_dir, paste0("burn_viirs_", yyyymm, ".nc"))

  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))

  write_empty_nc <- function() {
    empty_r <- terra::setValues(domain_template[[1]], NA_real_)
    terra::time(empty_r) <- month_start
    terra::writeCDF(empty_r, out_nc,
                    varname  = "burn_doy",
                    longname = "Burn day of year (VNP64A1, no data)",
                    overwrite = TRUE, verbose = FALSE)
  }

  nc_paths <- character(0)
  if (!grepl("\\.skip$", netcdf_directory) && dir.exists(netcdf_directory)) {
    nc_paths <- list.files(netcdf_directory, pattern = "\\.nc$",
                           full.names = TRUE, recursive = TRUE)
  }

  if (length(nc_paths) == 0L) {
    if (verbose) message("No VIIRS burn NCs for ", yyyymm, " — writing all-NA grid")
    write_empty_nc()
    if (cleanup && !grepl("\\.skip$", netcdf_directory) && dir.exists(netcdf_directory)) {
      unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    }
    return(out_nc)
  }

  burn_tiles <- list()
  for (nc_path in nc_paths) {
    tryCatch({
      r        <- terra::rast(nc_path)
      burn_idx <- which(grepl("Burn_Date|BurnDate|burn_date", names(r),
                              ignore.case = TRUE))[1]
      qa_idx   <- which(grepl("^QA$|quality", names(r), ignore.case = TRUE))[1]
      if (is.na(burn_idx) || is.na(qa_idx)) {
        warning("Missing Burn_Date or QA in ", basename(nc_path), " — skipping tile")
        return(NULL)
      }
      # Nearest-neighbour handles 375m → 500m resampling
      burn_proj <- terra::project(r[[burn_idx]], domain_template, method = "near")
      qa_proj   <- terra::project(r[[qa_idx]],   domain_template, method = "near")
      good_qa   <- terra::app(qa_proj, function(x) x == 0)
      burn_tiles[[length(burn_tiles) + 1L]] <- terra::mask(burn_proj, good_qa,
                                                            maskvalue = FALSE)
    }, error = function(e) {
      warning("Failed to process ", basename(nc_path), ": ", conditionMessage(e))
    })
  }

  burn_tiles <- Filter(Negate(is.null), burn_tiles)

  if (length(burn_tiles) == 0L) {
    if (verbose) message("All VIIRS tiles empty after QA for ", yyyymm, " — writing all-NA grid")
    write_empty_nc()
    if (cleanup) unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    return(out_nc)
  }

  burn_mosaic <- if (length(burn_tiles) == 1L) {
    burn_tiles[[1L]]
  } else {
    do.call(terra::mosaic, c(burn_tiles, list(fun = "first")))
  }
  domain_mask <- !is.na(domain_template[["pid"]])
  burn_mosaic <- terra::mask(burn_mosaic, domain_mask, maskvalue = FALSE)

  terra::time(burn_mosaic) <- month_start
  terra::writeCDF(burn_mosaic, out_nc,
                  varname  = "burn_doy",
                  longname = "Burn day of year (VNP64A1, QA=0)",
                  overwrite = TRUE, verbose = FALSE)

  if (verbose) message("Wrote VIIRS burn grid NC: ", basename(out_nc))

  if (cleanup) {
    unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }

  out_nc
}


#' @title Convert VIIRS burned area NetCDF to parquet
#'
#' @description Reads \code{burn_doy} from the domain-aligned NC produced by
#'   \code{burn_viirs_netcdf_to_grid()} and writes a tidy parquet.  QA filtering
#'   was applied in the grid step, so all rows have qa = 0.
#'
#' @param nc_file      Character. Path to \code{burn_viirs_YYYYMM.nc}.
#' @param domain_raster SpatRaster or path.  Must contain a \code{pid} layer.
#' @param month_start  Date or "YYYY-MM-DD".
#' @param out_dir      Character. Output directory for parquet files.
#' @param verbose      Logical.
#'
#' @return Character path to the parquet file, or a \code{.skip} path if no
#'   burned pixels are found.
#' @export
burn_date_viirs_netcdf_to_parquet <- function(
    netcdf_directory,
    domain_raster,
    month_start,
    out_dir  = "data/target_outputs/burn_dates_viirs",
    cleanup  = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose  = TRUE) {

  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  # Use a per-branch terra tempdir to prevent race conditions between parallel workers.
  terra_tmp <- file.path(getwd(), "data/temp/terra", yyyymm)
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terra::terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  nc_paths <- list.files(netcdf_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)

  if (length(nc_paths) == 0) {
    if (verbose) message("No VIIRS NetCDF files found for ", yyyymm)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    skip_file <- file.path(out_dir, paste0("burn_date_viirs_", yyyymm, ".skip"))
    writeLines(
      c(paste("Month:", yyyymm), "Reason: No NetCDF files available", paste("Timestamp:", Sys.time())),
      con = skip_file
    )
    return(skip_file)
  }

  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))

  pid_raster <- domain_template[["pid"]]
  valid_pids <- terra::values(pid_raster)[, 1] |> na.omit() |> unique()

  if (verbose) message("Processing ", length(nc_paths), " VIIRS NetCDF files for ", yyyymm)

  # extract_burn_date_observations() is shared with the MODIS pipeline;
  # nearest-neighbour reprojection handles the 375m → 500m resampling automatically
  obs_list <- purrr::map(nc_paths, function(nc_path) {
    tryCatch(
      extract_burn_date_observations(
        nc_path         = nc_path,
        domain_template = domain_template,
        month_start     = month_start,
        verbose         = verbose
      ),
      error = function(e) {
        warning("Failed to process ", basename(nc_path), ": ", conditionMessage(e))
        NULL
      }
    )
  })

  df <- obs_list |>
    purrr::compact() |>
    dplyr::bind_rows() |>
    dplyr::filter(.data$pid %in% valid_pids) |>
    dplyr::filter(.data$burn_doy > 0L) |>
    dplyr::filter(!is.na(.data$date))

  if (nrow(df) == 0) {
    if (verbose) message("No VIIRS burned pixels found for ", yyyymm)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    skip_file <- file.path(out_dir, paste0("burn_date_viirs_", yyyymm, ".skip"))
    writeLines(c(paste("Month:", yyyymm), "Reason: No burned pixels after QA"), con = skip_file)
    if (cleanup) unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    return(skip_file)
  }

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  parquet_file <- file.path(out_dir, paste0("burn_date_viirs_", yyyymm, ".parquet"))
  unlink(parquet_file)

  arrow::write_parquet(df, sink = parquet_file, compression = "gzip")

  if (verbose) {
    message(
      "Wrote ", nrow(df), " VIIRS burned pixels for ", yyyymm,
      " → ", basename(parquet_file)
    )
  }

  if (cleanup) {
    unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }

  parquet_file
}


#' @title Check which months of VIIRS burn dates need downloading
#'
#' @description Thin wrapper around \code{identify_missing_vi()} for the VIIRS
#'   naming convention. VIIRS data begins January 2012.
#'
#' @param output_dir  Character. Directory where monthly VIIRS burn date parquets live.
#' @param start_date  Character "YYYY-MM-DD". Defaults to VNP64A1 first available month.
#' @param end_date    Character "YYYY-MM-DD". Defaults to today.
#'
#' @return Data frame with columns month_start, month_end, date_str.
#' @export
identify_missing_burn_dates_viirs <- function(
    output_dir  = "data/target_outputs/burn_dates_viirs",
    start_date  = "2012-01-01",   # VNP64A1 first available data
    end_date    = NULL) {

  missing <- find_missing_months(
    output_dir = output_dir,
    dataset    = "burn_viirs",
    start_date = start_date,
    end_date   = end_date
  )

  # Always include the current month — VNP64A1 has ~2-month lag so the most
  # recent parquet may be stale even if the file exists.
  today               <- Sys.Date()
  current_month_start <- as.Date(paste0(format(today, "%Y-%m"), "-01"))
  current_month_end   <- as.Date(paste0(format(today + 31, "%Y-%m"), "-01")) - 1
  current_month_str   <- format(current_month_start, "%Y-%m")
  if (!any(missing$date_str == current_month_str)) {
    missing <- rbind(missing, data.frame(
      month_start = current_month_start,
      month_end   = current_month_end,
      date_str    = current_month_str
    ))
  }

  missing
}
