#' @title AppEEARS VI GeoTIFF date matching + COG DOY guards
#' @description Prevents Jul–Aug template reuse when
#'   \code{list.files(..., recursive = TRUE)} mixes composites in one temp
#'   tree. Source TIFs must carry an AppEEARS \code{YYYYMMDD} in the basename
#'   that falls in the branch composite window; written COGs must have DOY
#'   values in that window (year wrap for Dec→Jan).
#' @name vi_geotiff_date_match
NULL

#' Slack (days) added before composite start / after composite end for DOY checks.
#' @keywords internal
.vi_cog_doy_margin_days <- 7L

#' Minimum fraction of non-NA DOY pixels that must fall in the composite window.
#' @keywords internal
.vi_cog_doy_min_frac <- 0.5

#' @title Parse AppEEARS layer timestamp (YYYYMMDD) from a raw TIF basename
#' @description AppEEARS names look like
#'   \code{MOD13A1.061__500m_16_days_EVI_20000727T000000_aid0001.tif}.
#'   Prefer the \code{YYYYMMDD} immediately before \code{T}; fall back to the
#'   first 8-digit 20YYMMDD token.
#' @param file_name Character path or basename (vectorized)
#' @return Date vector (NA when no match)
#' @export
parse_appeears_tif_date <- function(file_name) {
  file_name <- basename(as.character(file_name))
  n <- length(file_name)
  out <- rep(as.Date(NA), n)
  if (!n) {
    return(out)
  }
  # Primary: …_YYYYMMDDTHHMMSS_…
  m <- regexpr("20[0-9]{6}T", file_name, perl = TRUE)
  ok <- !is.na(m) & m > 0L
  if (any(ok)) {
    extracted <- substring(file_name[ok], m[ok], m[ok] + 7L)
    out[ok] <- as.Date(extracted, format = "%Y%m%d")
  }
  # Fallback: first 20YYMMDD when no T-suffix (rare)
  need <- is.na(out)
  if (any(need)) {
    m2 <- regexpr("20[0-9]{6}", file_name[need], perl = TRUE)
    ok2 <- !is.na(m2) & m2 > 0L
    if (any(ok2)) {
      idx <- which(need)[ok2]
      extracted2 <- substring(file_name[idx], m2[ok2], m2[ok2] + 7L)
      out[idx] <- as.Date(extracted2, format = "%Y%m%d")
    }
  }
  out
}

#' @title Composite end date (start + 15) when not supplied
#' @keywords internal
.vi_composite_end <- function(composite_date, composite_end = NULL) {
  composite_date <- as.Date(composite_date)[[1L]]
  if (is.null(composite_end) || length(composite_end) < 1L || is.na(composite_end[[1L]])) {
    return(composite_date + 15L)
  }
  as.Date(composite_end)[[1L]]
}

#' @title Is a date inside the composite window (± margin)?
#' @export
appeears_date_in_composite_window <- function(file_date,
                                              composite_date,
                                              composite_end = NULL,
                                              margin_days = 0L) {
  file_date <- as.Date(file_date)
  composite_date <- as.Date(composite_date)[[1L]]
  composite_end <- .vi_composite_end(composite_date, composite_end)
  margin_days <- as.integer(margin_days)[[1L]]
  lo <- composite_date - margin_days
  hi <- composite_end + margin_days
  !is.na(file_date) & file_date >= lo & file_date <= hi
}

