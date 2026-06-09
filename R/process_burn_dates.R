# ============================================================================
# Burn Date Post-Processing
# ============================================================================
# Implements the EMMA burn pipeline redesign (BURNPLAN.md).  Three fire sources
# are integrated into a single, deduplicated fire-event table, then consumed to
# produce per-pixel fire-age parquets that mirror the VI parquet structure.
#
# Priority order: CapeNature  >  VIIRS (VNP64A1, 375 m)  >  MODIS (MCD64A1, 500 m)
#
# Functions (in pipeline order):
#   process_capenature_to_parquet()  — QC-clean CapeNature polygons → burned-
#                                       pixel parquet with fractional cover
#   merge_burn_dates()               — merge 3 sources; 6-month cluster dedup
#   compute_fire_state()             — incremental per-pixel running state file
#   compute_fire_age_for_vi()        — join state to VI parquets → fire_age_*.parquet
#   most_recent_burn_to_grid()       — snapshot raster from state file
# ============================================================================


# ── Internal helpers ──────────────────────────────────────────────────────────

# Greedy 6-month cluster assignment for a sorted date vector (days since epoch).
# Called once per pid group inside merge_burn_dates().
# A single pixel does not burn twice within 6 months — multi-sensor detections
# of the same fire are collapsed into one canonical event.
.assign_fire_clusters <- function(dates_sorted) {
  n       <- length(dates_sorted)
  cluster <- integer(n)
  if (n == 0L) return(cluster)
  current_cluster <- 1L
  anchor          <- dates_sorted[1L]
  cluster[1L]     <- current_cluster
  for (i in seq_len(n - 1L) + 1L) {
    if (dates_sorted[i] - anchor > 182L) {
      current_cluster <- current_cluster + 1L
      anchor          <- dates_sorted[i]
    }
    cluster[i] <- current_cluster
  }
  cluster
}


# Rasterize one reprojected CapeNature fire polygon against the domain grid,
# returning a tibble of burned pixels (burn_fraction > 0.5 only).
.rasterize_one_fire <- function(
    poly_vect,
    domain_r,
    pid_vec,
    burn_date_int,
    date_uncertainty_days
) {
  cover_r <- terra::rasterize(poly_vect, domain_r, cover = TRUE)
  cover_v <- terra::values(cover_r)[, 1]

  # pixels within domain AND covered by this polygon
  valid <- !is.na(pid_vec) & !is.na(cover_v) & cover_v > 0
  if (!any(valid)) return(NULL)

  tibble::tibble(
    pid                   = as.integer(pid_vec[valid]),
    date                  = burn_date_int,
    source                = "capenature",
    date_uncertainty_days = as.integer(date_uncertainty_days),
    burn_fraction         = as.numeric(cover_v[valid])
  ) |>
    # majority-pixel rule: pixel must be more than half covered by the fire
    dplyr::filter(.data$burn_fraction > 0.5)
}


# ── 1. CapeNature processing ──────────────────────────────────────────────────

