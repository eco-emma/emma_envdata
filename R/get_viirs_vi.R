# ============================================================================
# VIIRS Vegetation Index (VNP13A1 / VJ113A1) Download via AppEEARS
# ============================================================================
# Downloads monthly VIIRS 16-day EVI composites from NASA AppEEARS.
# Structurally identical to get_modis_vi.R — read that file first for design
# rationale and the shared output schema.
#
# Products used:
#   VNP13A1.002 — Suomi NPP VIIRS, 500m 16-day, 2012-01-19 to present
#   VJ113A1.002 — NOAA-20  VIIRS, 500m 16-day, 2018-01-01 to present
#
# Key differences from MODIS VI:
#   - Layer key prefix: "500_m_16_days_" (vs MODIS "_500m_16_days_")
#   - Sensor detection: NC global attr contains "VJ1" -> noaa20, else snpp
#   - Output NCs: vi_viirs_YYYYMM_snpp.nc / vi_viirs_YYYYMM_noaa20.nc
#   - Parquet variable codes: 3 = snpp, 4 = noaa20  (MODIS uses 1 = terra, 2 = aqua)
# ============================================================================


#' @title Submit monthly VIIRS VI request via AppEEARS
#'
#' @description Submits an AppEEARS area request for VNP13A1.002 (S-NPP) and
#'   VJ113A1.002 (NOAA-20) EVI, VI Quality, and composite day-of-year (500 m,
#'   16-day composites) for a single calendar month.
#'
#' @param domain_vector A SpatVector or sf polygon defining the study domain.
#' @param month_start   Date or "YYYY-MM-DD". First day of the month.
#' @param month_end     Date or "YYYY-MM-DD". Last day of the month.
#' @param verbose       Logical. Print progress messages? Default TRUE.
#'
#' @return Character string with AppEEARS task ID.
#' @export
submit_viirs_vi <- function(
    domain_vector,
    month_start,
    month_end,
    verbose = TRUE) {

  ensure_appeears_auth()
  month_start <- as.Date(month_start)
  month_end   <- as.Date(month_end)

  if (verbose) {
    message("AppEEARS VIIRS VI monthly request: ",
            format(month_start, "%Y-%m-%d"), " to ", format(month_end, "%Y-%m-%d"))
  }

  domain_sf <- sf::st_as_sf(domain_vector) |>
    sf::st_simplify(dTolerance = 100, preserveTopology = TRUE) |>
    sf::st_buffer(0) |>
    sf::st_make_valid() |>
    sf::st_transform(crs = 4326) |>
    geojsonsf::sf_geojson(simplify = FALSE) |>
    jsonlite::fromJSON()

  # Default VIIRS layer key strings (verified against AppEEARS API 2026-05)
  # Note: VIIRS uses "500_m_16_days_" prefix; MODIS uses "_500m_16_days_"
  evi_layer  <- "500_m_16_days_EVI"
  qa_layer   <- "500_m_16_days_VI_Quality"
  date_layer <- "500_m_16_days_composite_day_of_the_year"

  # Attempt dynamic resolution from AppEEARS — falls back to hard-coded names
  try({
    lyr <- appeears::rs_layers("VNP13A1.002")
    cand_cols <- intersect(c("Layer", "Name", "layer", "name"), names(lyr))
    if (length(cand_cols)) {
      vals <- unlist(lapply(cand_cols, function(cc) lyr[[cc]]))
      evi_cand  <- vals[grepl("^500_m.*EVI$",                          vals)][1]
      qa_cand   <- vals[grepl("VI_Quality",                             vals, ignore.case = TRUE)][1]
      date_cand <- vals[grepl("composite_day_of_the_year",              vals, ignore.case = TRUE)][1]
      if (!is.na(evi_cand))  evi_layer  <- evi_cand
      if (!is.na(qa_cand))   qa_layer   <- qa_cand
      if (!is.na(date_cand)) date_layer <- date_cand
    }
  }, silent = TRUE)

  if (verbose) message("Using layers: ", evi_layer, ", ", qa_layer, ", ", date_layer)

  req <- list(
    task_type = "area",
    task_name = paste0("VIIRS_VI_", format(month_start, "%Y%m"), "_",
                       format(Sys.time(), "%H%M%S")),
    params = list(
      dates = list(list(
        startDate = format(month_start, "%m-%d-%Y"),
        endDate   = format(month_end,   "%m-%d-%Y")
      )),
      layers = list(
        # VNP13A1.002 — Suomi NPP
        list(product = "VNP13A1.002", layer = evi_layer),
        list(product = "VNP13A1.002", layer = qa_layer),
        list(product = "VNP13A1.002", layer = date_layer),
        # VJ113A1.002 — NOAA-20
        list(product = "VJ113A1.002", layer = evi_layer),
        list(product = "VJ113A1.002", layer = qa_layer),
        list(product = "VJ113A1.002", layer = date_layer)
      ),
      output = list(
        format     = list(type = "netcdf4"),
        projection = "native"
      ),
      geo = domain_sf
    )
  )

  if (verbose) message("Submitting AppEEARS VIIRS VI monthly task...")
  task <- appeears::rs_request(
    request  = req,
    user     = Sys.getenv("EARTHDATA_USER"),
    transfer = FALSE,
    verbose  = verbose
  )

  task_id <- task$get_task_id()
  if (verbose) message("Task submitted with ID: ", task_id)
  task_id
}