#' @title Attach AppEEARS dates and drop layers outside the composite window
#' @param tif_info List of lists with at least \code{path}, \code{product}, \code{layer}
#' @return Filtered list (may be empty); each element gains \code{file_date}
#' @export
filter_appeears_tif_info_for_composite <- function(tif_info,
                                                   composite_date,
                                                   composite_end = NULL,
                                                   margin_days = 0L,
                                                   verbose = TRUE) {
  if (!length(tif_info)) {
    return(list())
  }
  composite_date <- as.Date(composite_date)[[1L]]
  composite_end <- .vi_composite_end(composite_date, composite_end)

  enriched <- lapply(tif_info, function(x) {
    x$file_date <- parse_appeears_tif_date(x$path)[[1L]]
    x
  })
  keep <- vapply(enriched, function(x) {
    isTRUE(
      appeears_date_in_composite_window(
        x$file_date,
        composite_date,
        composite_end,
        margin_days = margin_days
      )
    )
  }, logical(1))

  n_drop <- sum(!keep)
  if (isTRUE(verbose) && n_drop > 0L) {
    message(
      "AppEEARS date filter: dropped ", n_drop, "/", length(enriched),
      " TIF(s) outside ", format(composite_date), "–", format(composite_end),
      " (prevents mixed-pile [[1]] template reuse)"
    )
  }
  enriched[keep]
}

#' @title Pick one layer entry for a sensor (prefer exact composite_date)
#' @param tif_info Filtered list from [filter_appeears_tif_info_for_composite()]
#' @return One list element, or NULL
#' @export
pick_appeears_tif_layer <- function(tif_info,
                                    product,
                                    layer,
                                    composite_date = NULL) {
  hits <- Filter(
    function(x) identical(x$product, product) && identical(x$layer, layer),
    tif_info
  )
  if (!length(hits)) {
    return(NULL)
  }
  if (!is.null(composite_date) && !is.na(as.Date(composite_date)[[1L]])) {
    cd <- as.Date(composite_date)[[1L]]
    exact <- Filter(function(x) identical(x$file_date, cd), hits)
    if (length(exact)) {
      return(exact[[1L]])
    }
  }
  hits[[1L]]
}

#' Convert DOY values to Date using composite year (+ Dec→Jan wrap).
#' @keywords internal
.vi_doy_to_dates <- function(doy, composite_date) {
  composite_date <- as.Date(composite_date)[[1L]]
  doy <- as.integer(doy)
  n <- length(doy)
  out <- rep(as.Date(NA), n)
  ok <- !is.na(doy) & doy >= 1L & doy <= 366L
  if (!any(ok)) {
    return(out)
  }
  y <- as.integer(format(composite_date, "%Y"))
  out[ok] <- as.Date(doy[ok] - 1L, origin = paste0(y, "-01-01"))
  # Year wrap for Dec composites storing Jan DOYs
  file_doy <- as.integer(format(composite_date, "%j"))
  wrap <- ok & (doy - file_doy < -300L)
  if (any(wrap)) {
    out[wrap] <- as.Date(doy[wrap] - 1L, origin = paste0(y + 1L, "-01-01"))
  }
  out
}

#' @title Does a VI sensor COG's DOY band match the composite window?
#' @description All-NA DOY (placeholder) → TRUE. Otherwise requires
#'   \code{min_frac} of non-NA DOYs inside
#'   \code{[composite_date - margin, composite_end + margin]}.
#' @export
vi_cog_doy_matches_composite <- function(cog_path,
                                         composite_date = NULL,
                                         composite_end = NULL,
                                         margin_days = .vi_cog_doy_margin_days,
                                         min_frac = .vi_cog_doy_min_frac) {
  cog_path <- as.character(cog_path)[[1L]]
  if (!nzchar(cog_path) || !file.exists(cog_path)) {
    return(FALSE)
  }
  if (is.null(composite_date) || is.na(as.Date(composite_date)[[1L]])) {
    # Infer from basename vi_*_*_YYYYMMDD.tif
    bn <- basename(cog_path)
    m <- regexpr("20[0-9]{6}(?=\\.tif$)", bn, perl = TRUE)
    if (is.na(m) || m < 1L) {
      return(FALSE)
    }
    composite_date <- as.Date(substring(bn, m, m + 7L), format = "%Y%m%d")
  }
  composite_date <- as.Date(composite_date)[[1L]]
  composite_end <- .vi_composite_end(composite_date, composite_end)

  r <- tryCatch(terra::rast(cog_path), error = function(e) NULL)
  if (is.null(r) || !("doy" %in% names(r))) {
    return(FALSE)
  }
  doy_v <- terra::values(r[["doy"]])[, 1]
  ok <- !is.na(doy_v)
  if (!any(ok)) {
    return(TRUE) # placeholder / no observations
  }
  dates <- .vi_doy_to_dates(doy_v[ok], composite_date)
  lo <- composite_date - as.integer(margin_days)
  hi <- composite_end + as.integer(margin_days)
  frac <- mean(dates >= lo & dates <= hi, na.rm = TRUE)
  isTRUE(frac >= as.numeric(min_frac))
}

