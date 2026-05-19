# ============================================================================
# MODIS Burned Area (MCD64A1) Download via AppEEARS
# ============================================================================
# Downloads monthly MODIS MCD64A1.061 burned area data from NASA AppEEARS.
# Mirrors the structure of get_modis_vi.R for consistency.
#
# MCD64A1.061 product details:
#   - Spatial resolution: 500m
#   - Temporal coverage: November 2000 – present
#   - Layers used: Burn Date (day-of-year), QA (quality assurance)
#   - Combined Terra + Aqua burned area detection
#
# Output parquet schema (one row per burned pixel per month):
#   pid      (int32)  : Pixel ID from domain grid
#   date     (int32)  : Burn date as days since 1970-01-01 (0 = unburned this month)
#   burn_doy (int16)  : Raw burn day-of-year (0 = unburned, 1–366 = burn date)
#   qa       (int8)   : QA flag (0 = good, see MCD64A1 documentation)
# ============================================================================


#' @title Submit monthly MODIS burned area request via AppEEARS
#'
#' @description Submits an AppEEARS area request for MCD64A1.061 (Burn Date + QA)
#'   for a single calendar month. Returns the AppEEARS task ID for polling.
#'
#' @param domain_vector An sf or SpatVector polygon defining the study domain.
#' @param month_start Date. First day of the month to request (e.g., as.Date("2020-01-01")).
#' @param month_end   Date. Last day of the month to request.
#' @param verbose     Logical. Print progress messages? Default TRUE.
#'
#' @return Character string: AppEEARS task ID.
#' @export
submit_burn_date_modis_task <- function(
    domain_vector,
    month_start,
    month_end,
    verbose = TRUE) {

  month_start <- as.Date(month_start)
  month_end   <- as.Date(month_end)

  if (verbose) {
    message(
      "Submitting MODIS burn date task: ",
      format(month_start, "%Y-%m-%d"), " to ", format(month_end, "%Y-%m-%d")
    )
  }

  # Simplify and reproject domain to WGS84 GeoJSON (required by AppEEARS)
  domain_geojson <- domain_vector |>
    sf::st_as_sf() |>
    sf::st_simplify(dTolerance = 100, preserveTopology = TRUE) |>
    sf::st_buffer(0) |>
    sf::st_make_valid() |>
    sf::st_transform(crs = 4326) |>
    geojsonsf::sf_geojson(simplify = FALSE) |>
    jsonlite::fromJSON()

  # Build AppEEARS request for MCD64A1 Burn Date and QA layers
  req <- list(
    task_type = "area",
    task_name = paste0("MODIS_BurnDate_", format(month_start, "%Y%m"), "_", format(Sys.time(), "%H%M%S")),
    params = list(
      dates = list(list(
        startDate = format(month_start, "%m-%d-%Y"),
        endDate   = format(month_end,   "%m-%d-%Y")
      )),
      layers = list(
        # Burn Date: day-of-year (1–366) on which burn was detected; 0 = unburned
        list(product = "MCD64A1.061", layer = "Burn_Date"),
        # QA: per-pixel quality flag (0 = good quality)
        list(product = "MCD64A1.061", layer = "QA")
      ),
      output = list(
        format     = list(type = "netcdf4"),
        projection = "native"   # keep native MODIS sinusoidal; we reproject during processing
      ),
      geo = domain_geojson
    )
  )

  # Submit and return task ID
  task <- appeears::rs_request(
    request  = req,
    user     = Sys.getenv("EARTHDATA_USER"),
    transfer = FALSE,
    verbose  = verbose
  )

  task_id <- task$get_task_id()
  if (verbose) message("MODIS burn date task submitted: ", task_id)
  task_id
}


