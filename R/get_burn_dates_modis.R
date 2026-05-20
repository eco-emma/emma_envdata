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

  # If the grid NC for this month already exists, skip re-downloading.
  # burn_modis_netcdf_to_grid() writes burn_modis_YYYYMM.nc when it completes.
  marker_dir  <- "data/target_outputs/burn_dates_modis"
  dir.create(marker_dir, recursive = TRUE, showWarnings = FALSE)
  grid_nc_done <- file.path(marker_dir, paste0("burn_modis_", yyyymm, ".nc"))

  if (file.exists(grid_nc_done)) {
    if (verbose) message("Grid NC found for ", yyyymm, " — skipping AppEEARS download")
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
    skip_file <- file.path(marker_dir, paste0("burn_modis_", yyyymm, ".skip"))
    writeLines(
      c(paste("Month:", yyyymm), paste("Reason: No NetCDF returned"), paste("Timestamp:", Sys.time())),
      con = skip_file
    )
    return(skip_file)
  }

  if (verbose) message("Downloaded ", length(nc_paths), " NetCDF files for ", yyyymm)

  # Return temp directory so burn_modis_netcdf_to_grid() can access the files.
  # No sentinel NC is written here; the grid NC written by burn_modis_netcdf_to_grid()
  # acts as the persistent marker that prevents re-downloading.
  temp_directory
}


#' @title Convert MODIS burned area NetCDF tiles to a domain-aligned raster grid
#' @description Processes raw AppEEARS NetCDF downloads for one month: reprojects
#'   MCD64A1 Burn_Date tiles to the domain grid, applies QA masking (qa == 0
#'   pixels only), mosaics spatial tiles, and writes a single NetCDF containing
#'   a \code{burn_doy} variable.  Months with no burned pixels are still written
#'   as all-NA so that \code{find_missing_months()} treats them as complete.
#'
#' @param netcdf_directory Character.  Path to AppEEARS temp directory, or a
#'   \code{.skip} path returned when no data were available.
#' @param domain_raster Character path or SpatRaster with a \code{pid} layer.
#' @param month_start Date or "YYYY-MM-DD".  First day of the month.
#' @param out_dir Character.  Output directory for the grid NC file.
#' @param cleanup Logical.  Delete raw temp files after writing?
#' @param verbose Logical.  Print progress messages?
#'
#' @return Character path to \code{burn_modis_YYYYMM.nc}.
#' @export
burn_modis_netcdf_to_grid <- function(
  netcdf_directory,
  domain_raster,
  month_start,
  out_dir  = "data/target_outputs/burn_dates_modis/",
  cleanup  = Sys.getenv("GITHUB_ACTIONS") == "true",
  verbose  = TRUE
) {
  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  terra_tmp <- file.path(getwd(), "data/temp/terra", yyyymm)
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terra::terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_nc <- file.path(out_dir, paste0("burn_modis_", yyyymm, ".nc"))

  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))

  # Helper: write all-NA NC so find_missing_months() treats this month as done
  write_empty_nc <- function() {
    empty_r <- terra::setValues(domain_template[[1]], NA_real_)
    terra::time(empty_r) <- month_start
    terra::writeCDF(empty_r, out_nc,
                    varname  = "burn_doy",
                    longname = "Burn day of year (MCD64A1, no data)",
                    overwrite = TRUE, verbose = FALSE)
  }

  # Resolve source NCs
  nc_paths <- character(0)
  if (!grepl("\\.skip$", netcdf_directory) && dir.exists(netcdf_directory)) {
    nc_paths <- list.files(netcdf_directory, pattern = "\\.nc$",
                           full.names = TRUE, recursive = TRUE)
  }

  if (length(nc_paths) == 0L) {
    if (verbose) message("No burn NCs for ", yyyymm, " — writing all-NA grid")
    write_empty_nc()
    if (cleanup && !grepl("\\.skip$", netcdf_directory) && dir.exists(netcdf_directory)) {
      unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    }
    return(out_nc)
  }

  # Reproject each tile to domain; apply QA mask (keep qa == 0 only)
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
    if (verbose) message("All tiles empty after QA for ", yyyymm, " — writing all-NA grid")
    write_empty_nc()
    if (cleanup) unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    return(out_nc)
  }

  # Mosaic spatial tiles (first non-NA wins) and mask to domain pixels
  burn_mosaic <- if (length(burn_tiles) == 1L) {
    burn_tiles[[1L]]
  } else {
    do.call(terra::mosaic, c(burn_tiles, list(fun = "first")))
  }
  domain_mask <- !is.na(domain_template[["pid"]])
  burn_mosaic <- terra::mask(burn_mosaic, domain_mask, maskvalue = FALSE)

  # Write NC with burn_doy variable and a time dimension = month_start
  terra::time(burn_mosaic) <- month_start
  terra::writeCDF(burn_mosaic, out_nc,
                  varname  = "burn_doy",
                  longname = "Burn day of year (MCD64A1, QA=0)",
                  overwrite = TRUE, verbose = FALSE)

  if (verbose) message("Wrote burn grid NC: ", basename(out_nc))

  if (cleanup) {
    unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }

  out_nc
}