#' Assert projected DOY values match the composite window (before write).
#' @param doy_rast SpatRaster DOY layer (or NULL)
#' @keywords internal
assert_vi_doy_in_composite_window <- function(doy_rast,
                                              composite_date,
                                              composite_end = NULL,
                                              sensor_label = "",
                                              margin_days = .vi_cog_doy_margin_days,
                                              min_frac = .vi_cog_doy_min_frac) {
  if (is.null(doy_rast)) {
    return(invisible(TRUE))
  }
  composite_date <- as.Date(composite_date)[[1L]]
  composite_end <- .vi_composite_end(composite_date, composite_end)
  doy_v <- terra::values(doy_rast)[, 1]
  ok <- !is.na(doy_v)
  if (!any(ok)) {
    return(invisible(TRUE))
  }
  dates <- .vi_doy_to_dates(doy_v[ok], composite_date)
  lo <- composite_date - as.integer(margin_days)
  hi <- composite_end + as.integer(margin_days)
  frac <- mean(dates >= lo & dates <= hi, na.rm = TRUE)
  if (isTRUE(frac >= as.numeric(min_frac))) {
    return(invisible(TRUE))
  }
  stop(
    "VI COG DOY outside composite window for ", sensor_label,
    " (", format(composite_date), "–", format(composite_end),
    " ±", margin_days, "d): frac_in_window=",
    sprintf("%.3f", frac),
    " (min ", min_frac, "). Refusing to write (Jul–Aug template guard).",
    call. = FALSE
  )
}

#' @title Filter VI sensor COGs before GitHub release upload
#' @description Drops \code{vi_modis_{terra|aqua}_YYYYMMDD.tif} /
#'   \code{vi_viirs_{snpp|noaa20}_YYYYMMDD.tif} whose DOY band does not match
#'   the basename composite. Set \code{EMMA_VI_GRID_STRICT=1} to stop.
#' @export
filter_vi_grid_cogs_for_upload <- function(files,
                                           strict = NA,
                                           verbose = TRUE) {
  files <- as.character(files)
  files <- files[!is.na(files) & nzchar(files)]
  if (!length(files)) {
    return(character(0))
  }

  is_grid <- grepl(
    "^vi_(modis_(terra|aqua)|viirs_(snpp|noaa20))_[0-9]{8}\\.tif$",
    basename(files)
  )
  other <- files[!is_grid]
  grid_files <- files[is_grid]
  if (!length(grid_files)) {
    return(files)
  }

  if (is.na(strict)) {
    strict <- identical(Sys.getenv("EMMA_VI_GRID_STRICT", unset = ""), "1")
  }

  keep <- logical(length(grid_files))
  bad_names <- character(0)
  for (i in seq_along(grid_files)) {
    ok <- vi_cog_doy_matches_composite(grid_files[[i]])
    keep[[i]] <- isTRUE(ok)
    if (!ok) {
      bad_names <- c(bad_names, basename(grid_files[[i]]))
    }
  }

  if (length(bad_names) > 0L) {
    msg <- paste0(
      length(bad_names), " VI grid COG(s) fail DOY/filename alignment: ",
      paste(utils::head(bad_names, 15L), collapse = ", "),
      if (length(bad_names) > 15L) " ..." else ""
    )
    if (isTRUE(strict)) {
      stop(msg, ". Refusing upload (EMMA_VI_GRID_STRICT=1).", call. = FALSE)
    }
    if (verbose) {
      warning(msg, " — skipping upload of those files.", call. = FALSE)
    }
  } else if (verbose) {
    message("VI grid DOY guard: ", length(grid_files), " file(s) OK")
  }

  c(other, grid_files[keep])
}