#' @title Download MODIS burned area NetCDF files from AppEEARS
#'
#' @description Polls AppEEARS until the task completes, then downloads the
#'   resulting NetCDF files. Creates a marker file so the month is skipped on
#'   subsequent runs. Mirrors \code{download_modis_vi_netcdf()} in structure.
#'
#' @param task_id      Character. AppEEARS task ID (from \code{submit_burn_date_modis_task}).
#' @param month_start  Date. First day of the month (used for naming marker files).
#' @param temp_directory Character. Directory to download raw NetCDF files into.
#' @param cleanup      Logical. Delete temp files after conversion? Defaults to
#'   TRUE on GitHub Actions, FALSE locally.
#' @param verbose      Logical. Print progress messages? Default TRUE.
#'
#' @return Character path to the temp directory containing downloaded NetCDF files.
#' @export
download_burn_date_modis_netcdf <- function(
    task_id,
    month_start,
    temp_directory = "data/temp/appeears/burn_dates_modis/",
    cleanup        = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose        = TRUE) {

  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  # If a marker file already exists for this month, skip re-downloading
  marker_dir  <- "data/target_outputs/burn_dates_modis"
  marker_file <- file.path(marker_dir, paste0("burn_date_modis_", yyyymm, "_monthly.nc"))
  dir.create(marker_dir, recursive = TRUE, showWarnings = FALSE)

  if (file.exists(marker_file)) {
    if (verbose) message("Burn date marker exists for ", yyyymm, " — skipping download")
    dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
    return(temp_directory)
  }

  # Each branch gets its own month-specific subdirectory to prevent race
  # conditions when parallel tar_make_future() workers share base temp_directory.
  temp_directory <- file.path(temp_directory, yyyymm)
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  # Poll AppEEARS until task is done (max 2 hours at 60-second intervals)
  if (verbose) message("Polling AppEEARS task ", task_id, " ...")

  poll_result <- purrr::reduce(
    .x  = seq_len(120),      # up to 120 retries
    .f  = function(status, i) {
      if (status %in% c("done", "failed", "error")) return(status)

      task_info   <- appeears::rs_list_task(task_id = task_id, user = Sys.getenv("EARTHDATA_USER"))
      task_status <- task_info$status

      if (task_status %in% c("done", "failed", "error")) {
        if (verbose) message("Task status: ", task_status, " (attempt ", i, ")")
        return(task_status)
      }

      if (verbose && i %% 10 == 0) {
        message("Task status: ", task_status, " (", i, "/120 checks)")
      }
      Sys.sleep(60)
      task_status
    },
    .init = "pending"
  )

  if (poll_result %in% c("failed", "error")) {
    stop("AppEEARS task ", task_id, " failed with status: ", poll_result)
  }
  if (poll_result != "done") {
    stop("Task ", task_id, " polling timed out after 120 minutes")
  }

  # Download completed files
  if (verbose) message("Downloading burn date files for task: ", task_id)
  appeears::rs_transfer(
    task_id = task_id,
    user    = Sys.getenv("EARTHDATA_USER"),
    path    = temp_directory,
    verbose = verbose
  )

  # Verify at least one NetCDF was returned
  nc_paths <- list.files(temp_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)
  if (length(nc_paths) == 0) {
    if (verbose) message("No NetCDF files returned for month ", yyyymm, " — creating skip marker")
    writeLines(
      c(paste("Month:", yyyymm), paste("Reason: No NetCDF returned"), paste("Timestamp:", Sys.time())),
      con = marker_file
    )
    return(temp_directory)
  }

  if (verbose) message("Downloaded ", length(nc_paths), " NetCDF files for ", yyyymm)

  # Write marker so this month is not re-downloaded
  cat("", file = marker_file)
  if (verbose) message("Created download marker: ", marker_file)

  temp_directory
}