#' @title Download VIIRS VI NetCDF files from AppEEARS
#'
#' @description Polls for AppEEARS task completion and downloads result NCs.
#'   Separates I/O from computation for independent parallelisation.
#'   If the task is not found (e.g. expired after the 14-day retention window),
#'   and domain_vector plus month_end are supplied, the task is automatically
#'   re-submitted.
#'
#' @param task_id        Character. AppEEARS task ID.
#' @param month_start    Date or "YYYY-MM-DD". First day of the month.
#' @param domain_vector  SpatVector or sf polygon used to re-submit if the task
#'   has expired. Optional; if NULL a missing-status error is raised instead.
#' @param month_end      Date or "YYYY-MM-DD". Last day of the month. Required
#'   only when domain_vector is provided for automatic re-submission.
#' @param temp_directory Temporary working directory for downloads.
#' @param cleanup        Logical. Delete temp files after grid NC is written?
#'   Defaults to TRUE on GitHub Actions.
#' @param verbose        Logical. Print progress messages? Default TRUE.
#'
#' @return Character path to temp directory containing downloaded NCs, or
#'   path to a \code{.skip} marker when AppEEARS returned no data.
#' @export
download_viirs_vi_netcdf <- function(
    task_id,
    month_start,
    domain_vector  = NULL,
    month_end      = NULL,
    temp_directory = "data/temp/appeears/viirs_vi/",
    cleanup        = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose        = TRUE) {

  ensure_appeears_auth()
  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  cache_dir <- "data/target_outputs/viirs_vi"
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  # Early-exit: snpp NC written by vi_viirs_netcdf_to_grid() signals completion
  snpp_nc_done <- file.path(cache_dir, paste0("vi_viirs_", yyyymm, "_snpp.nc"))
  if (file.exists(snpp_nc_done)) {
    if (verbose) message("Grid NC found for ", yyyymm, " — skipping AppEEARS download")
    dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
    return(temp_directory)
  }

  # Per-branch subdir to avoid race conditions under parallel tar_make_future()
  temp_directory <- file.path(temp_directory, yyyymm)
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  if (verbose) message("Polling task ", task_id, " for completion...")
  max_retries <- 15  # 15 minutes at 60s intervals; error = "continue" on target handles retry
  retry_count <- 0L
  null_retries <- 0L  # consecutive null-status responses; AppEEARS may lag ~1-2 min after submission

  repeat {
    retry_count <- retry_count + 1L
    task_info   <- appeears::rs_list_task(task_id = task_id,
                                          user     = Sys.getenv("EARTHDATA_USER"))
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
        task_id     <- submit_viirs_vi(
          domain_vector = domain_vector,
          month_start   = month_start,
          month_end     = as.Date(month_end),
          verbose       = verbose
        )
        retry_count <- 0L
        next
      }
      stop(
        "AppEEARS task ", task_id, " returned no status field.\n",
        "The task likely expired (AppEEARS retains results for ~14 days).\n",
        "Pass domain_vector and month_end to enable automatic re-submission, ",
        "or run tar_invalidate(vi_viirs_task_ids) to force re-submission."
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
    if (verbose && retry_count %% 10L == 0L) {
      message("Task status: ", task_status, " (", retry_count, "/", max_retries, ")")
    }
    Sys.sleep(60)
  }

  if (verbose) message("Downloading files for task: ", task_id)
  appeears::rs_transfer(
    task_id = task_id,
    user    = Sys.getenv("EARTHDATA_USER"),
    path    = temp_directory,
    verbose = verbose
  )

  nc_paths <- list.files(temp_directory, pattern = "\\.nc$",
                         full.names = TRUE, recursive = TRUE)
  if (length(nc_paths) == 0L) {
    if (verbose) message("No NCs returned from AppEEARS for month ", yyyymm)
    skip_file <- file.path(cache_dir, paste0("vi_viirs_", yyyymm, ".skip"))
    writeLines(
      c(paste("Month:", yyyymm),
        "Reason: AppEEARS returned no NetCDF files",
        paste("Timestamp:", Sys.time())),
      con = skip_file
    )
    if (verbose) message("Created skip marker: ", skip_file)
    if (cleanup) unlink(temp_directory, recursive = TRUE, force = TRUE)
    return(skip_file)
  }

  if (verbose) message("Downloaded ", length(nc_paths), " NC files to ", temp_directory)
  temp_directory
}


