# ============================================================================
# VIIRS Burned Area (VNP64A1) Download via AppEEARS
# ============================================================================
# Downloads monthly VIIRS VNP64A1.001 burned area data from NASA AppEEARS.
# Structurally identical to get_burn_dates_modis.R — read that file first
# for design rationale and the shared output schema.
#
# VNP64A1.001 product details:
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
#' @description Submits a VNP64A1.001 area request for a single calendar month.
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
        list(product = "VNP64A1.001", layer = "Burn_Date"),
        list(product = "VNP64A1.001", layer = "QA")
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
#' @param temp_directory Character. Download directory.
#' @param cleanup      Logical. Delete temp files after conversion?
#' @param verbose      Logical. Print progress messages?
#'
#' @return Character path to temp directory containing downloaded NetCDF files.
#' @export
download_burn_date_viirs_netcdf <- function(
    task_id,
    month_start,
    temp_directory = "data/temp/raw_data/burn_dates_viirs/",
    cleanup        = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose        = TRUE) {

  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  # Skip if already downloaded (marker file present)
  marker_dir  <- "data/target_outputs/burn_dates_viirs"
  marker_file <- file.path(marker_dir, paste0("burn_date_viirs_", yyyymm, "_monthly.nc"))
  dir.create(marker_dir,      recursive = TRUE, showWarnings = FALSE)
  dir.create(temp_directory,  recursive = TRUE, showWarnings = FALSE)

  if (file.exists(marker_file)) {
    if (verbose) message("VIIRS burn date marker exists for ", yyyymm, " — skipping")
    return(temp_directory)
  }

  # Each branch gets its own month-specific subdirectory to prevent race
  # conditions when parallel tar_make_future() workers share base temp_directory.
  temp_directory <- file.path(temp_directory, yyyymm)
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  # Poll AppEEARS for up to 2 hours
  if (verbose) message("Polling AppEEARS task ", task_id, " ...")

  poll_result <- purrr::reduce(
    .x    = seq_len(120),
    .f    = function(status, i) {
      if (status %in% c("done", "failed", "error")) return(status)
      task_info   <- appeears::rs_list_task(task_id = task_id, user = Sys.getenv("EARTHDATA_USER"))
      task_status <- task_info$status
      if (task_status %in% c("done", "failed", "error")) return(task_status)
      if (verbose && i %% 10 == 0) message("Status: ", task_status, " (", i, "/120)")
      Sys.sleep(60)
      task_status
    },
    .init = "pending"
  )

  if (poll_result %in% c("failed", "error")) {
    stop("AppEEARS task ", task_id, " failed: ", poll_result)
  }
  if (poll_result != "done") {
    stop("Task ", task_id, " timed out after 120 minutes")
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
    writeLines(
      c(paste("Month:", yyyymm), "Reason: No NetCDF returned from AppEEARS", paste("Timestamp:", Sys.time())),
      con = marker_file
    )
    return(temp_directory)
  }

  if (verbose) message("Downloaded ", length(nc_paths), " VIIRS NetCDF files for ", yyyymm)
  cat("", file = marker_file)
  temp_directory
}


#' @title Convert VIIRS burned area NetCDF to parquet
#'
#' @description Identical workflow to \code{burn_date_modis_netcdf_to_parquet()}.
#'   Reads VNP64A1 Burn_Date + QA layers, reprojects to domain, filters to
#'   burned pixels, and writes a tidy parquet file.
#'
#'   VIIRS 375m pixels are resampled to the 500m domain grid using nearest-neighbour
#'   before extracting values (done inside \code{extract_burn_date_observations()}).
#'
#' @param netcdf_directory Character. Path to downloaded NetCDF files.
#' @param domain_raster    SpatRaster or file path to domain.nc.
#' @param month_start      Date. First day of the month.
#' @param out_dir          Character. Output directory for parquet files.
#' @param cleanup          Logical. Delete temp files after writing parquet?
#' @param verbose          Logical. Print progress messages?
#'
#' @return Character path to the output parquet file, or a skip marker path.
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

  identify_missing_vi(
    output_dir = output_dir,
    dataset    = "burn_date_viirs",
    start_date = start_date,
    end_date   = end_date
  )
}