#' @title Clean CapeNature fire polygons and rasterize to burned-pixel parquet
#'
#' @description Applies manual date corrections (QC cleaning), derives a
#'   canonical \code{burn_date} per polygon using the date hierarchy defined in
#'   BURNPLAN.md §4, applies post-clean filters, then rasterizes each polygon
#'   against the 500 m domain grid using fractional-cover rasterization
#'   (\code{terra::rasterize(..., cover = TRUE)}). Only pixels with
#'   \code{burn_fraction > 0.5} (majority-pixel rule) are retained.
#'
#'   The output parquet has one row per burned pixel per fire event:
#'   \describe{
#'     \item{pid}{int32 — domain pixel ID}
#'     \item{date}{int32 — DATE_START as days since 1970-01-01}
#'     \item{source}{chr — "capenature"}
#'     \item{date_uncertainty_days}{int16 — 0 if exact date, else fire span}
#'     \item{burn_fraction}{float32 — fraction of 500 m pixel covered}
#'   }
#'
#' @param capenature_fires   sf object from the CapeNature fire shapefile.
#' @param domain_raster      SpatRaster (or path) carrying a \code{pid} layer.
#' @param date_fixes_csv     Path to the manual date-correction CSV
#'   (columns: \code{fire_code, field, raw_value, corrected_value, note}).
#' @param out_file           Output parquet path.
#' @param max_corrupt_future Integer. Error if future-date count exceeds this.
#' @param max_corrupt_other  Integer. Error if reversed/long-span count exceeds.
#' @param verbose            Logical. Print progress messages?
#'
#' @return Character path to the written parquet file.
#' @export
process_capenature_to_parquet <- function(
    capenature_fires,
    domain_raster,
    date_fixes_csv     = "data/manual_download/capenature_date_fixes.csv",
    out_file           = "data/target_outputs/burndates/capenature_burns.parquet",
    max_corrupt_future = 0L,
    max_corrupt_other  = 5L,
    verbose            = TRUE
) {
  # parameters near the top for easy auditing (per R style guide)
  record_start_yr <- 2000L   # post-2000: satellite coverage; drop low-precision CN dates
  today           <- Sys.Date()
  epoch           <- as.Date("1970-01-01")

  # ── 1. Tidy the sf object ──────────────────────────────────────────────────
  required_fields <- c("FIRE_CODE", "LOCAL_DESC", "DATE_START",
                       "DATE_EXTIN", "MONTH", "YEAR")
  missing_fields  <- setdiff(required_fields, names(capenature_fires))
  if (length(missing_fields) > 0) {
    stop(
      "CapeNature shapefile missing expected fields: ",
      paste(missing_fields, collapse = ", ")
    )
  }

  fires_sf <- capenature_fires |>
    dplyr::mutate(
      FIRE_CODE  = as.character(.data$FIRE_CODE),
      LOCAL_DESC = as.character(.data$LOCAL_DESC),
      DATE_START = as.character(.data$DATE_START),
      DATE_EXTIN = as.character(.data$DATE_EXTIN),
      MONTH      = as.integer(.data$MONTH),
      YEAR       = as.integer(.data$YEAR),
      .row_id    = dplyr::row_number()
    )

  if (verbose) message("CapeNature: ", nrow(fires_sf), " raw polygons")

  # ── 2. Apply manual date corrections ──────────────────────────────────────
  if (file.exists(date_fixes_csv)) {
    fixes <- readr::read_csv(
      date_fixes_csv,
      col_types     = readr::cols(.default = readr::col_character()),
      show_col_types = FALSE
    )
    # fire_code-specific corrections: match on FIRE_CODE, set field value
    fc_fixes <- dplyr::filter(
      fixes, !is.na(.data$fire_code) & nchar(trimws(.data$fire_code)) > 0
    )
    for (i in seq_len(nrow(fc_fixes))) {
      fc  <- trimws(fc_fixes$fire_code[i])
      fld <- trimws(fc_fixes$field[i])
      val <- trimws(fc_fixes$corrected_value[i])
      idx <- which(fires_sf$FIRE_CODE == fc)
      if (length(idx) > 0L && fld %in% names(fires_sf)) {
        fires_sf[[fld]][idx] <- val
      }
    }
    # Global corrections (empty fire_code): match raw_value in the field
    if ("raw_value" %in% names(fixes)) {
      global_fixes <- dplyr::filter(
        fixes, is.na(.data$fire_code) | nchar(trimws(.data$fire_code)) == 0
      )
      for (i in seq_len(nrow(global_fixes))) {
        fld <- trimws(global_fixes$field[i])
        rv  <- trimws(global_fixes$raw_value[i])
        cv  <- trimws(global_fixes$corrected_value[i])
        if (!is.na(rv) && nchar(rv) > 0 && fld %in% names(fires_sf)) {
          idx <- which(fires_sf[[fld]] == rv)
          if (length(idx) > 0L) fires_sf[[fld]][idx] <- cv
        }
      }
    }
    if (verbose) {
      message(
        "Applied ", nrow(fc_fixes), " fire-specific and ",
        if ("raw_value" %in% names(fixes))
          sum(is.na(fixes$fire_code) | nchar(trimws(fixes$fire_code)) == 0)
        else 0L,
        " global date corrections from ", basename(date_fixes_csv)
      )
    }
  } else {
    if (verbose) {
      message(
        "No date_fixes_csv at ", date_fixes_csv,
        " — proceeding without manual corrections"
      )
    }
  }

  # ── 3. Handle "START DATE FAKE" records ───────────────────────────────────
  fake_idx <- grepl("START DATE FAKE", fires_sf$LOCAL_DESC, ignore.case = TRUE)
  if (any(fake_idx, na.rm = TRUE)) {
    if (verbose) {
      message(
        "Setting DATE_START = NA for ", sum(fake_idx, na.rm = TRUE),
        " 'START DATE FAKE' records"
      )
    }
    fires_sf$DATE_START[fake_idx] <- NA_character_
  }

  # ── 4. Parse dates safely ─────────────────────────────────────────────────
  .parse_date <- function(x) {
    d <- suppressWarnings(as.Date(trimws(x), format = "%Y-%m-%d"))
    d[!is.na(d) & d > today + 365L] <- NA  # pre-filter obviously impossible
    d
  }

  fires_sf <- fires_sf |>
    dplyr::mutate(
      date_start_parsed = .parse_date(.data$DATE_START),
      date_extin_parsed = .parse_date(.data$DATE_EXTIN)
    )

  # ── 5. QC validation — flag records for capenature_date_fixes.csv ─────────
  qc_reversed <- which(
    !is.na(fires_sf$date_start_parsed) &
      !is.na(fires_sf$date_extin_parsed) &
      fires_sf$date_extin_parsed < fires_sf$date_start_parsed
  )
  qc_long <- which(
    !is.na(fires_sf$date_start_parsed) &
      !is.na(fires_sf$date_extin_parsed) &
      as.integer(fires_sf$date_extin_parsed - fires_sf$date_start_parsed) > 30L
  )
  qc_future_start <- which(
    !is.na(fires_sf$date_start_parsed) &
      fires_sf$date_start_parsed >= today
  )
  qc_future_extin <- which(
    !is.na(fires_sf$date_extin_parsed) &
      fires_sf$date_extin_parsed >= today
  )

  if (length(qc_reversed) > 0L) {
    warning(
      "CapeNature QC: ", length(qc_reversed),
      " reversed-date records (DATE_EXTIN < DATE_START).",
      " Add to capenature_date_fixes.csv:\n",
      paste(fires_sf$FIRE_CODE[qc_reversed], collapse = "\n")
    )
  }
  if (length(qc_long) > 0L) {
    warning(
      "CapeNature QC: ", length(qc_long),
      " long-span records (>30 days).",
      " Check capenature_date_fixes.csv:\n",
      paste(fires_sf$FIRE_CODE[qc_long], collapse = "\n")
    )
  }

  n_future <- length(qc_future_start) + length(qc_future_extin)
  if (n_future > max_corrupt_future) {
    stop(
      "CapeNature QC: ", n_future, " future-date records exceed threshold ",
      "(max_corrupt_future = ", max_corrupt_future, "). ",
      "Add to capenature_date_fixes.csv: ",
      paste(
        fires_sf$FIRE_CODE[c(qc_future_start, qc_future_extin)],
        collapse = ", "
      )
    )
  }
  n_other <- length(unique(c(qc_reversed, qc_long)))
  if (n_other > max_corrupt_other) {
    stop(
      "CapeNature QC: ", n_other, " corrupt records (reversed/long-span) ",
      "exceed threshold (max_corrupt_other = ", max_corrupt_other, "). ",
      "Add corrections to capenature_date_fixes.csv."
    )
  }

  # ── 6. Derive canonical burn_date (date hierarchy from BURNPLAN §4.3) ─────
  fires_sf <- fires_sf |>
    dplyr::mutate(
      burn_date = dplyr::case_when(
        # 1. Exact DATE_START
        !is.na(.data$date_start_parsed) & .data$date_start_parsed < today
          ~ .data$date_start_parsed,
        # 2. Mid-month when only YEAR+MONTH known
        is.na(.data$date_start_parsed) &
          !is.na(.data$MONTH) & .data$MONTH > 0L
          ~ as.Date(paste0(
              .data$YEAR, "-",
              formatC(.data$MONTH, width = 2L, flag = "0"), "-15"
            )),
        # 3. Mid-year for pre-1996 year-only records
        is.na(.data$date_start_parsed) &
          (is.na(.data$MONTH) | .data$MONTH == 0L) & .data$YEAR < 1996L
          ~ as.Date(paste0(.data$YEAR, "-01-01")),
        # 4. No derivable date — will be dropped
        TRUE ~ NA_Date_
      ),
      date_uncertainty_days = dplyr::case_when(
        # Fire duration bounds pixel-burn uncertainty when duration is known
        !is.na(.data$date_start_parsed) &
          !is.na(.data$date_extin_parsed) &
          .data$date_extin_parsed > .data$date_start_parsed
          ~ as.integer(.data$date_extin_parsed - .data$date_start_parsed),
        # Exact date known
        !is.na(.data$date_start_parsed)
          ~ 0L,
        # Only month known: mid-month assignment
        !is.na(.data$MONTH) & .data$MONTH > 0L
          ~ 15L,
        # Only year known (pre-1996): ~half year
        .data$YEAR < 1996L
          ~ 180L,
        TRUE ~ NA_integer_
      )
    )

  # ── 7. Post-clean filtering ────────────────────────────────────────────────
  # Drop future burn_dates
  fires_sf <- dplyr::filter(
    fires_sf, is.na(.data$burn_date) | .data$burn_date < today
  )

  # Drop post-2000 low-precision records: post-2000 satellite coverage makes
  # month-only or year-only CapeNature dates redundant noise
  fires_sf <- dplyr::filter(
    fires_sf,
    !(
      !is.na(.data$burn_date) &
        as.integer(format(.data$burn_date, "%Y")) >= record_start_yr &
        is.na(.data$date_start_parsed)
    )
  )

  # Drop records with no derivable burn_date
  fires_sf <- dplyr::filter(fires_sf, !is.na(.data$burn_date))

  if (verbose) {
    message(
      "CapeNature: ", nrow(fires_sf),
      " polygons after cleaning (of ", nrow(capenature_fires), " raw)"
    )
  }

  if (nrow(fires_sf) == 0L) {
    if (verbose) message("No valid CapeNature records — writing empty parquet")
    empty <- tibble::tibble(
      pid                   = integer(0),
      date                  = integer(0),
      source                = character(0),
      date_uncertainty_days = integer(0),
      burn_fraction         = double(0)
    )
    dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(empty, out_file)
    return(out_file)
  }

  # ── 8. Rasterize with fractional cover ────────────────────────────────────
  domain_r <- if (is.character(domain_raster)) {
    terra::rast(domain_raster)
  } else {
    domain_raster
  }
  stopifnot("pid" %in% names(domain_r))

  pid_vec <- terra::values(domain_r[["pid"]])[, 1]

  # Reproject all fires to domain CRS in one batch (fast)
  fires_vect <- terra::project(
    terra::vect(fires_sf),
    terra::crs(domain_r)
  )

  # Per-polygon rasterization with fractional cover (majority-pixel rule = 0.5)
  if (verbose) {
    message(
      "Rasterizing ", nrow(fires_sf),
      " CapeNature polygons with fractional cover ..."
    )
  }

  result_list <- vector("list", nrow(fires_sf))
  for (i in seq_len(nrow(fires_sf))) {
    result_list[[i]] <- tryCatch(
      .rasterize_one_fire(
        poly_vect             = fires_vect[i, ],
        domain_r              = domain_r,
        pid_vec               = pid_vec,
        burn_date_int         = as.integer(fires_sf$burn_date[i] - epoch),
        date_uncertainty_days = as.integer(fires_sf$date_uncertainty_days[i])
      ),
      error = function(e) {
        warning(
          "Skipping polygon ", i,
          " (FIRE_CODE=", fires_sf$FIRE_CODE[i], "): ", conditionMessage(e)
        )
        NULL
      }
    )
  }

  burn_events <- dplyr::bind_rows(result_list)

  if (nrow(burn_events) == 0L) {
    if (verbose) message("No pixels burned within domain after rasterization")
  } else {
    if (verbose) {
      message(
        "CapeNature rasterized: ", nrow(burn_events),
        " burned pixel × fire-event rows (", length(unique(burn_events$pid)),
        " unique pixels)"
      )
    }
  }

  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  unlink(out_file)
  arrow::write_parquet(
    burn_events,
    sink        = out_file,
    compression = "gzip"
  )
  if (verbose) message("Wrote CapeNature burn events: ", basename(out_file))
  out_file
}


