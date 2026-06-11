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
    out_dir        = NULL,
    gh_release_tag = NULL,
    verbose        = TRUE) {

  yyyymm <- format(as.Date(month_start), "%Y%m")

  # Check local disk (fast — works on server after a completed run)
  if (!is.null(out_dir)) {
    grid_tif <- file.path(out_dir, paste0("burn_viirs_", yyyymm, ".tif"))
    if (file.exists(grid_tif)) {
      if (verbose) message("Grid COG on disk for ", yyyymm, " — skipping AppEEARS submission")
      return(paste0("cached:", yyyymm))
    }
  }

  # Check GitHub release (authoritative — works on CI where disk is empty)
  if (!is.null(gh_release_tag)) {
    repo <- Sys.getenv("TAR_GH_RELEASE_REPO", unset = "AdamWilsonLab/emma_envdata")
    if (gh_release_has_asset(repo, gh_release_tag, paste0("burn_viirs_", yyyymm, ".tif"), verbose = verbose)) {
      if (verbose) message("Month ", yyyymm, " already on GitHub release '", gh_release_tag, "' — skipping AppEEARS submission")
      return(paste0("cached:", yyyymm))
    }
  }

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
        format     = list(type = "geotiff", filename_date = "calendar"),
        projection = "native"  # keep native VIIRS sinusoidal; reproject to EPSG:9221 during processing
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


#' @title Download VIIRS burned area GeoTIFF files from AppEEARS
#'
#' @description Polls until the task completes, downloads the results, and creates
#'   a marker file. Identical to \code{download_burn_date_modis_geotiff()} except
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
#' @return Character path to temp directory containing downloaded GeoTIFF files.
#' @export
download_burn_date_viirs_geotiff <- function(
    task_id,
    month_start,
    domain_vector  = NULL,
    month_end      = NULL,
    temp_directory = "data/temp/appeears/burn_dates_viirs/",
    cleanup        = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose        = TRUE) {

  # Sentinel task_id means submit_burn_date_viirs_task() found the month already
  # complete — skip all AppEEARS polling and return the temp directory directly.
  if (startsWith(task_id, "cached:")) {
    yyyymm_sentinel <- sub("^cached:", "", task_id)
    if (verbose) message("Sentinel task_id for ", yyyymm_sentinel, " — skipping AppEEARS download")
    dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
    return(temp_directory)
  }

  ensure_appeears_auth()
  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  # Skip if grid COG for this month already exists.
  # burn_viirs_geotiff_to_grid() writes burn_viirs_YYYYMM.tif when it completes.
  marker_dir   <- "data/target_outputs/burndates"
  dir.create(marker_dir,      recursive = TRUE, showWarnings = FALSE)
  dir.create(temp_directory,  recursive = TRUE, showWarnings = FALSE)
  grid_tif_done <- file.path(marker_dir, paste0("burn_viirs_", yyyymm, ".tif"))

  if (file.exists(grid_tif_done)) {
    if (verbose) message("VIIRS grid COG found for ", yyyymm, " — skipping download")
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

  tif_paths <- list.files(temp_directory, pattern = "\\.tif$", full.names = TRUE, recursive = TRUE)
  if (length(tif_paths) == 0) {
    if (verbose) message("No GeoTIFF files returned for VIIRS month ", yyyymm)
    skip_file <- file.path(marker_dir, paste0("burn_viirs_", yyyymm, ".skip"))
    writeLines(
      c(paste("Month:", yyyymm), "Reason: No GeoTIFF returned from AppEEARS", paste("Timestamp:", Sys.time())),
      con = skip_file
    )
    return(skip_file)
  }

  if (verbose) message("Downloaded ", length(tif_paths), " VIIRS GeoTIFF files for ", yyyymm)
  # Return temp directory; burn_viirs_geotiff_to_grid() acts as the persistent marker.
  temp_directory
}


#' @title Convert VIIRS burned area GeoTIFFs to a domain-aligned COG
#' @description Identical workflow to \code{burn_modis_geotiff_to_grid()} but for
#'   VNP64A1 (VIIRS, 375 m).  The 375 m pixels are resampled to the 500 m domain
#'   grid (EPSG:9221) via nearest-neighbour reprojection.  Writes a single 1-band
#'   COG containing a \code{burn_doy} band (burn day-of-year; 0 = unburned,
#'   1–366 = burned DOY).  QA is intentionally not used — \code{burn_doy > 0}
#'   is the definitive indicator of burning; \code{qa == 0} removes all burned
#'   pixels because VNP64A1 QA = 0 means fill/unprocessed, not "good quality."
#'
#' @param geotiff_directory Character.  Path to AppEEARS temp directory or a
#'   \code{.skip} path.
#' @param domain_raster Character path or SpatRaster with a \code{pid} layer.
#' @param month_start Date or "YYYY-MM-DD".
#' @param out_dir Character.  Output directory for the grid COG.
#' @param cleanup Logical.  Delete raw temp files after writing?
#' @param verbose Logical.
#'
#' @return Character path to \code{burn_viirs_YYYYMM.tif}.
#' @export
burn_viirs_geotiff_to_grid <- function(
  geotiff_directory,
  domain_raster,
  month_start,
  out_dir  = "data/target_outputs/burndates/",
  cleanup  = Sys.getenv("GITHUB_ACTIONS") == "true",
  verbose  = TRUE
) {
  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  terra_tmp <- file.path(getwd(), "data/temp/terra", yyyymm)
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terra::terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_tif <- file.path(out_dir, paste0("burn_viirs_", yyyymm, ".tif"))

  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))

  write_empty_cog <- function() {
    empty_r        <- terra::setValues(domain_template[[1L]], NA_real_)
    names(empty_r) <- "burn_doy"
    terra::metags(empty_r) <- c(
      month        = yyyymm,
      source       = "VNP64A1.002",
      date_created = as.character(Sys.Date())
    )
    unlink(out_tif)
    terra::writeRaster(empty_r, out_tif, filetype = "COG", overwrite = TRUE)
  }

  # Resolve source GeoTIFFs (AppEEARS also writes CSVs and JSONs)
  tif_paths <- character(0)
  if (!grepl("\\.skip$", geotiff_directory) && dir.exists(geotiff_directory)) {
    tif_paths <- list.files(geotiff_directory, pattern = "\\.tif$",
                            full.names = TRUE, recursive = TRUE)
  }

  if (length(tif_paths) == 0L) {
    if (verbose) message("No VIIRS burn GeoTIFFs for ", yyyymm, " — writing all-NA grid")
    write_empty_cog()
    if (cleanup && !grepl("\\.skip$", geotiff_directory) && dir.exists(geotiff_directory)) {
      unlink(geotiff_directory, recursive = TRUE, force = TRUE)
    }
    return(out_tif)
  }

  # Select only Burn_Date TIFs (QA not used — burn_doy > 0 is the definitive
  # indicator of burning; VNP64A1 QA=0 is fill/unprocessed, NOT "good quality")
  burn_tif_paths <- tif_paths[grepl("Burn_Date", basename(tif_paths), ignore.case = TRUE)]

  # Reproject each Burn_Date tile to domain (375m → 500m EPSG:9221 via nearest-neighbour)
  burn_tiles <- purrr::map(burn_tif_paths, function(burn_path) {
    tryCatch({
      burn_r    <- terra::rast(burn_path)
      burn_proj <- terra::project(burn_r, domain_template, method = "near")
      domain_mask <- !is.na(domain_template[["pid"]])
      terra::mask(burn_proj, domain_mask, maskvalue = FALSE)
    }, error = function(e) {
      warning("Failed to process ", basename(burn_path), ": ", conditionMessage(e))
      NULL
    })
  })

  burn_tiles <- purrr::compact(burn_tiles)

  if (length(burn_tiles) == 0L) {
    if (verbose) message("All VIIRS tiles failed reprojection for ", yyyymm, " — writing all-NA grid")
    write_empty_cog()
    if (cleanup) unlink(geotiff_directory, recursive = TRUE, force = TRUE)
    return(out_tif)
  }

  # Mosaic spatial tiles (first non-NA wins) and mask to domain pixels
  burn_mosaic <- if (length(burn_tiles) == 1L) {
    burn_tiles[[1L]]
  } else {
    do.call(terra::mosaic, c(burn_tiles, list(fun = "first")))
  }
  domain_mask <- !is.na(domain_template[["pid"]])
  burn_mosaic <- terra::mask(burn_mosaic, domain_mask, maskvalue = FALSE)
  names(burn_mosaic) <- "burn_doy"

  # Embed provenance metadata and write 1-band COG (burn_doy = day-of-year)
  terra::metags(burn_mosaic) <- c(
    month        = yyyymm,
    source       = "VNP64A1.002",
    date_created = as.character(Sys.Date())
  )
  unlink(out_tif)
  terra::writeRaster(burn_mosaic, out_tif, filetype = "COG", overwrite = TRUE)

  n_burned <- sum(!is.na(terra::values(burn_mosaic)[, 1]) &
                    terra::values(burn_mosaic)[, 1] > 0L, na.rm = TRUE)
  if (verbose) message("Wrote VIIRS burn grid COG: ", basename(out_tif),
                       " (", n_burned, " burned pixels)")

  if (cleanup) {
    unlink(geotiff_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }

  out_tif
}


#' @title Convert VIIRS burned area COG to parquet
#'
#' @description Reads \code{burn_doy} band from the domain-aligned COG produced
#'   by \code{burn_viirs_geotiff_to_grid()} and writes a tidy parquet with one
#'   row per burned pixel (\code{burn_doy > 0}).
#'
#' @param tif_file     Character. Path to \code{burn_viirs_YYYYMM.tif}.
#' @param domain_raster SpatRaster or path.  Must contain a \code{pid} layer.
#' @param month_start  Date or "YYYY-MM-DD".
#' @param out_dir      Character. Output directory for parquet files.
#' @param verbose      Logical.
#'
#' @return Character path to the parquet file, or a \code{.skip} path if no
#'   burned pixels are found.
#' @export
burn_date_viirs_geotiff_to_parquet <- function(
    tif_file,
    domain_raster,
    month_start,
    out_dir  = "data/target_outputs/burndates/",
    verbose  = TRUE) {

  month_start <- as.Date(month_start)
  yyyymm      <- format(month_start, "%Y%m")

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # Handle skip-file path from upstream burn_viirs_grid target
  if (grepl("\\.skip$", tif_file)) {
    skip_file <- file.path(out_dir, paste0("burn_viirs_", yyyymm, ".skip"))
    writeLines(c(paste("Month:", yyyymm), "Reason: upstream grid target skipped",
                 paste("Timestamp:", Sys.time())), skip_file)
    return(skip_file)
  }

  domain_template  <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))
  pid_vec          <- terra::values(domain_template[["pid"]])[, 1]
  ref_year         <- as.integer(format(month_start, "%Y"))
  year_start_epoch <- as.integer(as.Date(paste0(ref_year, "-01-01")) - as.Date("1970-01-01"))

  # Read burn_doy band from the COG produced by burn_viirs_geotiff_to_grid()
  burn_r <- tryCatch(
    terra::rast(tif_file)[["burn_doy"]],
    error = function(e) {
      warning("Could not read burn_doy from ", basename(tif_file), ": ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(burn_r)) {
    skip_file <- file.path(out_dir, paste0("burn_viirs_", yyyymm, ".skip"))
    writeLines(c(paste("Month:", yyyymm), "Reason: Could not read grid COG",
                 paste("Timestamp:", Sys.time())), skip_file)
    return(skip_file)
  }

  # Vectorise: one row per burned pixel (burn_doy > 0)
  doy_v <- terra::values(burn_r)[, 1]
  valid <- !is.na(pid_vec) & !is.na(doy_v) & doy_v > 0L

  if (!any(valid)) {
    if (verbose) message("No burned pixels for ", yyyymm, " — writing skip marker")
    skip_file <- file.path(out_dir, paste0("burn_viirs_", yyyymm, ".skip"))
    writeLines(c(paste("Month:", yyyymm), "Reason: No burned pixels (burn_doy = 0)",
                 paste("Timestamp:", Sys.time())), skip_file)
    return(skip_file)
  }

  # Convert burn day-of-year to days since 1970-01-01
  epoch_dates <- as.integer(year_start_epoch + as.integer(doy_v[valid]) - 1L)
  df <- tibble::tibble(
    pid      = as.integer(pid_vec[valid]),
    date     = epoch_dates,
    burn_doy = as.integer(doy_v[valid]),
    qa       = 0L   # placeholder — no QA filtering applied; burn_doy > 0 is the fire indicator
  )

  parquet_file <- file.path(out_dir, paste0("burn_viirs_", yyyymm, ".parquet"))
  unlink(parquet_file)
  arrow::write_parquet(df, sink = parquet_file, compression = "gzip")
  if (verbose) message("Wrote ", nrow(df), " burned pixels → ", basename(parquet_file))

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
    output_dir  = "data/target_outputs/burndates/",
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
