# ============================================================================
# Burn Date Post-Processing
# ============================================================================
# Implements the EMMA burn pipeline redesign (BURNPLAN.md).  Fire sources are
# integrated into a single, deduplicated fire-event table, then consumed to
# produce per-pixel fire-age parquets that mirror the VI parquet structure.
#
# Priority order:
#   CapeNature  >  TMNP (Table Mountain NP only)  >  VIIRS  >  MODIS
#
# Functions (in pipeline order):
#   process_capenature_to_parquet()  — QC-clean CapeNature polygons → burned-
#                                       pixel parquet with fractional cover
#   download_tmnp_fire_shapefile()   — flat tmnp_fire_1962_2021.* from manual-data
#   process_tmnp_to_parquet()        — TMNP polygons → burned-pixel parquet
#   merge_burn_dates()               — merge sources; 6-month cluster dedup
#   compute_fire_state()             — incremental per-pixel running state file
#   compute_fireage_for_vi()         — join state to VI parquets → fireage_*.parquet
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


# Parse calendar dates from character vectors that may be ISO (`YYYY-MM-DD`)
# or CapeNature-style day/month/year (`DD/MM/YYYY`). Returns Date; invalid → NA.
.parse_flexible_date <- function(x, today = Sys.Date()) {
  x <- trimws(as.character(x))
  x[x == "" | is.na(x)] <- NA_character_
  d <- suppressWarnings(as.Date(x, format = "%Y-%m-%d"))
  need_dmy <- is.na(d) & !is.na(x)
  if (any(need_dmy)) {
    d[need_dmy] <- suppressWarnings(
      as.Date(x[need_dmy], format = "%d/%m/%Y")
    )
  }
  # Drop obviously impossible far-future values (corrupt strings)
  d[!is.na(d) & d > today + 365L] <- NA
  d
}


