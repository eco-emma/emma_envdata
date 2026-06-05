# ============================================================================
# Burn Date Post-Processing
# ============================================================================
# Aggregates monthly burn date parquet files (MODIS + VIIRS) into two derived
# products used by the emma_model:
#
#   1. most_recent_burn_date — for each domain pixel and each observation date,
#      the calendar date of the most recent fire BEFORE that observation.
#      Stored as a parquet with schema: pid (int32), as_of_date (int32), last_burn_date (int32)
#
#   2. fire_age — days since last fire for each pixel × date combination.
#      Derived directly from most_recent_burn_date.
#      Same schema plus: fire_age_days (int32)
#
# Strategy:
#   - MODIS burn dates are the primary source (2000–present).
#   - VIIRS burn dates are merged for 2012–present, with MODIS preferred on conflict
#     (MODIS has longer validation history; VIIRS used as gap-fill).
#   - All pixels with no recorded fire are returned with NA last_burn_date.
# ============================================================================


#' @title Merge MODIS and VIIRS monthly burn date parquets into a combined dataset
#'
#' @description Reads all monthly parquet files from both the MODIS and VIIRS
#'   burn date directories, deduplicates overlapping records (preferring MODIS),
#'   and returns a single tidy tibble of all burn events.
#'
#'   The returned tibble has one row per burned pixel × burn event:
#'   \itemize{
#'     \item \code{pid}      (int32): Domain pixel ID
#'     \item \code{date}     (int32): Burn date, days since 1970-01-01
#'     \item \code{burn_doy} (int16): Raw day-of-year
#'     \item \code{source}   (character): "modis" or "viirs"
#'   }
#'
#' @param modis_dir Character. Directory containing monthly MODIS burn date parquets.
#' @param viirs_dir Character. Directory containing monthly VIIRS burn date parquets.
#' @param verbose   Logical. Print progress messages? Default TRUE.
#'
#' @return A tibble of all burn events across the full record.
#' @export
merge_burn_dates <- function(
    burn_dir = "data/target_outputs/burndates/",
    verbose  = TRUE) {

  # Helper: read parquets matching filename pattern, add source column
  read_burn_parquets <- function(pattern, source_label) {
    parquet_files <- list.files(burn_dir, pattern = pattern, full.names = TRUE)

    if (length(parquet_files) == 0) {
      if (verbose) message("No parquet files found in ", burn_dir, " matching ", pattern)
      return(tibble::tibble(pid = integer(), date = integer(), burn_doy = integer(), source = character()))
    }

    if (verbose) message("Reading ", length(parquet_files), " ", source_label, " parquets from ", burn_dir)

    # Use arrow::open_dataset for efficient multi-file reading without loading
    # all files into memory at once — important for 200+ monthly files
    arrow::open_dataset(parquet_files) |>
      dplyr::select("pid", "date", "burn_doy") |>
      dplyr::collect() |>
      dplyr::mutate(source = source_label)
  }

  modis_burns <- read_burn_parquets("^burn_modis_.*\\.parquet$", "modis")
  viirs_burns <- read_burn_parquets("^burn_viirs_.*\\.parquet$", "viirs")

  if (nrow(modis_burns) == 0 && nrow(viirs_burns) == 0) {
    if (verbose) message("No burn date parquet files found in ", burn_dir, " — returning empty burn record")
    return(tibble::tibble(pid = integer(), date = integer(), burn_doy = integer(), source = character()))
  }

  # Combine and deduplicate: for the same pixel × date, keep VIIRS over MODIS
  all_burns <- dplyr::bind_rows(modis_burns, viirs_burns) |>
    dplyr::filter(!is.na(.data$date), .data$burn_doy > 0L) |>
    # Rank by source preference: VIIRS first, then MODIS
    dplyr::mutate(source_rank = dplyr::if_else(.data$source == "viirs", 1L, 2L)) |>
    dplyr::group_by(.data$pid, .data$date) |>
    dplyr::slice_min(.data$source_rank, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select("pid", "date", "burn_doy", "source") |>
    dplyr::arrange(.data$pid, .data$date)

  if (verbose) {
    message(
      "Merged burn record: ", nrow(all_burns), " burn events ",
      "(MODIS: ", sum(all_burns$source == "modis"), ", ",
      "VIIRS: ", sum(all_burns$source == "viirs"), ")"
    )
  }

  all_burns
}


#' @title Compute the most recent burn date for every pixel across the full record
#'
#' @description For each domain pixel, produces a time series of "what was the
#'   most recent burn before date X?" for every month in the record. This table
#'   is the primary fire covariate used by emma_model.
#'
#'   The output parquet has one row per pixel per as-of-date:
#'   \itemize{
#'     \item \code{pid}            (int32): Domain pixel ID
#'     \item \code{as_of_date}     (int32): Query date (days since epoch); typically
#'       the first day of each month in the observation record
#'     \item \code{last_burn_date} (int32): Most recent burn before as_of_date;
#'       NA if pixel has never burned in the record
#'     \item \code{fire_age_days}  (int32): Days since last burn (as_of_date - last_burn_date);
#'       NA if pixel has never burned
#'   }
#'
#' @param burn_events   Tibble from \code{merge_burn_dates()}.
#' @param query_dates   Integer vector of days-since-epoch at which to evaluate
#'   fire age. Typically the first day of each month in the VI record.
#'   If NULL, defaults to every month from burn record start to today.
#' @param out_file      Character. Output parquet file path.
#' @param verbose       Logical. Print progress messages?
#'
#' @return Character path to the written parquet file.
#' @export
compute_most_recent_burn <- function(
    burn_events,
    query_dates = NULL,
    out_file    = "data/target_outputs/most_recent_burn.parquet",
    verbose     = TRUE) {

  if (nrow(burn_events) == 0) {
    if (verbose) message("burn_events is empty — writing empty most_recent_burn parquet")
    dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
    empty <- tibble::tibble(
      pid            = integer(),
      as_of_date     = integer(),
      last_burn_date = integer(),
      fire_age_days  = integer()
    )
    arrow::write_parquet(empty, out_file)
    return(out_file)
  }

  # Default query dates: monthly sequence from first burn to today
  if (is.null(query_dates) || length(query_dates) == 0L) {
    first_burn    <- as.Date(min(burn_events$date, na.rm = TRUE), origin = "1970-01-01")
    first_month   <- as.Date(format(first_burn, "%Y-%m-01"))
    all_months    <- seq(first_month, Sys.Date(), by = "month")
    query_dates   <- as.integer(all_months - as.Date("1970-01-01"))
  }

  if (verbose) {
    message(
      "Computing most recent burn for ", length(unique(burn_events$pid)), " pixels ",
      "over ", length(query_dates), " query dates"
    )
  }

  # For each query date, find the most recent burn on or before that date.
  # Implemented with a tidy non-equi join approach:
  #   1. Cross every (pid, query_date) pair with the burn event table for that pid
  #   2. Keep only burns that occurred before the query date
  #   3. Take the maximum burn date (most recent)
  #
  # This is done in chunks over query dates to keep memory usage bounded.

  # Create a lookup of all pixels that ever burned
  burned_pids <- unique(burn_events$pid)

  # Chunk query dates into groups of 12 months to avoid memory blowup
  chunk_size   <- 12L
  date_chunks  <- split(query_dates, ceiling(seq_along(query_dates) / chunk_size))

  result_list <- purrr::map(date_chunks, function(dates_chunk) {
    # For this chunk of dates, find last burn ≤ each date for each burned pixel
    # Use a cross-product then filter approach (efficient for moderate # pids)
    purrr::map_dfr(dates_chunk, function(qdate) {
      burn_events |>
        dplyr::filter(.data$date <= qdate) |>            # only burns before query date
        dplyr::group_by(.data$pid) |>
        dplyr::summarise(
          last_burn_date = max(.data$date, na.rm = TRUE),
          .groups        = "drop"
        ) |>
        dplyr::mutate(
          as_of_date    = qdate,
          fire_age_days = qdate - .data$last_burn_date
        )
    })
  })

  result_df <- dplyr::bind_rows(result_list) |>
    dplyr::select("pid", "as_of_date", "last_burn_date", "fire_age_days") |>
    dplyr::arrange(.data$pid, .data$as_of_date)

  if (verbose) {
    message(
      "Writing ", nrow(result_df), " rows to ", basename(out_file)
    )
  }

  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  unlink(out_file)
  arrow::write_parquet(result_df, sink = out_file, compression = "gzip")
  out_file
}


#' @title Identify query dates from the MODIS VI parquet record
#'
#' @description Reads the MODIS VI parquet directory and returns a vector of
#'   unique observation dates as integers (days since 1970-01-01). These are
#'   used as query dates for \code{compute_most_recent_burn()} so that fire age
#'   is evaluated at exactly the dates where VI observations exist.
#'
#' @param modis_vi_dir Character. Directory containing monthly MODIS VI parquets.
#' @param verbose Logical. Print progress messages?
#'
#' @return Integer vector of unique observation dates (days since epoch).
#' @export
vi_load_observation_dates <- function(
    modis_vi_dir = "data/target_outputs/modis_vi",
    verbose      = TRUE) {

  parquet_files <- list.files(modis_vi_dir, pattern = "\\.parquet$", full.names = TRUE)

  if (length(parquet_files) == 0) {
    if (verbose) message("No MODIS VI parquet files found in ", modis_vi_dir, " — returning empty date vector")
    return(integer(0))
  }

  if (verbose) message("Scanning ", length(parquet_files), " MODIS VI parquets for observation dates")

  # Read only the date column across all files (efficient with Arrow)
  dates <- arrow::open_dataset(parquet_files) |>
    dplyr::select("date") |>
    dplyr::distinct() |>
    dplyr::collect() |>
    dplyr::pull("date") |>
    sort()

  if (verbose) message("Found ", length(dates), " unique observation dates")
  dates
}


#' @title Rasterize most-recent-burn parquet to a domain-aligned SpatRaster
#'
#' @description Reads \code{most_recent_burn.parquet} (columns: pid, as_of_date,
#'   last_burn_date, fire_age_days), finds the latest available \code{as_of_date},
#'   and returns a two-band SpatRaster snapshot for storage by
#'   \code{geotargets::tar_terra_rast()} as a Cloud Optimized GeoTIFF:
#'   \describe{
#'     \item{fire_age_days}{Band 1: integer days since last fire per pixel}
#'     \item{last_burn_date}{Band 2: integer days since 1970-01-01 of last burn per pixel}
#'   }
#'   Pixels that never burned are written as \code{NA}.
#'
#' @param parquet_file Character path to \code{most_recent_burn.parquet}.
#' @param domain_raster A \code{SpatRaster} (or file path) carrying a \code{pid}
#'   layer used to map pixel IDs to grid cells.
#' @param verbose Logical. Print progress messages?
#'
#' @return A two-band \code{SpatRaster} (fire_age_days, last_burn_date).
#' @export
most_recent_burn_to_grid <- function(
    parquet_file,
    domain_raster,
    verbose = TRUE) {

  # Load domain grid (accept file path or SpatRaster)
  if (is.character(domain_raster)) {
    domain_template <- terra::rast(domain_raster)
  } else {
    domain_template <- domain_raster
  }

  df <- arrow::read_parquet(parquet_file)

  if (nrow(df) == 0L) {
    if (verbose) message("most_recent_burn parquet is empty — returning all-NA raster")
    empty_r       <- domain_template[[1]]
    terra::values(empty_r) <- NA_integer_
    r_out         <- c(empty_r, empty_r)
    names(r_out)  <- c("fire_age_days", "last_burn_date")
    terra::metags(r_out) <- c(
      snapshot_date = as.character(Sys.Date()),
      source        = "most_recent_burn"
    )
    return(r_out)
  }

  # Snapshot: use the latest as_of_date only
  latest_date   <- max(df$as_of_date)
  df_latest     <- df[df$as_of_date == latest_date, ]
  snapshot_date <- as.Date(latest_date, origin = "1970-01-01")

  if (verbose) {
    message("Rasterizing most_recent_burn snapshot for ", format(snapshot_date),
            " (", nrow(df_latest), " burned pixels)")
  }

  # Map pid → raster cell values
  pid_vec <- terra::values(domain_template[["pid"]])[, 1]

  fire_age_map  <- setNames(df_latest$fire_age_days,  as.character(df_latest$pid))
  last_burn_map <- setNames(df_latest$last_burn_date, as.character(df_latest$pid))

  fire_age_vec  <- as.integer(fire_age_map[as.character(pid_vec)])
  last_burn_vec <- as.integer(last_burn_map[as.character(pid_vec)])

  # Build 2-band raster: band 1 = fire_age_days, band 2 = last_burn_date
  fire_age_r  <- domain_template[[1]]
  last_burn_r <- domain_template[[1]]
  terra::values(fire_age_r)  <- fire_age_vec
  terra::values(last_burn_r) <- last_burn_vec
  names(fire_age_r)  <- "fire_age_days"
  names(last_burn_r) <- "last_burn_date"

  r_out <- c(fire_age_r, last_burn_r)
  terra::metags(r_out) <- c(
    snapshot_date = as.character(snapshot_date),
    source        = "most_recent_burn"
  )

  if (verbose) message("Built most_recent_burn raster for ", format(snapshot_date))
  r_out
}