#' @title Convert MODIS burned area NetCDF to parquet
#'
#' @description Reads MCD64A1 Burn_Date and QA layers from AppEEARS NetCDF output,
#'   reprojects to the domain grid, applies QA masking, and writes a tidy parquet file.
#'
#'   Only pixels that actually burned (burn_doy > 0) are written to the parquet file,
#'   keeping file sizes small. Unburned pixels are implicitly absent.
#'
#' @param netcdf_directory Character. Path to directory with downloaded NetCDF files.
#' @param domain_raster    SpatRaster or file path to domain.nc (must have a 'pid' layer).
#' @param month_start      Date. First day of the month (used for output filename and date conversion).
#' @param out_dir          Character. Output directory for parquet files.
#' @param cleanup          Logical. Delete temp NetCDF files after writing parquet?
#' @param verbose          Logical. Print progress messages? Default TRUE.
#'
#' @return Character path to the output parquet file, or a skip marker path if no data.
#' @export
burn_date_modis_netcdf_to_parquet <- function(
    netcdf_directory,
    domain_raster,
    month_start,
    out_dir  = "data/target_outputs/burn_dates_modis",
    cleanup  = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose  = TRUE) {

  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  # Use a per-branch terra tempdir to prevent race conditions between parallel workers.
  terra_tmp <- file.path(getwd(), "data/temp/terra", yyyymm)
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terra::terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  # Locate NetCDF files
  nc_paths <- list.files(netcdf_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)

  if (length(nc_paths) == 0) {
    if (verbose) message("No NetCDF files found for ", yyyymm, " — writing skip marker")
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    skip_file <- file.path(out_dir, paste0("burn_date_modis_", yyyymm, ".skip"))
    writeLines(
      c(paste("Month:", yyyymm), "Reason: No NetCDF files available", paste("Timestamp:", Sys.time())),
      con = skip_file
    )
    return(skip_file)
  }

  # Load domain template for reprojection and pid extraction
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))

  pid_raster  <- domain_template[["pid"]]
  valid_pids  <- terra::values(pid_raster)[, 1] |> na.omit() |> unique()
  year_int    <- as.integer(format(month_start, "%Y"))

  if (verbose) message("Processing ", length(nc_paths), " NetCDF files for ", yyyymm)

  # Process each NetCDF file and extract burned-pixel observations.
  # MCD64A1 is a monthly composite so there is typically one file per request,
  # but we handle multiple files defensively (tile-based downloads).
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

  # Combine results, filter to domain pixels only, and drop unburned pixels
  df <- obs_list |>
    purrr::compact() |>                              # drop NULLs
    dplyr::bind_rows() |>
    dplyr::filter(.data$pid %in% valid_pids) |>      # restrict to domain
    dplyr::filter(.data$burn_doy > 0L) |>            # keep only burned pixels
    dplyr::filter(!is.na(.data$date))                # drop any failed date conversions

  if (nrow(df) == 0) {
    if (verbose) message("No burned pixels found for ", yyyymm, " — writing skip marker")
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    skip_file <- file.path(out_dir, paste0("burn_date_modis_", yyyymm, ".skip"))
    writeLines(
      c(paste("Month:", yyyymm), "Reason: No burned pixels after QA filtering", paste("Timestamp:", Sys.time())),
      con = skip_file
    )
    if (cleanup) unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    return(skip_file)
  }

  # Write parquet with gzip compression
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  parquet_file <- file.path(out_dir, paste0("burn_date_modis_", yyyymm, ".parquet"))
  unlink(parquet_file)

  arrow::write_parquet(df, sink = parquet_file, compression = "gzip")

  if (verbose) {
    message(
      "Wrote ", nrow(df), " burned pixels for ", yyyymm,
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


# ============================================================================
# Internal helper: extract observations from a single MCD64A1 NetCDF file
# ============================================================================

#' @title Extract burn date observations from one MCD64A1 NetCDF file
#'
#' @description Reads Burn_Date and QA layers, reprojects to domain grid, converts
#'   burn day-of-year to a calendar date (days since 1970-01-01), and returns a
#'   tidy tibble. Only pixels where QA == 0 (good quality) are kept.
#'
#' @param nc_path         Character. Path to a single NetCDF file.
#' @param domain_template SpatRaster. Domain grid defining output CRS and extent.
#' @param month_start     Date. Used to convert day-of-year to a calendar date.
#' @param verbose         Logical. Print progress messages?
#'
#' @return A tibble with columns pid, date, burn_doy, qa.  Returns NULL on failure.
#' @keywords internal
extract_burn_date_observations <- function(
    nc_path,
    domain_template,
    month_start,
    verbose = TRUE) {

  rast_obj <- terra::rast(nc_path)

  # Locate Burn_Date and QA layers (case-insensitive search)
  burn_idx <- which(grepl("Burn_Date|BurnDate|burn_date", names(rast_obj), ignore.case = TRUE))[1]
  qa_idx   <- which(grepl("^QA$|quality", names(rast_obj), ignore.case = TRUE))[1]

  if (is.na(burn_idx) || is.na(qa_idx)) {
    if (verbose) warning("Missing Burn_Date or QA layer in ", basename(nc_path), " — skipping")
    return(NULL)
  }

  # Reproject both layers to domain grid (nearest-neighbour to preserve integer codes)
  burn_r <- terra::project(rast_obj[[burn_idx]], domain_template, method = "near")
  qa_r   <- terra::project(rast_obj[[qa_idx]],   domain_template, method = "near")

  pid_r  <- domain_template[["pid"]]

  # Vectorise all layers into a flat tibble for tidy processing
  df <- tibble::tibble(
    pid      = as.integer(terra::values(pid_r)[, 1]),
    burn_doy = as.integer(terra::values(burn_r)[, 1]),
    qa       = as.integer(terra::values(qa_r)[, 1])
  ) |>
    # Remove pixels outside domain (NA pid) and apply QA filter (keep qa == 0 only)
    dplyr::filter(!is.na(.data$pid), !is.na(.data$burn_doy), !is.na(.data$qa)) |>
    dplyr::filter(.data$qa == 0L) |>
    # Convert burn day-of-year to calendar date (days since 1970-01-01).
    # burn_doy 0 = unburned; 1–366 = day within the year of month_start.
    dplyr::mutate(
      date = dplyr::if_else(
        .data$burn_doy > 0L,
        as.integer(
          as.Date(paste0(format(month_start, "%Y"), "-01-01")) +
            (.data$burn_doy - 1L) -
            as.Date("1970-01-01")
        ),
        NA_integer_
      )
    ) |>
    dplyr::select("pid", "date", "burn_doy", "qa")

  if (verbose) message("Extracted ", nrow(df), " observations from ", basename(nc_path))
  df
}


#' @title Check which months of MODIS burn dates need downloading
#'
#' @description Compares the full monthly sequence (November 2000 – today) against
#'   existing parquet files in \code{output_dir} and returns only the missing months.
#'   A thin wrapper around \code{identify_missing_vi()} using the burn date naming convention.
#'
#' @param output_dir  Character. Directory where monthly burn date parquet files live.
#' @param start_date  Character "YYYY-MM-DD". Defaults to MCD64A1 first available month.
#' @param end_date    Character "YYYY-MM-DD". Defaults to today.
#'
#' @return Data frame with columns month_start, month_end, date_str (YYYYMM).
#' @export
identify_missing_burn_dates_modis <- function(
    output_dir  = "data/target_outputs/burn_dates_modis",
    start_date  = "2000-11-01",   # MCD64A1 first available data
    end_date    = NULL) {

  # Reuse the generic VI helper; just change the pattern prefix
  missing <- identify_missing_vi(
    output_dir = output_dir,
    dataset    = "burn_date_modis",
    start_date = start_date,
    end_date   = end_date
  )

  # Always include the current month — MCD64A1 has ~2-month lag so the most
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