# Rasterize one reprojected fire polygon against the domain grid,
# returning a tibble of burned pixels (burn_fraction > 0.5 only).
.rasterize_one_fire <- function(
    poly_vect,
    domain_r,
    pid_vec,
    burn_date_int,
    date_uncertainty_days,
    source_label = "capenature"
) {
  cover_r <- terra::rasterize(poly_vect, domain_r, cover = TRUE)
  cover_v <- terra::values(cover_r)[, 1]

  # pixels within domain AND covered by this polygon
  valid <- !is.na(pid_vec) & !is.na(cover_v) & cover_v > 0
  if (!any(valid)) return(NULL)

  tibble::tibble(
    pid                   = as.integer(pid_vec[valid]),
    date                  = burn_date_int,
    source                = source_label,
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
  today <- Sys.Date()
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

  # ── 4. Parse dates safely (ISO YYYY-MM-DD and CapeNature DD/MM/YYYY) ──────
  fires_sf <- fires_sf |>
    dplyr::mutate(
      date_start_parsed = .parse_flexible_date(.data$DATE_START, today = today),
      date_extin_parsed = .parse_flexible_date(.data$DATE_EXTIN, today = today)
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

  # One-cell buffer (in domain CRS units) used to ensure edge pixels are
  # captured when cropping to the fire bounding box.
  cell_buf <- max(terra::res(domain_r))

  result_list <- vector("list", nrow(fires_sf))
  for (i in seq_len(nrow(fires_sf))) {
    message(paste(i, "of", nrow(fires_sf))) #status update

    # Crop domain raster to this fire's bounding box + one-cell buffer so that
    # terra::rasterize() only has to work on a small spatial subset rather than
    # the full domain grid — the dominant cost in the original implementation.
    fire_ext    <- terra::ext(fires_vect[i, ])
    fire_ext    <- terra::extend(fire_ext, cell_buf)
    domain_crop <- terra::crop(domain_r, fire_ext)
    pid_crop    <- terra::values(domain_crop[["pid"]])[, 1]

    result_list[[i]] <- tryCatch(
      .rasterize_one_fire(
        poly_vect             = fires_vect[i, ],
        domain_r              = domain_crop,
        pid_vec               = pid_crop,
        burn_date_int         = as.integer(fires_sf$burn_date[i] - epoch),
        date_uncertainty_days = as.integer(fires_sf$date_uncertainty_days[i]),
        source_label          = "capenature"
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


# ── 1b. TMNP (Table Mountain NP) historical fire ingest ───────────────────────

#' @title Download TMNP fire shapefile sidecars from the manual-data release
#'
#' @description Pulls flat assets \code{tmnp_fire_1962_2021.{shp,shx,dbf,prj}}
#'   from the \code{manual-data} GitHub release (TMNP only — not full SANParks).
#'
#' @param dest_dir Local directory for shapefile sidecars.
#' @param repo GitHub owner/repo.
#' @param tag Release tag (default \code{manual-data}).
#' @param overwrite Re-download when files already exist?
#' @return Absolute path to the \code{.shp} file.
#' @export
download_tmnp_fire_shapefile <- function(
    dest_dir = "data/manual_download/tmnp_fire_1962_2021",
    repo = "eco-emma/emma_envdata",
    tag = "manual-data",
    overwrite = FALSE
) {
  stem <- "tmnp_fire_1962_2021"
  parts <- .shapefile_sidecar_names(stem)
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

  for (asset in parts$required) {
    download_release_asset_by_name(
      file = asset,
      dest_dir = dest_dir,
      repo = repo,
      tag = tag,
      overwrite = overwrite
    )
  }
  for (asset in parts$optional) {
    tryCatch(
      download_release_asset_by_name(
        file = asset,
        dest_dir = dest_dir,
        repo = repo,
        tag = tag,
        overwrite = overwrite
      ),
      error = function(e) {
        message("Optional sidecar skipped (", asset, "): ", conditionMessage(e))
      }
    )
  }

  normalizePath(
    file.path(dest_dir, paste0(stem, ".shp")),
    winslash = "/",
    mustWork = TRUE
  )
}


# Parse TMNP STARTDATE strings: YYYYMMDD, YYYYMM00 (month only), YYYY0000
# (year only). Returns a list of burn_date (Date) and date_uncertainty_days.
.parse_tmnp_startdate <- function(startdate, year, today = Sys.Date()) {
  s <- trimws(as.character(startdate))
  y <- suppressWarnings(as.integer(year))
  n <- length(s)
  burn_date <- rep(as.Date(NA), n)
  unc <- rep(NA_integer_, n)

  for (i in seq_len(n)) {
    si <- s[i]
    yi <- y[i]
    if (is.na(si) || !nzchar(si) || identical(si, "0")) {
      if (!is.na(yi) && yi >= 1900L && yi <= as.integer(format(today, "%Y"))) {
        burn_date[i] <- as.Date(paste0(yi, "-07-01"))
        unc[i] <- 180L
      }
      next
    }
    if (!grepl("^[0-9]{8}$", si)) next
    yy <- as.integer(substr(si, 1L, 4L))
    mm <- as.integer(substr(si, 5L, 6L))
    dd <- as.integer(substr(si, 7L, 8L))
    if (is.na(yy) || yy < 1900L) next

    if (!is.na(mm) && mm > 0L && !is.na(dd) && dd > 0L) {
      d <- suppressWarnings(as.Date(sprintf("%04d-%02d-%02d", yy, mm, dd)))
      if (!is.na(d) && d < today) {
        burn_date[i] <- d
        unc[i] <- 0L
      }
    } else if (!is.na(mm) && mm > 0L) {
      # Month known, day unknown → mid-month
      d <- suppressWarnings(
        as.Date(sprintf("%04d-%02d-15", yy, mm))
      )
      if (!is.na(d) && d < today) {
        burn_date[i] <- d
        unc[i] <- 15L
      }
    } else {
      # Year only
      d <- as.Date(paste0(yy, "-07-01"))
      if (d < today) {
        burn_date[i] <- d
        unc[i] <- 180L
      }
    }
  }

  list(burn_date = burn_date, date_uncertainty_days = unc)
}


#' @title Rasterize TMNP fire polygons to burned-pixel parquet
#'
#' @description Table Mountain National Park historical fires only
#'   (\code{tmnp_fire_1962_2021} from \code{manual-data}). Other national parks
#'   are unchanged (MODIS/VIIRS + censor). Output schema matches CapeNature
#'   burn events with \code{source = "tmnp"}.
#'
#' @param tmnp_fires sf object from the TMNP fire shapefile (or path to \code{.shp}).
#' @param domain_raster SpatRaster (or path) carrying a \code{pid} layer.
#' @param out_file Output parquet path.
#' @param verbose Logical. Print progress messages?
#'
#' @return Character path to the written parquet file.
#' @export
process_tmnp_to_parquet <- function(
    tmnp_fires,
    domain_raster,
    out_file = "data/target_outputs/burndates/tmnp_burns.parquet",
    verbose = TRUE
) {
  today <- Sys.Date()
  epoch <- as.Date("1970-01-01")

  if (is.character(tmnp_fires)) {
    tmnp_fires <- sf::st_read(tmnp_fires, quiet = !verbose)
  }

  required_fields <- c("STARTDATE", "YEAR")
  missing_fields <- setdiff(required_fields, names(tmnp_fires))
  if (length(missing_fields) > 0L) {
    stop(
      "TMNP shapefile missing expected fields: ",
      paste(missing_fields, collapse = ", ")
    )
  }

  fires_sf <- tmnp_fires |>
    dplyr::mutate(
      STARTDATE = as.character(.data$STARTDATE),
      YEAR = as.integer(.data$YEAR),
      ID = if ("ID" %in% names(tmnp_fires)) {
        as.character(.data$ID)
      } else {
        as.character(dplyr::row_number())
      },
      .row_id = dplyr::row_number()
    )

  if (verbose) message("TMNP: ", nrow(fires_sf), " raw polygons")

  parsed <- .parse_tmnp_startdate(
    fires_sf$STARTDATE,
    fires_sf$YEAR,
    today = today
  )
  fires_sf$burn_date <- parsed$burn_date
  fires_sf$date_uncertainty_days <- parsed$date_uncertainty_days

  fires_sf <- dplyr::filter(
    fires_sf,
    !is.na(.data$burn_date),
    .data$burn_date < today
  )

  if (verbose) {
    message(
      "TMNP: ", nrow(fires_sf),
      " polygons after date cleaning (of ", nrow(tmnp_fires), " raw)"
    )
  }

  if (nrow(fires_sf) == 0L) {
    if (verbose) message("No valid TMNP records — writing empty parquet")
    empty <- tibble::tibble(
      pid = integer(0),
      date = integer(0),
      source = character(0),
      date_uncertainty_days = integer(0),
      burn_fraction = double(0)
    )
    dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(empty, out_file)
    return(out_file)
  }

  domain_r <- if (is.character(domain_raster)) {
    terra::rast(domain_raster)
  } else {
    domain_raster
  }
  stopifnot("pid" %in% names(domain_r))

  fires_vect <- terra::project(
    terra::vect(fires_sf),
    terra::crs(domain_r)
  )
  cell_buf <- max(terra::res(domain_r))

  if (verbose) {
    message(
      "Rasterizing ", nrow(fires_sf),
      " TMNP polygons with fractional cover ..."
    )
  }

  result_list <- vector("list", nrow(fires_sf))
  for (i in seq_len(nrow(fires_sf))) {
    if (verbose && (i == 1L || i %% 50L == 0L || i == nrow(fires_sf))) {
      message(paste(i, "of", nrow(fires_sf)))
    }

    fire_ext <- terra::ext(fires_vect[i, ])
    fire_ext <- terra::extend(fire_ext, cell_buf)
    domain_crop <- tryCatch(
      terra::crop(domain_r, fire_ext),
      error = function(e) NULL
    )
    if (is.null(domain_crop)) {
      result_list[[i]] <- NULL
      next
    }
    pid_crop <- terra::values(domain_crop[["pid"]])[, 1]

    result_list[[i]] <- tryCatch(
      .rasterize_one_fire(
        poly_vect = fires_vect[i, ],
        domain_r = domain_crop,
        pid_vec = pid_crop,
        burn_date_int = as.integer(fires_sf$burn_date[i] - epoch),
        date_uncertainty_days = as.integer(fires_sf$date_uncertainty_days[i]),
        source_label = "tmnp"
      ),
      error = function(e) {
        warning(
          "Skipping TMNP polygon ", i,
          " (ID=", fires_sf$ID[i], "): ", conditionMessage(e)
        )
        NULL
      }
    )
  }

  burn_events <- dplyr::bind_rows(result_list)

  if (verbose) {
    if (nrow(burn_events) == 0L) {
      message("No TMNP pixels burned within domain after rasterization")
    } else {
      message(
        "TMNP rasterized: ", nrow(burn_events),
        " burned pixel × fire-event rows (",
        length(unique(burn_events$pid)), " unique pixels)"
      )
    }
  }

  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  unlink(out_file)
  arrow::write_parquet(
    burn_events,
    sink = out_file,
    compression = "gzip"
  )
  if (verbose) message("Wrote TMNP burn events: ", basename(out_file))
  out_file
}


# ── 2. Merge burn sources ─────────────────────────────────────────────────────

#' @title Merge MODIS, VIIRS, CapeNature, and TMNP burn events
#'
#' @description Reads all monthly parquet files from the burn directory plus the
#'   CapeNature and TMNP parquets, unifies them to a common schema, then applies
#'   a greedy 6-month per-pixel clustering to collapse multi-sensor detections
#'   of the same fire into one canonical event. Source priority:
#'   CapeNature > TMNP > VIIRS > MODIS.
#'
#'   The returned tibble has one row per pixel × distinct fire:
#'   \describe{
#'     \item{pid}{int32}
#'     \item{date}{int32 — canonical date, days since 1970-01-01}
#'     \item{fire_source}{chr — "capenature" | "tmnp" | "viirs" | "modis"}
#'     \item{date_uncertainty_days}{int16 — base uncertainty + cluster spread}
#'     \item{burn_fraction}{float32 — polygon fractional cover; NA for satellite}
#'   }
#'
#' @param burn_dir           Directory containing \code{burn_modis_*.parquet}
#'   and \code{burn_viirs_*.parquet} files.
#' @param capenature_parquet Path to the CapeNature burned-pixel parquet
#'   (from \code{process_capenature_to_parquet()}). NULL to skip.
#' @param tmnp_parquet       Path to the TMNP burned-pixel parquet
#'   (from \code{process_tmnp_to_parquet()}). NULL to skip.
#' @param verbose            Logical. Print progress messages?
#'
#' @return Tibble of deduplicated fire events.
#' @export
merge_burn_dates <- function(
    burn_dir = "data/target_outputs/burndates/",
    capenature_parquet = NULL,
    tmnp_parquet = NULL,
    verbose = TRUE
) {
  # Helper: read parquets matching pattern, add source column, standardise schema
  .read_burn_parquets <- function(pattern, source_label) {
    paths <- list.files(burn_dir, pattern = pattern, full.names = TRUE)
    if (length(paths) == 0L) {
      if (verbose) {
        message("No parquets in ", burn_dir, " matching ", pattern)
      }
      return(tibble::tibble(
        pid = integer(0),
        date = integer(0),
        source = character(0),
        date_uncertainty_days = integer(0),
        burn_fraction = double(0)
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
        source = source_label,
        date_uncertainty_days = 8L, # half of 16-day compositing window
        burn_fraction = NA_real_
      ) |>
      dplyr::select(
        "pid", "date", "source", "date_uncertainty_days", "burn_fraction"
      )
  }

  .read_ground_parquet <- function(path, label) {
    if (!is.null(path) && file.exists(path)) {
      if (verbose) message("Reading ", label, " parquet: ", basename(path))
      arrow::read_parquet(path) |>
        dplyr::select(
          "pid", "date", "source", "date_uncertainty_days", "burn_fraction"
        )
    } else {
      tibble::tibble(
        pid = integer(0),
        date = integer(0),
        source = character(0),
        date_uncertainty_days = integer(0),
        burn_fraction = double(0)
      )
    }
  }

  modis_burns <- .read_burn_parquets("^burn_modis_.*\\.parquet$", "modis")
  viirs_burns <- .read_burn_parquets("^burn_viirs_.*\\.parquet$", "viirs")
  cn_burns <- .read_ground_parquet(capenature_parquet, "CapeNature")
  tmnp_burns <- .read_ground_parquet(tmnp_parquet, "TMNP")

  all_burns <- dplyr::bind_rows(modis_burns, viirs_burns, cn_burns, tmnp_burns)

  if (nrow(all_burns) == 0L) {
    if (verbose) message("No burn events found — returning empty table")
    return(tibble::tibble(
      pid = integer(0),
      date = integer(0),
      fire_source = character(0),
      date_uncertainty_days = integer(0),
      burn_fraction = double(0)
    ))
  }

  if (verbose) {
    message(
      "Combining ", nrow(modis_burns), " MODIS + ",
      nrow(viirs_burns), " VIIRS + ",
      nrow(cn_burns), " CapeNature + ",
      nrow(tmnp_burns), " TMNP raw detections"
    )
  }

  # ── Greedy 6-month per-pixel cluster deduplication ─────────────────────────
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
      tmnp_rows <- dplyr::filter(d, .data$source == "tmnp")

      if (nrow(cn_rows) > 0L) {
        # CapeNature ground truth wins over TMNP and satellites
        canon_date <- cn_rows$date[1L]
        canon_source <- "capenature"
        canon_unc <- as.integer(cn_rows$date_uncertainty_days[1L])
        canon_frac <- as.numeric(cn_rows$burn_fraction[1L])
      } else if (nrow(tmnp_rows) > 0L) {
        # TMNP ground truth (Table Mountain NP only)
        canon_date <- tmnp_rows$date[1L]
        canon_source <- "tmnp"
        canon_unc <- as.integer(tmnp_rows$date_uncertainty_days[1L])
        canon_frac <- as.numeric(tmnp_rows$burn_fraction[1L])
      } else {
        # Satellites: earliest detection; VIIRS preferred over MODIS for ties
        sat <- dplyr::arrange(
          d,
          .data$date,
          dplyr::desc(.data$source == "viirs")
        )
        canon_date <- sat$date[1L]
        canon_source <- sat$source[1L]
        spread <- as.integer(max(d$date) - min(d$date))
        canon_unc <- 8L + spread
        canon_frac <- NA_real_
      }

      tibble::tibble(
        date = as.integer(canon_date),
        fire_source = as.character(canon_source),
        date_uncertainty_days = as.integer(canon_unc),
        burn_fraction = as.numeric(canon_frac)
      )
    }) |>
    dplyr::ungroup() |>
    dplyr::select(
      "pid", "date", "fire_source", "date_uncertainty_days", "burn_fraction"
    ) |>
    dplyr::arrange(.data$pid, .data$date)

  if (verbose) {
    message(
      "Merged burn record: ", nrow(deduplicated), " unique pixel × fire events ",
      "(CapeNature: ",
      sum(deduplicated$fire_source == "capenature", na.rm = TRUE),
      ", TMNP: ",
      sum(deduplicated$fire_source == "tmnp", na.rm = TRUE),
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

  # ── Find months to process ─────────────────────────────────────────────────
  # Convert burn event dates to month-start integers
  burn_event_dates <- as.Date(burn_events$date, origin = "1970-01-01")
  burn_month_starts <- as.integer(
    as.Date(format(burn_event_dates, "%Y-%m-01")) - as.Date("1970-01-01")
  )

  all_month_starts <- sort(unique(burn_month_starts))
  
  # Check if burn_events contains sources not present in current state
  # (e.g., CapeNature added retrospectively after satellite-only state exists)
  sources_in_events <- unique(burn_events$fire_source)
  sources_in_state  <- if (nrow(state) > 0L) {
    unique(state$fire_source[!is.na(state$fire_source)])
  } else {
    character(0)
  }
  new_sources <- setdiff(sources_in_events, sources_in_state)
  
  if (length(new_sources) > 0L) {
    if (verbose) {
      message(
        "New fire source(s) detected: ", paste(new_sources, collapse = ", "),
        " — rebuilding state from scratch to incorporate historical events"
      )
    }
    # Reset state to empty so all months get reprocessed
    state <- tibble::tibble(
      pid                   = integer(0),
      state_month           = integer(0),
      last_burn_date        = integer(0),
      fire_count            = integer(0),
      fire_source           = character(0),
      date_uncertainty_days = integer(0),
      burn_fraction         = double(0)
    )
    months_to_process <- all_month_starts
  } else {
    # No new sources — incremental update (only months > last_state_month)
    months_to_process <- all_month_starts[all_month_starts > last_state_month]
  }

  if (length(months_to_process) == 0L) {
    if (verbose) message("State is up-to-date — no new months to process")
    dir.create(dirname(state_file), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(state, state_file)
    return(state_file)
  }

  if (verbose) {
    message(
      "Processing ", length(months_to_process), " month(s) into fire state ..."
    )
  }

  # ── Stateful for loop: chronological carry-forward ─────────────────────────
  # A for loop is appropriate here — this is explicitly stateful carry-forward
  # (R style guide exception to the prefer-purrr::map rule).
  for (month_start in months_to_process) {
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
#'     \item{last_burn_date}{int32 — most recent fire before this VI date
#'       (\code{NA} = never burned / unknown)}
#'     \item{fire_age_days}{int32 — date − last_burn_date when known;
#'       \code{NA} when \code{is_censored} (do not invent an age)}
#'     \item{fire_source}{chr — "capenature" | "tmnp" | "viirs" | "modis" | NA}
#'     \item{date_uncertainty_days}{int16}
#'     \item{fire_count}{int32 — total fires observed; 0 = never burned}
#'     \item{burn_fraction}{float32 — polygon fractional cover; NA if satellite}
#'     \item{is_censored}{logical — TRUE when never burned / no known burn
#'       before this VI date (report must label separately; do not map to age 20)}
#'     \item{censor_age_days}{int32 — lower-bound age \code{vi_date − 2000-01-01}
#'       when censored; \code{NA} when a true burn age is known (model use)}
#'   }
#'
#'   Never-burned / right-censored pixels: \code{last_burn_date = NA},
#'   \code{fire_age_days = NA}, \code{is_censored = TRUE}, and
#'   \code{censor_age_days = vi_date − 2000-01-01} (optional lower bound for
#'   survival models). Report UIs must not collapse censored → age 20.
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
compute_fireage_for_vi <- function(
    modis_vi_dir = "data/target_outputs/modis_vi",
    viirs_vi_dir = "data/target_outputs/viirs_vi",
    state_file,
    out_dir      = "data/target_outputs/fireage/",
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

  # Derive output parquet names: vi_modis_* → fireage_modis_*, etc.
  out_names <- file.path(out_dir, sub("^vi_", "fireage_", basename(all_vi_files)))

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
    if (is.null(vi_df)) {
      # Write .skip marker — consistent with upstream pipeline convention.
      # Handles legacy YYYYMM-named parquets (old pipeline schema) or other
      # unreadable files; prevents targets from erroring on missing output paths.
      skip_file <- paste0(out_file, ".skip")
      writeLines(c(paste("VI file:", basename(vi_file)),
                   "Reason: Could not read parquet (wrong format or schema)",
                   paste("Timestamp:", Sys.time())),
                 skip_file)
      todo_out[j] <- skip_file
      next
    }

    # Require pid, date, sensor columns
    req_cols <- c("pid", "date", "sensor")
    missing_cols <- setdiff(req_cols, names(vi_df))
    if (length(missing_cols) > 0L) {
      warning(
        basename(vi_file), " missing columns: ",
        paste(missing_cols, collapse = ", "), " — skipping"
      )
      # Write .skip marker so targets does not error on missing output files.
      # Likely cause: legacy VI parquet from an older pipeline schema (YYYYMM
      # filenames) that lacks the pid/date/sensor columns expected by this function.
      skip_file <- paste0(out_file, ".skip")
      writeLines(c(paste("VI file:", basename(vi_file)),
                   paste("Reason: Missing required columns:",
                         paste(missing_cols, collapse = ", ")),
                   paste("Available columns:", paste(names(vi_df), collapse = ", ")),
                   paste("Timestamp:", Sys.time())),
                 skip_file)
      todo_out[j] <- skip_file
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
        is_censored = is.na(.data$last_burn_date_valid),
        # True age only when a burn is known; NA when censored (W3.3 / W0.4)
        fire_age_days = dplyr::if_else(
          .data$is_censored,
          NA_integer_,
          as.integer(.data$date - .data$last_burn_date_valid)
        ),
        # Lower-bound age for models that need right-censoring semantics
        censor_age_days = dplyr::if_else(
          .data$is_censored,
          as.integer(.data$date - record_start),
          NA_integer_
        ),
        fire_source = dplyr::if_else(
          !.data$is_censored,
          .data$fire_source,
          NA_character_
        ),
        date_uncertainty_days = dplyr::if_else(
          !.data$is_censored,
          as.integer(.data$date_uncertainty_days),
          NA_integer_
        ),
        fire_count = dplyr::coalesce(as.integer(.data$fire_count), 0L),
        last_burn_date = .data$last_burn_date_valid
      ) |>
      dplyr::select(
        "pid", "date", "sensor",
        "last_burn_date", "fire_age_days", "fire_source",
        "date_uncertainty_days", "fire_count", "burn_fraction",
        "is_censored", "censor_age_days"
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

  # Merge updated todo paths (possibly .skip) back into the full output vector
  # so every returned path points to a file that actually exists on disk.
  out_names[todo] <- todo_out
  out_names
}


# ── 5. Snapshot raster ────────────────────────────────────────────────────────

#' @title Rasterize the most-recent-burn state parquet to a domain-aligned raster
#'
#' @description Reads \code{most_recent_burn_state.parquet} (written by
#'   \code{compute_fire_state()}) and returns a three-band SpatRaster snapshot
#'   at \code{state_month} for storage by \code{geotargets::tar_terra_rast()}:
#'   \describe{
#'     \item{fire_age_days}{Band 1: days since last fire; \code{NA} if never
#'       burned (censored — do not invent age 20)}
#'     \item{last_burn_date}{Band 2: days since 1970-01-01 of most recent burn;
#'       \code{NA} if never burned}
#'     \item{is_censored}{Band 3: 1 = never burned / unknown; 0 = known burn}
#'   }
#'   Never-burned pixels keep \code{fire_age_days = NA} and
#'   \code{is_censored = 1} so report UIs can label them without collapsing to
#'   a fake age. The MODIS-era lower bound
#'   (\code{state_month − 2000-01-01}) is available in fireage parquets as
#'   \code{censor_age_days}, not as a filled raster age.
#'
#' @param state_file   Character path to \code{most_recent_burn_state.parquet}.
#' @param domain_raster SpatRaster or path with a \code{pid} layer.
#' @param verbose      Logical. Print progress messages?
#'
#' @return Three-band SpatRaster (fire_age_days, last_burn_date, is_censored).
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

  # For empty state, return all-NA / all-censored raster
  if (nrow(state) == 0L) {
    if (verbose) message("State is empty — returning all-NA / censored raster")
    empty <- domain_r[[1L]]
    terra::values(empty) <- NA_integer_
    censored <- domain_r[[1L]]
    pid_vec <- terra::values(domain_r[["pid"]])[, 1]
    terra::values(censored) <- as.integer(!is.na(pid_vec))
    r_out <- c(empty, empty, censored)
    names(r_out) <- c("fire_age_days", "last_burn_date", "is_censored")
    terra::metags(r_out) <- c(
      snapshot_date = as.character(Sys.Date()),
      source = "most_recent_burn_state"
    )
    return(r_out)
  }

  record_start <- as.integer(as.Date("2000-01-01") - as.Date("1970-01-01"))
  snapshot_int <- max(state$state_month, record_start)
  snapshot_date <- as.Date(snapshot_int, origin = "1970-01-01")

  if (verbose) {
    message(
      "Rasterizing most_recent_burn snapshot for ",
      format(snapshot_date), " (", nrow(state), " pixels in state)"
    )
  }

  pid_vec <- terra::values(domain_r[["pid"]])[, 1]

  # Known burns only — never-burned stay NA (W3.3); flag via is_censored
  state_snap <- state |>
    dplyr::mutate(
      is_censored = as.integer(is.na(.data$last_burn_date)),
      fire_age_days = dplyr::if_else(
        !is.na(.data$last_burn_date),
        as.integer(snapshot_int - .data$last_burn_date),
        NA_integer_
      )
    )

  fire_age_map <- setNames(
    state_snap$fire_age_days, as.character(state_snap$pid)
  )
  last_burn_map <- setNames(
    state_snap$last_burn_date, as.character(state_snap$pid)
  )
  censored_map <- setNames(
    state_snap$is_censored, as.character(state_snap$pid)
  )

  fire_age_vec <- as.integer(fire_age_map[as.character(pid_vec)])
  last_burn_vec <- as.integer(last_burn_map[as.character(pid_vec)])
  censored_vec <- as.integer(censored_map[as.character(pid_vec)])

  # Domain pixels with a valid pid but absent from state = never burned
  unburned_valid <- !is.na(pid_vec) & is.na(censored_vec)
  censored_vec[unburned_valid] <- 1L
  # Known burns already have is_censored = 0; leave fire_age NA where censored
  censored_vec[is.na(censored_vec)] <- NA_integer_

  fire_age_r <- domain_r[[1L]]
  last_burn_r <- domain_r[[1L]]
  censored_r <- domain_r[[1L]]
  terra::values(fire_age_r) <- fire_age_vec
  terra::values(last_burn_r) <- last_burn_vec
  terra::values(censored_r) <- censored_vec
  names(fire_age_r) <- "fire_age_days"
  names(last_burn_r) <- "last_burn_date"
  names(censored_r) <- "is_censored"

  r_out <- c(fire_age_r, last_burn_r, censored_r)
  terra::metags(r_out) <- c(
    snapshot_date = as.character(snapshot_date),
    source = "most_recent_burn_state"
  )

  if (verbose) {
    message(
      "Built most_recent_burn raster for ", format(snapshot_date),
      " (is_censored band: never-burned = 1, known burn = 0)"
    )
  }
  r_out
}