# ── 2. Merge burn sources ─────────────────────────────────────────────────────

#' @title Merge MODIS, VIIRS, and CapeNature burn events into one dedup table
#'
#' @description Reads all monthly parquet files from the burn directory plus the
#'   CapeNature parquet, unifies them to a common schema, then applies a greedy
#'   6-month per-pixel clustering to collapse multi-sensor detections of the
#'   same fire into one canonical event. Source priority:
#'   CapeNature > VIIRS > MODIS.
#'
#'   The returned tibble has one row per pixel × distinct fire:
#'   \describe{
#'     \item{pid}{int32}
#'     \item{date}{int32 — canonical date, days since 1970-01-01}
#'     \item{fire_source}{chr — "capenature" | "viirs" | "modis"}
#'     \item{date_uncertainty_days}{int16 — base uncertainty + cluster spread}
#'     \item{burn_fraction}{float32 — CapeNature fractional cover; NA otherwise}
#'   }
#'
#' @param burn_dir           Directory containing \code{burn_modis_*.parquet}
#'   and \code{burn_viirs_*.parquet} files.
#' @param capenature_parquet Path to the CapeNature burned-pixel parquet
#'   (from \code{process_capenature_to_parquet()}). NULL to skip.
#' @param verbose            Logical. Print progress messages?
#'
#' @return Tibble of deduplicated fire events.
#' @export
merge_burn_dates <- function(
    burn_dir           = "data/target_outputs/burndates/",
    capenature_parquet = NULL,
    verbose            = TRUE
) {
  # Helper: read parquets matching pattern, add source column, standardise schema
  .read_burn_parquets <- function(pattern, source_label) {
    paths <- list.files(burn_dir, pattern = pattern, full.names = TRUE)
    if (length(paths) == 0L) {
      if (verbose) {
        message("No parquets in ", burn_dir, " matching ", pattern)
      }
      return(tibble::tibble(
        pid                   = integer(0),
        date                  = integer(0),
        source                = character(0),
        date_uncertainty_days = integer(0),
        burn_fraction         = double(0)
      ))
    }
    if (verbose) {
      message("Reading ", length(paths), " ", source_label, " parquets")
    }
    arrow::open_dataset(paths) |>
      dplyr::select("pid", "date", "burn_doy") |>
      dplyr::filter(!is.na(.data$date), .data$burn_doy > 0L) |>
      dplyr::collect() |>
      dplyr::mutate(
        source                = source_label,
        date_uncertainty_days = 8L,   # half of 16-day compositing window
        burn_fraction         = NA_real_
      ) |>
      dplyr::select("pid", "date", "source", "date_uncertainty_days",
                    "burn_fraction")
  }

  modis_burns <- .read_burn_parquets("^burn_modis_.*\\.parquet$", "modis")
  viirs_burns <- .read_burn_parquets("^burn_viirs_.*\\.parquet$", "viirs")

  # CapeNature burns have exact dates and fractional cover
  cn_burns <- if (!is.null(capenature_parquet) && file.exists(capenature_parquet)) {
    if (verbose) message("Reading CapeNature parquet: ", basename(capenature_parquet))
    arrow::read_parquet(capenature_parquet) |>
      dplyr::select("pid", "date", "source", "date_uncertainty_days",
                    "burn_fraction")
  } else {
    tibble::tibble(
      pid                   = integer(0),
      date                  = integer(0),
      source                = character(0),
      date_uncertainty_days = integer(0),
      burn_fraction         = double(0)
    )
  }

  all_burns <- dplyr::bind_rows(modis_burns, viirs_burns, cn_burns)

  if (nrow(all_burns) == 0L) {
    if (verbose) message("No burn events found — returning empty table")
    return(tibble::tibble(
      pid                   = integer(0),
      date                  = integer(0),
      fire_source           = character(0),
      date_uncertainty_days = integer(0),
      burn_fraction         = double(0)
    ))
  }

  if (verbose) {
    message(
      "Combining ", nrow(modis_burns), " MODIS + ",
      nrow(viirs_burns), " VIIRS + ",
      nrow(cn_burns), " CapeNature raw detections"
    )
  }

  # ── Greedy 6-month per-pixel cluster deduplication ─────────────────────────
  # Sort by pid then date so .assign_fire_clusters receives a sorted date vector
  all_burns_sorted <- all_burns |>
    dplyr::filter(!is.na(.data$pid), !is.na(.data$date)) |>
    dplyr::arrange(.data$pid, .data$date)

  clustered <- all_burns_sorted |>
    dplyr::group_by(.data$pid) |>
    dplyr::mutate(
      cluster_id = .assign_fire_clusters(.data$date)
    ) |>
    dplyr::ungroup()

  # Collapse each (pid, cluster_id) group into one canonical fire event
  deduplicated <- clustered |>
    dplyr::group_by(.data$pid, .data$cluster_id) |>
    dplyr::group_modify(~{
      d <- .x

      cn_rows <- dplyr::filter(d, .data$source == "capenature")

      if (nrow(cn_rows) > 0L) {
        # CapeNature: ground truth — use its date regardless of satellite dates
        canon_date    <- cn_rows$date[1L]
        canon_source  <- "capenature"
        canon_unc     <- as.integer(cn_rows$date_uncertainty_days[1L])
        canon_frac    <- as.numeric(cn_rows$burn_fraction[1L])
      } else {
        # Satellites: use earliest detection; VIIRS preferred over MODIS for ties
        sat <- dplyr::arrange(
          d,
          .data$date,
          dplyr::desc(.data$source == "viirs")
        )
        canon_date   <- sat$date[1L]
        canon_source <- sat$source[1L]
        # Cluster spread widens uncertainty beyond the 8-day base
        spread    <- as.integer(max(d$date) - min(d$date))
        canon_unc <- 8L + spread
        canon_frac <- NA_real_
      }

      tibble::tibble(
        date                  = as.integer(canon_date),
        fire_source           = as.character(canon_source),
        date_uncertainty_days = as.integer(canon_unc),
        burn_fraction         = as.numeric(canon_frac)
      )
    }) |>
    dplyr::ungroup() |>
    dplyr::select("pid", "date", "fire_source", "date_uncertainty_days",
                  "burn_fraction") |>
    dplyr::arrange(.data$pid, .data$date)

  if (verbose) {
    message(
      "Merged burn record: ", nrow(deduplicated), " unique pixel × fire events ",
      "(CapeNature: ",
      sum(deduplicated$fire_source == "capenature", na.rm = TRUE),
      ", VIIRS: ",
      sum(deduplicated$fire_source == "viirs", na.rm = TRUE),
      ", MODIS: ",
      sum(deduplicated$fire_source == "modis", na.rm = TRUE), ")"
    )
  }

  deduplicated
}