#' @title Convert MODIS burned area NetCDF to parquet
#'
#' @description Reads \code{burn_doy} from the domain-aligned NC produced by
#'   \code{burn_modis_netcdf_to_grid()} and writes a tidy parquet with one row
#'   per burned pixel.  QA filtering was already applied in the grid step, so
#'   all rows have qa = 0.
#'
#' @param nc_file      Character. Path to \code{burn_modis_YYYYMM.nc}.
#' @param domain_raster SpatRaster or path.  Must contain a \code{pid} layer.
#' @param month_start  Date or "YYYY-MM-DD".  First day of the month.
#' @param out_dir      Character. Output directory for parquet files.
#' @param verbose      Logical. Print progress messages?
#'
#' @return Character path to the parquet file, or a \code{.skip} path if no
#'   burned pixels are found.
#' @export
burn_date_modis_netcdf_to_parquet <- function(
  nc_file,
  domain_raster,
  month_start,
  out_dir  = "data/target_outputs/burn_dates_modis",
  verbose  = TRUE
) {
  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))
  pid_vec      <- terra::values(domain_template[["pid"]])[, 1]
  ref_year     <- as.integer(format(month_start, "%Y"))
  year_start_epoch <- as.integer(as.Date(paste0(ref_year, "-01-01")) - as.Date("1970-01-01"))

  # Read burn_doy from the grid NC produced by burn_modis_netcdf_to_grid()
  burn_r <- tryCatch(
    terra::rast(nc_file, subds = "burn_doy"),
    error = function(e) {
      warning("Could not read burn_doy from ", basename(nc_file), ": ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(burn_r)) {
    skip_file <- file.path(out_dir, paste0("burn_date_modis_", yyyymm, ".skip"))
    writeLines(c(paste("Month:", yyyymm), "Reason: Could not read grid NC",
                 paste("Timestamp:", Sys.time())), skip_file)
    return(skip_file)
  }

  # Vectorise: one row per burned pixel (burn_doy > 0) per time step
  n_layers <- terra::nlyr(burn_r)
  obs_list <- vector("list", n_layers)
  for (ti in seq_len(n_layers)) {
    doy_v <- terra::values(burn_r[[ti]])[, 1]
    valid <- !is.na(pid_vec) & !is.na(doy_v) & doy_v > 0L
    if (!any(valid)) next
    epoch_dates <- as.integer(year_start_epoch + as.integer(doy_v[valid]) - 1L)
    obs_list[[ti]] <- tibble::tibble(
      pid      = as.integer(pid_vec[valid]),
      date     = epoch_dates,
      burn_doy = as.integer(doy_v[valid]),
      qa       = 0L   # QA filtering was applied in burn_modis_netcdf_to_grid()
    )
  }

  df <- dplyr::bind_rows(purrr::compact(obs_list))

  if (nrow(df) == 0L) {
    if (verbose) message("No burned pixels for ", yyyymm, " — writing skip marker")
    skip_file <- file.path(out_dir, paste0("burn_date_modis_", yyyymm, ".skip"))
    writeLines(c(paste("Month:", yyyymm), "Reason: No burned pixels (burn_doy = 0)",
                 paste("Timestamp:", Sys.time())), skip_file)
    return(skip_file)
  }

  parquet_file <- file.path(out_dir, paste0("burn_date_modis_", yyyymm, ".parquet"))
  unlink(parquet_file)
  arrow::write_parquet(df, sink = parquet_file, compression = "gzip")
  if (verbose) message("Wrote ", nrow(df), " burned pixels → ", basename(parquet_file))

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
  missing <- find_missing_months(
    output_dir = output_dir,
    dataset    = "burn_modis",
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