#' @title Convert VIIRS VI AppEEARS NetCDF files to domain-aligned raster grids
#'
#' @description Processes raw AppEEARS NetCDF downloads for one month: applies
#'   QA masking, mosaics spatial tiles, and reprojects to the domain grid.
#'   Outputs two NetCDF files — one for S-NPP (VNP13A1) and one for NOAA-20
#'   (VJ113A1) — each containing two variables: \code{EVI} (EVI×100,
#'   QA-masked, int32) and \code{doy} (composite day-of-year, int16).
#'   Both files are always written (all-NA when no source data exist).
#'
#' @param netcdf_directory Character. Path to directory of raw AppEEARS NCs,
#'   or path to a \code{.skip} marker from \code{download_viirs_vi_netcdf()}.
#' @param domain_raster   Character path or SpatRaster with a \code{pid} layer.
#' @param month_start     Date or "YYYY-MM-DD". First day of the month.
#' @param out_dir         Output directory for the two sensor NCs.
#' @param cleanup         Logical. Delete raw AppEEARS temp files after writing?
#' @param verbose         Logical. Print progress messages?
#'
#' @return Character vector of length 2:
#'   \code{c("out_dir/vi_viirs_YYYYMM_snpp.nc", "out_dir/vi_viirs_YYYYMM_noaa20.nc")}.
#' @export
vi_viirs_netcdf_to_grid <- function(
    netcdf_directory,
    domain_raster,
    month_start,
    out_dir  = "data/target_outputs/viirs_vi/",
    cleanup  = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose  = TRUE) {

  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  terra_tmp <- file.path(getwd(), "data/temp/terra", paste0(yyyymm, "_viirs"))
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terra::terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_snpp_nc   <- file.path(out_dir, paste0("vi_viirs_", yyyymm, "_snpp.nc"))
  out_noaa20_nc <- file.path(out_dir, paste0("vi_viirs_", yyyymm, "_noaa20.nc"))

  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))

  nc_paths <- character(0)
  if (!grepl("\\.skip$", netcdf_directory) && dir.exists(netcdf_directory)) {
    nc_paths <- list.files(netcdf_directory, pattern = "\\.nc$",
                           full.names = TRUE, recursive = TRUE)
  }

  if (length(nc_paths) == 0L) {
    if (verbose) message("No source NCs for ", yyyymm, " — writing all-NA grid files")
    write_sensor_nc(NULL, out_snpp_nc,   "S-NPP/VNP13A1",   verbose)
    write_sensor_nc(NULL, out_noaa20_nc, "NOAA-20/VJ113A1", verbose)
    if (cleanup && !grepl("\\.skip$", netcdf_directory) && dir.exists(netcdf_directory)) {
      unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    }
    return(c(out_snpp_nc, out_noaa20_nc))
  }

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

  # Sensor detection: NOAA-20 NC global attributes contain "VJ1"; S-NPP contains "VNP"
  detect_sensor <- function(nc_path) {
    sensor <- "snpp"
    tryCatch({
      nc_obj <- ncdf4::nc_open(nc_path)
      attrs  <- ncdf4::ncatt_get(nc_obj, 0)
      ncdf4::nc_close(nc_obj)
      for (val in attrs) {
        if (is.character(val) && grepl("VJ1", val, ignore.case = FALSE)) {
          sensor <- "noaa20"
          break
        }
      }
    }, error = function(e) invisible(NULL))
    sensor
  }

  sensor_labels <- vapply(nc_paths, detect_sensor, character(1L))
  snpp_ncs   <- nc_paths[sensor_labels == "snpp"]
  noaa20_ncs <- nc_paths[sensor_labels == "noaa20"]
  if (verbose) {
    message("Sensor split: ", length(snpp_ncs), " S-NPP NC(s), ",
            length(noaa20_ncs), " NOAA-20 NC(s)")
  }

  # Process one set of same-sensor NCs -> (EVI stack, doy stack) aligned to domain.
  # Identical logic to vi_modis_netcdf_to_grid(); sensor label differs only.
  process_sensor_ncs <- function(ncs, keep_values, domain_template, verbose) {
    if (length(ncs) == 0L) return(NULL)

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

        r_times <- as.numeric(terra::time(r[[evi_idx]]))
        t_match <- which(r_times == t_val)
        if (length(t_match) == 0L) next

        i_evi <- evi_idx[t_match[1L]]
        i_qa  <- qa_idx[min(t_match[1L], length(qa_idx))]
        i_doy <- doy_idx[min(t_match[1L], length(doy_idx))]

        keep_mask  <- terra::app(r[[i_qa]], function(x) x %in% keep_values)
        evi_masked <- terra::mask(r[[i_evi]], keep_mask, maskvalue = FALSE) |>
                      terra::app(function(x) as.integer(round(x * 100)))
        doy_masked <- terra::mask(r[[i_doy]], keep_mask, maskvalue = FALSE)

        evi_tiles[[length(evi_tiles) + 1L]] <- evi_masked
        doy_tiles[[length(doy_tiles) + 1L]] <- doy_masked
      }

      if (length(evi_tiles) == 0L) next

      if (length(evi_tiles) == 1L) {
        evi_m <- evi_tiles[[1L]]
        doy_m <- doy_tiles[[1L]]
      } else {
        evi_m <- do.call(terra::mosaic, c(evi_tiles, list(fun = "mean")))
        doy_m <- do.call(terra::mosaic, c(doy_tiles, list(fun = "first")))
      }

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

  snpp_data   <- process_sensor_ncs(snpp_ncs,   keep_values, domain_template, verbose)
  noaa20_data <- process_sensor_ncs(noaa20_ncs, keep_values, domain_template, verbose)

  # Write helper: always writes to a temp path then renames, so terra never sees
  # a pre-existing file regardless of whether overwrite=TRUE is honoured.
  # terra 1.9.27 only has writeCDF(x, filename, ...) — no overwrite or append.
  # Write each variable to its own temp file, then merge doy into the EVI file
  # using ncdf4::ncvar_add so terra never sees a pre-existing filename.
  merge_doy_into_nc <- function(tmp_doy, tmp_nc, doy_long) {
    nc_src <- ncdf4::nc_open(tmp_doy)
    nc_dst <- ncdf4::nc_open(tmp_nc, write = TRUE)
    tryCatch({
      new_var <- ncdf4::ncvar_def(
        name     = "doy",
        units    = "",
        dim      = nc_dst$var[[names(nc_dst$var)[1]]]$dim,
        longname = doy_long,
        prec     = "float"
      )
      nc_dst <- ncdf4::ncvar_add(nc_dst, new_var)
      ncdf4::ncvar_put(nc_dst, "doy", ncdf4::ncvar_get(nc_src, "doy"))
    }, finally = {
      ncdf4::nc_close(nc_src)
      ncdf4::nc_close(nc_dst)
    })
  }

  write_sensor_nc <- function(sensor_data, out_nc, sensor_label, verbose) {
    tmp_nc  <- tempfile(tmpdir = dirname(out_nc), fileext = ".nc")
    tmp_doy <- tempfile(tmpdir = dirname(out_nc), fileext = ".nc")
    on.exit({ unlink(tmp_nc); unlink(tmp_doy) }, add = TRUE)

    if (is.null(sensor_data)) {
      if (verbose) message("No valid composites for ", sensor_label, " in ", yyyymm,
                           " — writing all-NA NC")
      empty_r <- terra::setValues(domain_template[[1]], NA_real_)
      terra::time(empty_r) <- month_start
      terra::writeCDF(empty_r, tmp_nc,
                      varname  = "EVI",
                      longname = "EVI x100 (QA-masked, no data)",
                      verbose  = FALSE)
      terra::writeCDF(empty_r, tmp_doy,
                      varname  = "doy",
                      longname = "Composite day of year (no data)",
                      verbose  = FALSE)
      merge_doy_into_nc(tmp_doy, tmp_nc, "Composite day of year (no data)")
    } else {
      terra::writeCDF(sensor_data$evi, tmp_nc,
                      varname  = "EVI",
                      longname = paste0("EVI x100 QA-masked (", sensor_label, ")"),
                      verbose  = FALSE)
      terra::writeCDF(sensor_data$doy, tmp_doy,
                      varname  = "doy",
                      longname = paste0("Composite day of year (", sensor_label, ")"),
                      verbose  = FALSE)
      merge_doy_into_nc(tmp_doy, tmp_nc, paste0("Composite day of year (", sensor_label, ")"))
      n_steps <- terra::nlyr(sensor_data$evi)
      if (verbose) message("Wrote ", n_steps, " time step(s) -> ", basename(out_nc))
    }

    unlink(out_nc)
    if (!file.rename(tmp_nc, out_nc))
      stop("Could not rename ", tmp_nc, " -> ", out_nc)
  }

  unlink(out_snpp_nc)
  unlink(out_noaa20_nc)
  write_sensor_nc(snpp_data,   out_snpp_nc,   "S-NPP/VNP13A1",  verbose)
  write_sensor_nc(noaa20_data, out_noaa20_nc, "NOAA-20/VJ113A1", verbose)

  if (cleanup) {
    unlink(netcdf_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }

  c(out_snpp_nc, out_noaa20_nc)
}