# ── 3. Incremental per-pixel fire state ──────────────────────────────────────

#' @title Update the incremental per-pixel most-recent-burn state
#'
#' @description Maintains \code{most_recent_burn_state.parquet} — a per-pixel
#'   running record of the most recent burn date, fire count, and provenance.
#'   Each run:
#'   \enumerate{
#'     \item Reads the current state (or initialises empty if first run).
#'     \item Finds months in \code{burn_events} not yet reflected in the state.
#'     \item Loops over those months in chronological order, updating the state.
#'     \item Writes the updated state parquet.
#'   }
#'   This mirrors the idempotency pattern of the burn download pipeline: only
#'   new months trigger any computation; subsequent runs are no-ops.
#'
#'   State schema (\code{most_recent_burn_state.parquet}):
#'   \describe{
#'     \item{pid}{int32}
#'     \item{state_month}{int32 — last processed month-start, days since epoch}
#'     \item{last_burn_date}{int32 — most recent fire date up to state_month}
#'     \item{fire_count}{int32 — total fires since 2000-01-01 (0 = never burned)}
#'     \item{fire_source}{chr — source of last_burn_date}
#'     \item{date_uncertainty_days}{int16}
#'     \item{burn_fraction}{float32}
#'   }
#'   Pixels with \code{fire_count = 0} are right-censored (minimum age is
#'   \code{state_month − 2000-01-01}).
#'
#' @param burn_events  Tibble from \code{merge_burn_dates()}.
#' @param state_file   Path to the state parquet (read + overwrite each run).
#' @param verbose      Logical. Print progress messages?
#'
#' @return Character path to the (updated) state parquet.
#' @export
compute_fire_state <- function(
    burn_events,
    state_file = "data/target_outputs/most_recent_burn_state.parquet",
    verbose    = TRUE
) {
  record_start <- as.integer(as.Date("2000-01-01") - as.Date("1970-01-01"))

  # ── Load or initialise state ───────────────────────────────────────────────
  if (file.exists(state_file)) {
    state <- arrow::read_parquet(state_file)
    if (verbose) {
      message(
        "Loaded state: ", nrow(state), " pixels, ",
        "last state_month = ",
        format(as.Date(max(state$state_month, record_start),
                       origin = "1970-01-01"))
      )
    }
  } else {
    state <- tibble::tibble(
      pid                   = integer(0),
      state_month           = integer(0),
      last_burn_date        = integer(0),
      fire_count            = integer(0),
      fire_source           = character(0),
      date_uncertainty_days = integer(0),
      burn_fraction         = double(0)
    )
    if (verbose) message("No existing state file — initialising empty state")
  }

  last_state_month <- if (nrow(state) > 0L) {
    max(state$state_month)
  } else {
    record_start
  }

  if (nrow(burn_events) == 0L) {
    if (verbose) message("burn_events is empty — state unchanged")
    dir.create(dirname(state_file), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(state, state_file)
    return(state_file)
  }

  # ── Find new months since last state update ────────────────────────────────
  # Convert burn event dates to month-start integers
  burn_event_dates <- as.Date(burn_events$date, origin = "1970-01-01")
  burn_month_starts <- as.integer(
    as.Date(format(burn_event_dates, "%Y-%m-01")) - as.Date("1970-01-01")
  )

  all_month_starts <- sort(unique(burn_month_starts))
  new_months <- all_month_starts[all_month_starts > last_state_month]

  if (length(new_months) == 0L) {
    if (verbose) message("State is up-to-date — no new months to process")
    dir.create(dirname(state_file), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(state, state_file)
    return(state_file)
  }

  if (verbose) {
    message(
      "Processing ", length(new_months), " new months into fire state ..."
    )
  }

  # ── Stateful for loop: chronological carry-forward ─────────────────────────
  # A for loop is appropriate here — this is explicitly stateful carry-forward
  # (R style guide exception to the prefer-purrr::map rule).
  for (month_start in new_months) {
    # Advance one calendar month: add 32 days then snap to first of that month
    next_month <- as.integer(
      as.Date(
        format(as.Date(month_start, origin = "1970-01-01") + 32L, "%Y-%m-01")
      ) - as.Date("1970-01-01")
    )

    # Fire events for this month
    month_fires <- burn_events |>
      dplyr::filter(
        .data$date >= month_start,
        .data$date < next_month
      ) |>
      dplyr::rename(
        last_burn_date_new        = "date",
        fire_source_new           = "fire_source",
        date_uncertainty_days_new = "date_uncertainty_days",
        burn_fraction_new         = "burn_fraction"
      )

    # New pixels not yet in state get initialised with fire_count = 0
    new_pids <- setdiff(month_fires$pid, state$pid)
    if (length(new_pids) > 0L) {
      state <- dplyr::bind_rows(
        state,
        tibble::tibble(
          pid                   = new_pids,
          state_month           = month_start,
          last_burn_date        = NA_integer_,
          fire_count            = 0L,
          fire_source           = NA_character_,
          date_uncertainty_days = NA_integer_,
          burn_fraction         = NA_real_
        )
      )
    }

    # Update state for all pixels, carrying forward existing values for
    # pixels that did not burn this month
    state <- state |>
      dplyr::left_join(month_fires, by = "pid") |>
      dplyr::mutate(
        did_burn = !is.na(.data$last_burn_date_new),
        last_burn_date = dplyr::if_else(
          .data$did_burn,
          as.integer(.data$last_burn_date_new),
          .data$last_burn_date
        ),
        fire_count = .data$fire_count +
          dplyr::if_else(.data$did_burn, 1L, 0L),
        fire_source = dplyr::if_else(
          .data$did_burn,
          .data$fire_source_new,
          .data$fire_source
        ),
        date_uncertainty_days = dplyr::if_else(
          .data$did_burn,
          as.integer(.data$date_uncertainty_days_new),
          .data$date_uncertainty_days
        ),
        burn_fraction = dplyr::if_else(
          .data$did_burn,
          as.numeric(.data$burn_fraction_new),
          .data$burn_fraction
        ),
        state_month = month_start
      ) |>
      dplyr::select(
        "pid", "state_month", "last_burn_date", "fire_count",
        "fire_source", "date_uncertainty_days", "burn_fraction"
      )
  }

  dir.create(dirname(state_file), recursive = TRUE, showWarnings = FALSE)
  unlink(state_file)
  arrow::write_parquet(state, sink = state_file, compression = "gzip")

  if (verbose) {
    message(
      "State updated: ", nrow(state), " pixels, state_month = ",
      format(as.Date(max(state$state_month), origin = "1970-01-01")),
      ". Wrote ", basename(state_file)
    )
  }

  state_file
}


# ── 4. Fire age at VI observation dates ──────────────────────────────────────

#' @title Compute fire age at every VI observation date
#'
#' @description For each VI parquet in \code{modis_vi_dir} and
#'   \code{viirs_vi_dir} that does not already have a corresponding
#'   \code{fire_age_*.parquet} in \code{out_dir}, joins the per-pixel fire
#'   state to the VI observations and writes a fire-age parquet that mirrors
#'   the VI parquet schema.
#'
#'   Output schema (one row per VI observation row):
#'   \describe{
#'     \item{pid}{int32}
#'     \item{date}{int32 — VI observation date, days since 1970-01-01}
#'     \item{sensor}{int32 — 1=Terra MOD13A1, 2=Aqua MYD13A1,
#'       3=VIIRS S-NPP, 4=NOAA-20}
#'     \item{last_burn_date}{int32 — most recent fire before this VI date (NA = never)}
#'     \item{fire_age_days}{int32 — date − last_burn_date; right-censored for
#'       unburned pixels}
#'     \item{fire_source}{chr — "capenature" | "viirs" | "modis" | NA}
#'     \item{date_uncertainty_days}{int16}
#'     \item{fire_count}{int32 — total fires since 2000-01-01; 0 = right-censored}
#'     \item{burn_fraction}{float32 — CapeNature fractional cover; NA if satellite}
#'   }
#'
#'   Right-censored pixels (\code{fire_count = 0}): \code{fire_age_days =
#'   vi_date − 2000-01-01} (minimum age lower bound), \code{last_burn_date = NA}.
#'   Join to VI parquets via \code{arrow::open_dataset() |> left_join(by =
#'   c("pid", "date", "sensor"))}.
#'
#' @param modis_vi_dir Directory containing MODIS VI parquets.
#' @param viirs_vi_dir Directory containing VIIRS VI parquets.
#' @param state_file   Path to \code{most_recent_burn_state.parquet}
#'   (from \code{compute_fire_state()}).
#' @param out_dir      Directory for \code{fire_age_*.parquet} output files.
#' @param verbose      Logical. Print progress messages?
#'
#' @return Character vector of output parquet file paths (including previously
#'   existing files that were skipped).
#' @export
compute_fire_age_for_vi <- function(
    modis_vi_dir = "data/target_outputs/modis_vi",
    viirs_vi_dir = "data/target_outputs/viirs_vi",
    state_file,
    out_dir      = "data/target_outputs/fire_age/",
    verbose      = TRUE
) {
  record_start <- as.integer(as.Date("2000-01-01") - as.Date("1970-01-01"))

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # ── List all VI parquets ───────────────────────────────────────────────────
  modis_vi_files <- list.files(
    modis_vi_dir, pattern = "^vi_modis_.*\\.parquet$", full.names = TRUE
  )
  viirs_vi_files <- list.files(
    viirs_vi_dir, pattern = "^vi_viirs_.*\\.parquet$", full.names = TRUE
  )
  all_vi_files <- c(modis_vi_files, viirs_vi_files)

  if (length(all_vi_files) == 0L) {
    if (verbose) message("No VI parquets found — returning empty vector")
    return(character(0))
  }

  # Derive output parquet names: vi_modis_* → fire_age_modis_*, etc.
  out_names <- file.path(out_dir, sub("^vi_", "fire_age_", basename(all_vi_files)))

  # Idempotency: skip files already written (same pattern as burn pipeline)
  todo <- !file.exists(out_names)
  if (verbose) {
    message(
      length(all_vi_files), " VI parquets total; ",
      sum(todo), " need fire_age computation, ",
      sum(!todo), " already exist (skipping)"
    )
  }

  if (!any(todo)) return(out_names)

  # ── Load state once (shared across all VI files) ───────────────────────────
  if (!file.exists(state_file)) {
    stop("state_file not found: ", state_file,
         ". Run compute_fire_state() first.")
  }
  state <- arrow::read_parquet(state_file)

  if (verbose) {
    message(
      "Loaded fire state: ", nrow(state), " pixels, state_month = ",
      format(as.Date(max(state$state_month, record_start),
                     origin = "1970-01-01"))
    )
  }

  # ── Process each VI parquet that needs a fire_age output ──────────────────
  todo_vi   <- all_vi_files[todo]
  todo_out  <- out_names[todo]

  for (j in seq_along(todo_vi)) {
    vi_file  <- todo_vi[j]
    out_file <- todo_out[j]

    if (verbose) message("Computing fire age: ", basename(vi_file))

    vi_df <- tryCatch(
      arrow::read_parquet(vi_file),
      error = function(e) {
        warning("Could not read ", basename(vi_file), ": ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(vi_df)) next

    # Require pid, date, sensor columns
    req_cols <- c("pid", "date", "sensor")
    missing_cols <- setdiff(req_cols, names(vi_df))
    if (length(missing_cols) > 0L) {
      warning(
        basename(vi_file), " missing columns: ",
        paste(missing_cols, collapse = ", "), " — skipping"
      )
      next
    }

    # Select distinct (pid, date, sensor) observation keys
    obs_keys <- vi_df |>
      dplyr::select("pid", "date", "sensor") |>
      dplyr::distinct()

    # Join state to observation keys on pid
    fire_age_df <- obs_keys |>
      dplyr::left_join(
        dplyr::select(
          state, "pid", "last_burn_date", "fire_count",
          "fire_source", "date_uncertainty_days", "burn_fraction"
        ),
        by = "pid"
      ) |>
      dplyr::mutate(
        # Only use last_burn_date if the burn predates this VI observation;
        # if state captured a post-VI burn (state_month > vi_date), set NA
        last_burn_date_valid = dplyr::if_else(
          !is.na(.data$last_burn_date) &
            .data$last_burn_date < as.integer(.data$date),
          .data$last_burn_date,
          NA_integer_
        ),
        fire_age_days = dplyr::case_when(
          # Known burn predating this observation
          !is.na(.data$last_burn_date_valid)
            ~ as.integer(.data$date - .data$last_burn_date_valid),
          # Right-censored: never burned — minimum age since record start
          is.na(.data$fire_count) | .data$fire_count == 0L
            ~ as.integer(.data$date - record_start),
          # fire_count > 0 but last_burn_date is after vi_date (stale state):
          # treat as right-censored with record_start lower bound
          TRUE ~ as.integer(.data$date - record_start)
        ),
        fire_source = dplyr::if_else(
          !is.na(.data$last_burn_date_valid),
          .data$fire_source,
          NA_character_
        ),
        date_uncertainty_days = dplyr::if_else(
          !is.na(.data$last_burn_date_valid),
          as.integer(.data$date_uncertainty_days),
          NA_integer_
        ),
        fire_count = dplyr::coalesce(as.integer(.data$fire_count), 0L),
        last_burn_date = .data$last_burn_date_valid
      ) |>
      dplyr::select(
        "pid", "date", "sensor",
        "last_burn_date", "fire_age_days", "fire_source",
        "date_uncertainty_days", "fire_count", "burn_fraction"
      )

    unlink(out_file)
    arrow::write_parquet(fire_age_df, sink = out_file, compression = "gzip")

    if (verbose) {
      message(
        "  → ", basename(out_file),
        " (", nrow(fire_age_df), " rows, ",
        sum(!is.na(fire_age_df$last_burn_date)), " burned)"
      )
    }
  }

  out_names
}


# ── 5. Snapshot raster ────────────────────────────────────────────────────────

#' @title Rasterize the most-recent-burn state parquet to a domain-aligned raster
#'
#' @description Reads \code{most_recent_burn_state.parquet} (written by
#'   \code{compute_fire_state()}) and returns a two-band SpatRaster snapshot
#'   at \code{state_month} for storage by \code{geotargets::tar_terra_rast()}:
#'   \describe{
#'     \item{fire_age_days}{Band 1: days since last fire at state_month}
#'     \item{last_burn_date}{Band 2: days since 1970-01-01 of most recent burn}
#'   }
#'   Pixels never burned have \code{fire_age_days = state_month - 2000-01-01}
#'   (right-censored lower bound; \code{fire_count = 0}) and
#'   \code{last_burn_date = NA}.
#'
#' @param state_file   Character path to \code{most_recent_burn_state.parquet}.
#' @param domain_raster SpatRaster or path with a \code{pid} layer.
#' @param verbose      Logical. Print progress messages?
#'
#' @return Two-band SpatRaster (fire_age_days, last_burn_date).
#' @export
most_recent_burn_to_grid <- function(
    state_file,
    domain_raster,
    verbose = TRUE
) {
  domain_r <- if (is.character(domain_raster)) {
    terra::rast(domain_raster)
  } else {
    domain_raster
  }

  state <- arrow::read_parquet(state_file)

  # For empty state, return all-NA raster
  if (nrow(state) == 0L) {
    if (verbose) message("State is empty — returning all-NA raster")
    empty <- domain_r[[1L]]
    terra::values(empty) <- NA_integer_
    r_out <- c(empty, empty)
    names(r_out) <- c("fire_age_days", "last_burn_date")
    terra::metags(r_out) <- c(
      snapshot_date = as.character(Sys.Date()),
      source        = "most_recent_burn_state"
    )
    return(r_out)
  }

  record_start  <- as.integer(as.Date("2000-01-01") - as.Date("1970-01-01"))
  snapshot_int  <- max(state$state_month, record_start)
  snapshot_date <- as.Date(snapshot_int, origin = "1970-01-01")

  if (verbose) {
    message(
      "Rasterizing most_recent_burn snapshot for ",
      format(snapshot_date), " (", nrow(state), " pixels in state)"
    )
  }

  pid_vec <- terra::values(domain_r[["pid"]])[, 1]

  # Right-censored pixels: fire_count = 0, use record_start lower bound
  state_snap <- state |>
    dplyr::mutate(
      fire_age_days = dplyr::if_else(
        !is.na(.data$last_burn_date),
        as.integer(snapshot_int - .data$last_burn_date),
        as.integer(snapshot_int - record_start)  # right-censored
      )
    )

  fire_age_map  <- setNames(state_snap$fire_age_days,  as.character(state_snap$pid))
  last_burn_map <- setNames(state_snap$last_burn_date, as.character(state_snap$pid))

  fire_age_vec  <- as.integer(fire_age_map[as.character(pid_vec)])
  last_burn_vec <- as.integer(last_burn_map[as.character(pid_vec)])

  fire_age_r  <- domain_r[[1L]]
  last_burn_r <- domain_r[[1L]]
  terra::values(fire_age_r)  <- fire_age_vec
  terra::values(last_burn_r) <- last_burn_vec
  names(fire_age_r)  <- "fire_age_days"
  names(last_burn_r) <- "last_burn_date"

  r_out <- c(fire_age_r, last_burn_r)
  terra::metags(r_out) <- c(
    snapshot_date = as.character(snapshot_date),
    source        = "most_recent_burn_state"
  )

  if (verbose) message("Built most_recent_burn raster for ", format(snapshot_date))
  r_out
}
