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
#   - Sensor detection: GeoTIFF filename contains "VJ113A1" -> noaa20, else snpp
#   - Output TIFs: vi_viirs_snpp_YYYYMMDD.tif / vi_viirs_noaa20_YYYYMMDD.tif
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
    composite_date,
    composite_end,
    out_dir        = NULL,
    gh_release_tag = NULL,
    verbose        = TRUE) {

  yyyymmdd <- format(as.Date(composite_date), "%Y%m%d")

  # Check local disk (fast — works on server after a completed run)
  if (!is.null(out_dir)) {
    snpp_tif <- file.path(out_dir, paste0("vi_viirs_snpp_", yyyymmdd, ".tif"))
    if (file.exists(snpp_tif)) {
      if (verbose) message("Grid COG on disk for ", yyyymmdd, " — skipping AppEEARS submission")
      return(paste0("cached:", yyyymmdd))
    }
  }

  # Check GitHub release (authoritative — works on CI where disk is empty)
  if (!is.null(gh_release_tag)) {
    repo <- Sys.getenv("TAR_GH_RELEASE_REPO", unset = "AdamWilsonLab/emma_envdata")
    if (gh_release_has_asset(repo, gh_release_tag, paste0("vi_viirs_snpp_", yyyymmdd, ".tif"), verbose = verbose)) {
      if (verbose) message("Composite ", yyyymmdd, " already on GitHub release '", gh_release_tag, "' — skipping AppEEARS submission")
      return(paste0("cached:", yyyymmdd))
    }
  }

  ensure_appeears_auth()
  composite_date <- as.Date(composite_date)
  composite_end  <- as.Date(composite_end)

  if (verbose) {
    message("AppEEARS VIIRS VI composite request: ",
            format(composite_date, "%Y-%m-%d"), " to ", format(composite_end, "%Y-%m-%d"))
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
    task_name = paste0("VIIRS_VI_", format(composite_date, "%Y%m%d"), "_",
                       format(Sys.time(), "%H%M%S")),
    params = list(
      dates = list(list(
        startDate = format(composite_date, "%m-%d-%Y"),
        endDate   = format(composite_end,  "%m-%d-%Y")
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
        format     = list(type = "geotiff", filename_date = "calendar"),
        projection = "native"  # keep native VIIRS sinusoidal; reproject to EPSG:9221 in R
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


#' @title Download VIIRS VI GeoTIFF files from AppEEARS
#'
#' @description Polls for AppEEARS task completion and downloads result GeoTIFFs.
#'   Separates I/O from computation for independent parallelisation.
#'   If the task is not found (e.g. expired after the 14-day retention window),
#'   and domain_vector plus month_end are supplied, the task is automatically
#'   re-submitted.
#'
#' @param task_id        Character. AppEEARS task ID.
#' @param month_start    Date or "YYYY-MM-DD". First day of the month.
#' @param domain_vector  SpatVector or sf polygon used to re-submit if the task
#'   has expired. Optional; if NULL a missing-status error is raised instead.
#' @param composite_end  Date or "YYYY-MM-DD". Last day of the composite window.
#'   Required only when domain_vector is provided for automatic re-submission.
#' @param temp_directory Temporary working directory for downloads.
#' @param cleanup        Logical. Delete temp files after grid COG is written?
#'   Defaults to TRUE on GitHub Actions.
#' @param verbose        Logical. Print progress messages? Default TRUE.
#'
#' @return Character path to temp directory containing downloaded GeoTIFFs, or
#'   path to a \code{.skip} marker when AppEEARS returned no data.
#' @export
download_viirs_vi_geotiff <- function(
    task_id,
    composite_date,
    domain_vector  = NULL,
    composite_end  = NULL,
    temp_directory = "data/temp/appeears/viirs_vi/",
    cleanup        = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose        = TRUE) {

  # Sentinel task_id means submit_viirs_vi() found the composite already complete —
  # skip all AppEEARS polling and return the temp directory path directly.
  if (startsWith(task_id, "cached:")) {
    yyyymmdd_sentinel <- sub("^cached:", "", task_id)
    if (verbose) message("Sentinel task_id for ", yyyymmdd_sentinel, " \u2014 skipping AppEEARS download")
    dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
    return(temp_directory)
  }

  ensure_appeears_auth()
  composite_date <- as.Date(composite_date)
  yyyymmdd       <- format(composite_date, "%Y%m%d")

  cache_dir <- "data/target_outputs/viirs_vi"
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  # Early-exit: snpp COG written by vi_viirs_geotiff_to_grid() signals completion
  snpp_tif_done <- file.path(cache_dir, paste0("vi_viirs_snpp_", yyyymmdd, ".tif"))
  if (file.exists(snpp_tif_done)) {
    if (verbose) message("Grid COG found for ", yyyymmdd, " \u2014 skipping AppEEARS download")
    dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
    return(temp_directory)
  }

  # Per-branch subdir to avoid race conditions under parallel tar_make_future()
  temp_directory <- file.path(temp_directory, yyyymmdd)
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

    if (is.null(task_status) || length(task_status) == 0) {
      null_retries <- null_retries + 1L
      if (null_retries <= 10L) {
        if (verbose) message("Task ", task_id, " not yet visible in AppEEARS (",
                             null_retries, "/10) \u2014 retrying...")
        Sys.sleep(60)
        next
      }
      null_retries <- 0L
      if (!is.null(domain_vector) && !is.null(composite_end)) {
        if (verbose) {
          message(
            "[AppEEARS] Task ", task_id, " not found (likely expired) \u2014 re-submitting for ", yyyymmdd
          )
        }
        task_id <- submit_viirs_vi(
          domain_vector  = domain_vector,
          composite_date = composite_date,
          composite_end  = as.Date(composite_end),
          verbose        = verbose
        )
        retry_count <- 0L
        next
      }
      stop(
        "AppEEARS task ", task_id, " returned no status field.\n",
        "The task likely expired (AppEEARS retains results for ~14 days).\n",
        "Pass domain_vector and composite_end to enable automatic re-submission, ",
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

  tif_paths <- list.files(temp_directory, pattern = "\\.tif$",
                          full.names = TRUE, recursive = TRUE)
  if (length(tif_paths) == 0L) {
    if (verbose) message("No GeoTIFF files returned from AppEEARS for composite ", yyyymmdd)
    skip_file <- file.path(cache_dir, paste0("vi_viirs_", yyyymmdd, ".skip"))
    writeLines(
      c(paste("Composite:", yyyymmdd),
        "Reason: AppEEARS returned no GeoTIFF files",
        paste("Timestamp:", Sys.time())),
      con = skip_file
    )
    if (verbose) message("Created skip marker: ", skip_file)
    if (cleanup) unlink(temp_directory, recursive = TRUE, force = TRUE)
    return(skip_file)
  }

  if (verbose) message("Downloaded ", length(tif_paths), " GeoTIFF files to ", temp_directory)
  temp_directory
}


#' @title Convert VIIRS VI AppEEARS GeoTIFF downloads to domain-aligned COG grids
#'
#' @description Processes raw AppEEARS GeoTIFF downloads for one 16-day composite:
#'   reads EVI, VI_Quality and composite_day_of_the_year TIFs, applies QA masking,
#'   reprojects to the domain grid (EPSG:9221), and writes two 2-band COGs —
#'   one for S-NPP (VNP13A1) and one for NOAA-20 (VJ113A1) — each with bands
#'   \code{evi} (EVI × 100, QA-masked, integer) and \code{doy}
#'   (composite day-of-year, per pixel, integer).
#'   Both files are always written (all-NA placeholder when no source data exist).
#'
#' @param geotiff_directory Character. Path to directory of raw AppEEARS GeoTIFFs,
#'   or path to a \code{.skip} marker from \code{download_viirs_vi_geotiff()}.
#' @param domain_raster   Character path or SpatRaster with a \code{pid} layer.
#' @param composite_date  Date or "YYYY-MM-DD". First day of the 16-day window.
#' @param out_dir         Output directory for the two sensor COGs.
#' @param cleanup         Logical. Delete raw AppEEARS temp files after writing?
#' @param verbose         Logical. Print progress messages?
#'
#' @return Character vector of length 2:
#'   \code{c("out_dir/vi_viirs_snpp_YYYYMMDD.tif", "out_dir/vi_viirs_noaa20_YYYYMMDD.tif")}.
#' @export
vi_viirs_geotiff_to_grid <- function(
    geotiff_directory,
    domain_raster,
    composite_date,
    out_dir  = "data/target_outputs/viirs_vi/",
    cleanup  = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose  = TRUE) {

  composite_date <- as.Date(composite_date)
  yyyymmdd       <- format(composite_date, "%Y%m%d")

  terra_tmp <- file.path(getwd(), "data/temp/terra", paste0(yyyymmdd, "_viirs"))
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terra::terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_snpp   <- file.path(out_dir, paste0("vi_viirs_snpp_",   yyyymmdd, ".tif"))
  out_noaa20 <- file.path(out_dir, paste0("vi_viirs_noaa20_", yyyymmdd, ".tif"))

  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))

  # Helper: write all-NA placeholder 2-band COG aligned to domain
  write_na_cog <- function(out_path, sensor_label) {
    if (verbose) message("No source data for ", sensor_label, " in ", yyyymmdd,
                         " \u2014 writing all-NA placeholder COG")
    na_r         <- domain_template[["pid"]]
    na_r[]       <- NA_real_
    names(na_r)  <- "evi"
    doy_r        <- domain_template[["pid"]]
    doy_r[]      <- NA_real_
    names(doy_r) <- "doy"
    r_out <- c(na_r, doy_r)
    terra::metags(r_out) <- c(
      composite_date = as.character(composite_date),
      sensor         = sensor_label,
      source         = "no_data"
    )
    terra::writeRaster(r_out, out_path, filetype = "COG", datatype = "INT2S",
                       gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2"),
                       overwrite = TRUE)
  }

  # Collect available GeoTIFF files; handle skip marker and empty/missing directory
  tif_paths <- character(0L)
  if (!grepl("\\.skip$", geotiff_directory) && dir.exists(geotiff_directory)) {
    tif_paths <- list.files(geotiff_directory, pattern = "\\.tif$",
                            full.names = TRUE, recursive = TRUE)
  }

  if (length(tif_paths) == 0L) {
    if (verbose) message("No source GeoTIFFs for ", yyyymmdd,
                         " \u2014 writing all-NA placeholder COGs")
    write_na_cog(out_snpp,   "S-NPP/VNP13A1")
    write_na_cog(out_noaa20, "NOAA-20/VJ113A1")
    if (cleanup && !grepl("\\.skip$", geotiff_directory) && dir.exists(geotiff_directory)) {
      unlink(geotiff_directory, recursive = TRUE, force = TRUE)
    }
    return(c(out_snpp, out_noaa20))
  }

  # Read QA lookup tables (AppEEARS includes VI-Quality CSV alongside GeoTIFFs)
  qa_csv_paths <- list.files(geotiff_directory, pattern = "VI[-_]Quality.*\\.csv$",
                              full.names = TRUE, recursive = TRUE)
  if (!length(qa_csv_paths)) {
    stop("QA lookup table not found in geotiff_directory; cannot QA-mask VI data")
  }
  keep_values <- parse_qa(qa_csv_paths)
  if (!length(keep_values)) stop("No good-quality QA entries found in lookup tables")

  if (verbose) {
    message("Processing ", length(tif_paths), " GeoTIFF files for composite ", yyyymmdd,
            " (", length(keep_values), " QA keep values)")
  }

  # Classify TIFs by sensor and layer from AppEEARS filename.
  # Pattern: VNP13A1.002__500_m_16_days_EVI_YYYYMMDDTHHMMSS_aid0001.tif
  classify_tif <- function(path) {
    bn      <- basename(path)
    product <- if (grepl("VNP13A1", bn)) "snpp"   else
               if (grepl("VJ113A1", bn)) "noaa20" else NA_character_
    layer   <- if (grepl("_EVI_", bn) && !grepl("Quality", bn)) "evi"  else
               if (grepl("VI_Quality|VI-Quality", bn))           "qa"   else
               if (grepl("composite_day_of_the_year", bn))       "doy"  else NA_character_
    list(path = path, product = product, layer = layer)
  }

  tif_info <- lapply(tif_paths, classify_tif)
  tif_info <- Filter(function(x) !is.na(x$product) && !is.na(x$layer), tif_info)

  # Process one sensor (snpp or noaa20) → 2-band COG (evi, doy) aligned to domain
  process_sensor <- function(sensor_label, product_code, source_label, out_path) {
    sensor_tifs <- Filter(function(x) x$product == product_code, tif_info)
    evi_entry   <- Filter(function(x) x$layer == "evi", sensor_tifs)
    qa_entry    <- Filter(function(x) x$layer == "qa",  sensor_tifs)
    doy_entry   <- Filter(function(x) x$layer == "doy", sensor_tifs)

    if (!length(evi_entry)) {
      if (verbose) message("No EVI TIF for ", sensor_label, " in ", yyyymmdd,
                           " \u2014 writing all-NA placeholder COG")
      write_na_cog(out_path, sensor_label)
      return(invisible(NULL))
    }

    evi_r <- terra::rast(evi_entry[[1L]]$path)
    qa_r  <- if (length(qa_entry))  terra::rast(qa_entry[[1L]]$path)  else NULL
    doy_r <- if (length(doy_entry)) terra::rast(doy_entry[[1L]]$path) else NULL

    # QA-mask EVI; scale to integer × 100 to match parquet schema
    if (!is.null(qa_r)) {
      keep_mask <- terra::app(qa_r, function(x) x %in% keep_values)
      evi_r     <- terra::mask(evi_r, keep_mask, maskvalue = FALSE)
      if (!is.null(doy_r)) {
        doy_r <- terra::mask(doy_r, keep_mask, maskvalue = FALSE)
      }
    }
    evi_r <- terra::app(evi_r, function(x) as.integer(round(x * 100)))

    # Reproject from native VIIRS sinusoidal to domain CRS (EPSG:9221, metres)
    domain_mask <- !is.na(domain_template[["pid"]])
    evi_proj    <- terra::project(evi_r, domain_template, method = "average")
    evi_proj    <- terra::mask(evi_proj, domain_mask, maskvalue = FALSE)

    if (!is.null(doy_r)) {
      doy_proj <- terra::project(doy_r, domain_template, method = "mode")
      doy_proj <- terra::mask(doy_proj, domain_mask, maskvalue = FALSE)
    } else {
      doy_proj    <- domain_template[["pid"]]
      doy_proj[]  <- NA_real_
    }

    # Stack EVI + DOY into 2-band COG with embedded metadata
    r_out        <- c(evi_proj, doy_proj)
    names(r_out) <- c("evi", "doy")
    terra::metags(r_out) <- c(
      composite_date = as.character(composite_date),
      sensor         = sensor_label,
      source         = source_label,
      date_created   = as.character(Sys.Date())
    )
    unlink(out_path)
    terra::writeRaster(r_out, out_path, filetype = "COG", datatype = "INT2S",
                       gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2"),
                       overwrite = TRUE)
    if (verbose) message("Wrote: ", basename(out_path))
  }

  process_sensor("S-NPP/VNP13A1",   "snpp",   "VNP13A1.002", out_snpp)
  process_sensor("NOAA-20/VJ113A1", "noaa20", "VJ113A1.002", out_noaa20)

  if (cleanup) {
    unlink(geotiff_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }

  c(out_snpp, out_noaa20)
}


#' @title Convert VIIRS VI sensor COG grids to tabular parquet
#'
#' @description Reads the two 2-band sensor COGs produced by
#'   \code{vi_viirs_geotiff_to_grid()} and writes a single gzip-compressed
#'   Parquet file with one row per valid (non-NA EVI) pixel.
#'
#' @param tif_files     Character vector of COG paths (snpp + noaa20).
#' @param domain_raster Character path or SpatRaster with a \code{pid} layer.
#' @param composite_date Date or "YYYY-MM-DD". First day of the 16-day composite.
#' @param out_dir       Output directory for the parquet file.
#' @param verbose       Logical. Print progress messages?
#'
#' @return Character path to \code{dynamic_viirs_vi_YYYYMMDD.parquet}, or path to
#'   a \code{vi_viirs_YYYYMMDD.skip} marker when all pixels are NA.
#'
#' @details
#' Parquet schema (one row per observation):
#' \describe{
#'   \item{pid}{int32 — pixel ID from domain grid}
#'   \item{date}{int32 — days since 1970-01-01, from per-pixel composite DOY}
#'   \item{variable}{int32 — sensor code: 3 = S-NPP (VNP13A1), 4 = NOAA-20 (VJ113A1)}
#'   \item{value}{int32 — EVI × 100 (scale factor 0.01)}
#' }
#' @export
vi_viirs_geotiff_to_parquet <- function(
    tif_files,
    domain_raster,
    composite_date,
    out_dir  = "data/target_outputs/viirs_vi/",
    verbose  = TRUE) {

  composite_date   <- as.Date(composite_date)
  yyyymmdd         <- format(composite_date, "%Y%m%d")

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  parquet_file <- file.path(out_dir, paste0("dynamic_viirs_vi_", yyyymmdd, ".parquet"))

  # Load domain for pid values
  domain_template  <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))
  pid_vec          <- terra::values(domain_template[["pid"]])[, 1]
  ref_year         <- as.integer(format(composite_date, "%Y"))
  year_start_epoch <- as.integer(as.Date(paste0(ref_year, "-01-01")) - as.Date("1970-01-01"))

  # Detect sensor code from filename: _snpp_ \u2192 3, _noaa20_ \u2192 4
  sensor_code <- function(tif_path) {
    if (grepl("_snpp_", basename(tif_path))) 3L else 4L
  }

  # Extract observations from one 2-band sensor COG (evi + doy bands)
  extract_sensor_obs <- function(tif_path) {
    s_id <- sensor_code(tif_path)
    r    <- tryCatch(terra::rast(tif_path), error = function(e) NULL)
    if (is.null(r)) {
      if (verbose) message("Could not read: ", basename(tif_path))
      return(NULL)
    }
    if (!all(c("evi", "doy") %in% names(r))) {
      if (verbose) message("Missing evi/doy bands in: ", basename(tif_path))
      return(NULL)
    }
    evi_v <- terra::values(r[["evi"]])[, 1]
    doy_v <- terra::values(r[["doy"]])[, 1]
    valid <- !is.na(evi_v) & !is.na(doy_v) & !is.na(pid_vec)
    if (!any(valid)) return(NULL)
    # Convert day-of-year (1\u2013366) to days since 1970-01-01
    epoch_dates <- as.integer(year_start_epoch + as.integer(doy_v[valid]) - 1L)
    tibble::tibble(
      pid      = as.integer(pid_vec[valid]),
      date     = epoch_dates,
      variable = s_id,
      value    = as.integer(evi_v[valid])
    )
  }

  all_obs <- purrr::map(tif_files, function(tf) {
    tryCatch(extract_sensor_obs(tf),
             error = function(e) {
               warning("Failed to process ", basename(tf), ": ", conditionMessage(e))
               NULL
             })
  })

  compact_obs <- purrr::compact(all_obs)
  df <- if (length(compact_obs) > 0L) {
    dplyr::bind_rows(compact_obs) |>
      dplyr::filter(!is.na(.data$value))
  } else {
    tibble::tibble(pid = integer(), date = integer(), variable = integer(), value = integer())
  }

  if (nrow(df) == 0L) {
    if (verbose) message("No valid VIIRS VI observations for ", yyyymmdd,
                         " \u2014 writing skip marker")
    skip_file <- file.path(out_dir, paste0("vi_viirs_", yyyymmdd, ".skip"))
    writeLines(
      c(paste("Composite date:", yyyymmdd),
        "Reason: All-NA after reading sensor grid COGs",
        paste("Timestamp:", Sys.time())),
      skip_file
    )
    return(skip_file)
  }

  unlink(parquet_file)
  if (verbose) message("Writing ", nrow(df), " observations \u2192 ", basename(parquet_file))
  arrow::write_parquet(df, sink = parquet_file, compression = "gzip")

  parquet_file
}