#' @title Convert VIIRS VI sensor grid NCs to tabular parquet
#'
#' @description Reads the two domain-aligned sensor NCs produced by
#'   \code{vi_viirs_netcdf_to_grid()} and writes a single gzip-compressed
#'   Parquet file with one row per valid pixel × time step.
#'
#' @param nc_files     Character vector of NC paths (snpp + noaa20) for one month.
#' @param domain_raster Character path or SpatRaster with a \code{pid} layer.
#' @param month_start   Date or "YYYY-MM-DD". First day of the month.
#' @param out_dir       Output directory for the parquet file.
#' @param verbose       Logical. Print progress messages?
#'
#' @return Character path to \code{dynamic_viirs_vi_YYYYMM.parquet}, or path to
#'   a \code{vi_viirs_YYYYMM.skip} marker when all pixels are NA.
#' @export
vi_viirs_netcdf_to_parquet <- function(
    nc_files,
    domain_raster,
    month_start,
    out_dir  = "data/target_outputs/viirs_vi/",
    verbose  = TRUE) {

  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  parquet_file <- file.path(out_dir, paste0("dynamic_viirs_vi_", yyyymm, ".parquet"))

  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))
  pid_vec         <- terra::values(domain_template[["pid"]])[, 1]
  ref_year        <- as.integer(format(month_start, "%Y"))
  year_start_epoch <- as.integer(as.Date(paste0(ref_year, "-01-01")) - as.Date("1970-01-01"))

  # Sensor code from filename: _snpp_ -> 3, else 4 (noaa20)
  sensor_code <- function(nc_path) {
    if (grepl("_snpp_", basename(nc_path))) 3L else 4L
  }

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
    if (verbose) message("No valid VIIRS VI observations for ", yyyymm, " — writing skip marker")
    skip_file <- file.path(out_dir, paste0("vi_viirs_", yyyymm, ".skip"))
    writeLines(
      c(paste("Month:", yyyymm),
        "Reason: All-NA after reading sensor grid NCs",
        paste("Timestamp:", Sys.time())),
      skip_file
    )
    return(skip_file)
  }

  unlink(parquet_file)
  if (verbose) message("Writing ", nrow(df), " observations -> ", basename(parquet_file))
  arrow::write_parquet(df, sink = parquet_file, compression = "gzip")

  parquet_file
}
