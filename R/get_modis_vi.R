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
  composite_date,
  composite_end,
  out_dir        = NULL,
  gh_release_tag = NULL,
  verbose        = TRUE
) {

  yyyymmdd <- format(as.Date(composite_date), "%Y%m%d")

  # Check local disk (fast — works on server after a completed run)
  if (!is.null(out_dir)) {
    terra_tif <- file.path(out_dir, paste0("vi_modis_terra_", yyyymmdd, ".tif"))
    if (file.exists(terra_tif)) {
      if (verbose) message("Grid COG on disk for ", yyyymmdd, " — skipping AppEEARS submission")
      return(paste0("cached:", yyyymmdd))
    }
  }

  # Check GitHub release (authoritative — works on CI where disk is empty)
  if (!is.null(gh_release_tag)) {
    repo <- Sys.getenv("TAR_GH_RELEASE_REPO", unset = "AdamWilsonLab/emma_envdata")
    if (gh_release_has_asset(repo, gh_release_tag, paste0("vi_modis_terra_", yyyymmdd, ".tif"), verbose = verbose)) {
      if (verbose) message("Composite ", yyyymmdd, " already on GitHub release '", gh_release_tag, "' — skipping AppEEARS submission")
      return(paste0("cached:", yyyymmdd))
    }
  }

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
  composite_date <- as.Date(composite_date)
  composite_end  <- as.Date(composite_end)

  if (verbose) {
    message("AppEEARS MODIS VI composite request: ", format(composite_date, "%Y-%m-%d"),
            " to ", format(composite_end, "%Y-%m-%d"))
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
    task_name = paste0("MODIS_VI_", format(composite_date, "%Y%m%d"), "_", format(Sys.time(), "%H%M%S")),
    params = list(
      dates = list(list(
        startDate = format(composite_date, "%m-%d-%Y"),
        endDate   = format(composite_end,  "%m-%d-%Y")
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
        format = list(type = "geotiff"),
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




#' @title Download MODIS VI GeoTIFF files from AppEEARS
#' @description Polls for completion of an AppEEARS area task and downloads
#'   GeoTIFF results for one 16-day MODIS VI composite. Separates I/O from
#'   computation for independent parallelisation. If the task is not found
#'   (e.g. expired after 14 days) and \code{domain_vector} plus
#'   \code{composite_end} are supplied, the task is automatically re-submitted.
#' @param task_id Character. AppEEARS task ID, or a \code{"cached:YYYYMMDD"}
#'   sentinel returned by \code{submit_modis_vi()} when the composite is
#'   already complete on disk.
#' @param composite_date Date or "YYYY-MM-DD". First day of the 16-day window.
#' @param composite_end  Date or "YYYY-MM-DD". Last day of the 16-day window.
#'   Required only for automatic re-submission on task expiry.
#' @param domain_vector  SpatVector or sf polygon used to re-submit if expired.
#'   Optional; if NULL a missing-status error is raised instead.
#' @param temp_directory Character. Temporary working directory for downloads.
#' @param cleanup Logical. Delete temp files after \code{vi_modis_geotiff_to_grid()}
#'   writes COGs? Defaults to TRUE on GitHub Actions.
#' @param verbose Logical. Print progress messages?
#' @return Character path to temp_directory, or path to a \code{.skip} marker
#'   when AppEEARS returned no files.
#' @export
download_modis_vi_geotiff <- function(
    task_id,
    composite_date,
    composite_end  = NULL,
    domain_vector  = NULL,
    temp_directory = "data/temp/appeears/modis_vi/",
    cleanup        = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose        = TRUE) {

  # Sentinel task_id means submit_modis_vi() found the composite already complete —
  # skip all AppEEARS polling and return the temp directory path directly.
  if (startsWith(task_id, "cached:")) {
    yyyymmdd_sentinel <- sub("^cached:", "", task_id)
    if (verbose) message("Sentinel task_id for ", yyyymmdd_sentinel,
                         " \u2014 skipping AppEEARS download")
    dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
    return(temp_directory)
  }

  ensure_appeears_auth()
  composite_date <- as.Date(composite_date)
  yyyymmdd       <- format(composite_date, "%Y%m%d")

  cache_dir <- "data/target_outputs/modis_vi"
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  # Early-exit: Terra COG written by vi_modis_geotiff_to_grid() signals completion
  terra_tif_done <- file.path(cache_dir, paste0("vi_modis_terra_", yyyymmdd, ".tif"))
  if (file.exists(terra_tif_done)) {
    if (verbose) message("Grid COG found for ", yyyymmdd,
                         " \u2014 skipping AppEEARS download")
    dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
    return(temp_directory)
  }

  # Per-branch subdir to avoid race conditions under parallel tar_make_future()
  temp_directory <- file.path(temp_directory, yyyymmdd)
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  if (verbose) message("Polling task ", task_id, " for completion...")
  max_retries  <- 15L
  retry_count  <- 0L
  null_retries <- 0L

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
          message("[AppEEARS] Task ", task_id,
                  " not found (likely expired) \u2014 re-submitting for ", yyyymmdd)
        }
        task_id <- submit_modis_vi(
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
    skip_file <- file.path(cache_dir, paste0("vi_modis_", yyyymmdd, ".skip"))
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


#' @title Convert MODIS VI AppEEARS GeoTIFF downloads to domain-aligned COG grids
#'
#' @description Processes raw AppEEARS GeoTIFF downloads for one 16-day composite:
#'   reads EVI, VI_Quality and composite_day_of_the_year TIFs, applies QA masking,
#'   reprojects to the domain grid (EPSG:9221), and writes two 2-band COGs —
#'   one for Terra (MOD13A1) and one for Aqua (MYD13A1) — each with bands
#'   \code{evi} (EVI \eqn{\times} 100, QA-masked, integer) and \code{doy}
#'   (composite day-of-year, per pixel, integer).
#'   Both files are always written (all-NA placeholder when no source data exist).
#'
#' @param geotiff_directory Character. Path to directory of raw AppEEARS GeoTIFFs,
#'   or path to a \code{.skip} marker from \code{download_modis_vi_geotiff()}.
#' @param domain_raster   Character path or SpatRaster with a \code{pid} layer.
#' @param composite_date  Date or "YYYY-MM-DD". First day of the 16-day window.
#' @param out_dir         Output directory for the two sensor COGs.
#' @param cleanup         Logical. Delete raw AppEEARS temp files after writing?
#' @param verbose         Logical. Print progress messages?
#'
#' @return Character vector of length 2:
#'   \code{c("out_dir/vi_modis_terra_YYYYMMDD.tif", "out_dir/vi_modis_aqua_YYYYMMDD.tif")}.
#' @export
vi_modis_geotiff_to_grid <- function(
    geotiff_directory,
    domain_raster,
    composite_date,
    out_dir  = "data/target_outputs/modis_vi/",
    cleanup  = Sys.getenv("GITHUB_ACTIONS") == "true",
    verbose  = TRUE) {

  composite_date <- as.Date(composite_date)
  yyyymmdd       <- format(composite_date, "%Y%m%d")

  terra_tmp <- file.path(getwd(), "data/temp/terra", paste0(yyyymmdd, "_modis"))
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terra::terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_terra <- file.path(out_dir, paste0("vi_modis_terra_", yyyymmdd, ".tif"))
  out_aqua  <- file.path(out_dir, paste0("vi_modis_aqua_",  yyyymmdd, ".tif"))

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
                       gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "ZLEVEL=9",
                                "SPARSE_OK=YES"),
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
    write_na_cog(out_terra, "Terra/MOD13A1")
    write_na_cog(out_aqua,  "Aqua/MYD13A1")
    if (cleanup && !grepl("\\.skip$", geotiff_directory) && dir.exists(geotiff_directory)) {
      unlink(geotiff_directory, recursive = TRUE, force = TRUE)
    }
    return(c(out_terra, out_aqua))
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
  # Pattern: MOD13A1.061__500m_16_days_EVI_YYYYMMDDTHHMMSS_aid0001.tif
  classify_tif <- function(path) {
    bn      <- basename(path)
    product <- if (grepl("MOD13A1", bn)) "terra" else
               if (grepl("MYD13A1", bn)) "aqua"  else NA_character_
    layer   <- if (grepl("_EVI_", bn) && !grepl("Quality", bn)) "evi"  else
               if (grepl("VI_Quality|VI-Quality", bn))           "qa"   else
               if (grepl("composite_day_of_the_year", bn))       "doy"  else NA_character_
    list(path = path, product = product, layer = layer)
  }

  tif_info <- lapply(tif_paths, classify_tif)
  tif_info <- Filter(function(x) !is.na(x$product) && !is.na(x$layer), tif_info)

  # Process one sensor (terra or aqua) → 2-band COG (evi, doy) aligned to domain
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

    # QA-mask EVI; scale to integer \u00d7 100 to match parquet schema
    if (!is.null(qa_r)) {
      keep_mask <- terra::app(qa_r, function(x) x %in% keep_values)
      evi_r     <- terra::mask(evi_r, keep_mask, maskvalue = FALSE)
      if (!is.null(doy_r)) {
        doy_r <- terra::mask(doy_r, keep_mask, maskvalue = FALSE)
      }
    }
    evi_r <- terra::app(evi_r, function(x) as.integer(round(x * 100)))

    # Reproject from native MODIS sinusoidal to domain CRS (EPSG:9221, metres)
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
                       gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "ZLEVEL=9",
                                "SPARSE_OK=YES"),
                       overwrite = TRUE)
    if (verbose) message("Wrote: ", basename(out_path))
  }

  process_sensor("Terra/MOD13A1", "terra", "MOD13A1.061", out_terra)
  process_sensor("Aqua/MYD13A1",  "aqua",  "MYD13A1.061", out_aqua)

  if (cleanup) {
    unlink(geotiff_directory, recursive = TRUE, force = TRUE)
    gc()
    unlink(terra_tmp, recursive = TRUE, force = TRUE)
  }

  c(out_terra, out_aqua)
}


#' @title Convert MODIS VI sensor COG grids to tabular parquet
#'
#' @description Reads the two 2-band sensor COGs produced by
#'   \code{vi_modis_geotiff_to_grid()} and writes a single gzip-compressed
#'   Parquet file with one row per valid (non-NA EVI) pixel.
#'
#' @param tif_files     Character vector of COG paths (terra + aqua).
#' @param domain_raster Character path or SpatRaster with a \code{pid} layer.
#' @param composite_date Date or "YYYY-MM-DD". First day of the 16-day composite.
#' @param out_dir       Output directory for the parquet file.
#' @param verbose       Logical. Print progress messages?
#'
#' @return Character path to \code{dynamic_modis_vi_YYYYMMDD.parquet}, or path to
#'   a \code{vi_modis_YYYYMMDD.skip} marker when all pixels are NA.
#'
#' @details
#' Parquet schema (one row per observation):
#' \describe{
#'   \item{pid}{int32 \u2014 pixel ID from domain grid}
#'   \item{date}{int32 \u2014 days since 1970-01-01, from per-pixel composite DOY}
#'   \item{sensor}{int32 \u2014 sensor code: 1 = Terra (MOD13A1), 2 = Aqua (MYD13A1)}
#'   \item{value}{int32 \u2014 EVI \eqn{\times} 100 (scale factor 0.01)}
#' }
#' @export
vi_modis_geotiff_to_parquet <- function(
    tif_files,
    domain_raster,
    composite_date,
    out_dir  = "data/target_outputs/modis_vi/",
    verbose  = TRUE) {

  composite_date <- as.Date(composite_date)
  yyyymmdd       <- format(composite_date, "%Y%m%d")

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  parquet_file <- file.path(out_dir, paste0("vi_modis_", yyyymmdd, ".parquet"))

  # Load domain for pid values
  domain_template  <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  stopifnot("pid" %in% names(domain_template))
  pid_vec          <- terra::values(domain_template[["pid"]])[, 1]
  ref_year         <- as.integer(format(composite_date, "%Y"))
  year_start_epoch <- as.integer(as.Date(paste0(ref_year, "-01-01")) - as.Date("1970-01-01"))

  # Detect sensor code from filename: _terra_ \u2192 1, _aqua_ \u2192 2
  sensor_code <- function(tif_path) {
    if (grepl("_terra_", basename(tif_path))) 1L else 2L
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
      pid    = as.integer(pid_vec[valid]),
      date   = epoch_dates,
      sensor = s_id,
      value  = as.integer(evi_v[valid])
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
    tibble::tibble(pid = integer(), date = integer(), sensor = integer(), value = integer())
  }

  if (nrow(df) == 0L) {
    if (verbose) message("No valid MODIS VI observations for ", yyyymmdd,
                         " \u2014 writing skip marker")
    skip_file <- file.path(out_dir, paste0("vi_modis_", yyyymmdd, ".skip"))
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

