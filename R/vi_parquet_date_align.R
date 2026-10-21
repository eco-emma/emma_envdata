#' @title VI parquet filename vs content-date alignment
#' @description Shared helpers for auditing and gating
#'   \code{vi_modis_YYYYMMDD.parquet} / \code{vi_viirs_YYYYMMDD.parquet}
#'   assets. Filename YYYYMMDD is the 16-day composite start; row
#'   \code{date} is DOY converted with the filename year (see
#'   \code{vi_modis_geotiff_to_parquet}). Misaligned historical assets reuse a
#'   Jul–Aug template with rewritten years and identical EVI values — report
#'   climatologies must skip them until CCR regenerates the release.
#' @name vi_parquet_date_align
NULL

#' Default: majority of rows share the filename calendar month.
#' @keywords internal
.vi_parquet_min_frac_month <- 0.5

#' Default: most rows fall in a slack window around the composite
#' (\code{[start - 7, start + 22]} days) — covers month-boundary composites.
#' @keywords internal
.vi_parquet_min_frac_window <- 0.8

#' Shift filename-year Jan DOYs to next year when they wrap a Dec composite.
#' @param dates Date vector (stored epoch dates)
#' @param file_date Composite start Date from the basename
#' @return Date vector for alignment comparisons only
#' @keywords internal
.vi_parquet_dates_for_align <- function(dates, file_date) {
  if (!length(dates) || is.na(file_date)) {
    return(dates)
  }
  file_doy <- as.integer(format(file_date, "%j"))
  row_doy <- as.integer(format(dates, "%j"))
  # Pixel DOY far behind the composite DOY ⇒ observation is in the next year
  # (threshold matches MODIS::reformatDOY / phenofit year-wrap convention).
  wrap <- !is.na(row_doy) & (row_doy - file_doy < -300L)
  if (!any(wrap)) {
    return(dates)
  }
  out <- dates
  y_next <- as.integer(format(file_date, "%Y")) + 1L
  out[wrap] <- as.Date(
    paste(y_next, format(dates[wrap], "%m-%d"), sep = "-"),
    format = "%Y-%m-%d"
  )
  out
}

#' @title Parse composite start date from a VI parquet basename
#' @param path File path or basename
#' @return Date, or NA if the name does not match
#'   \code{vi_(modis|viirs)_YYYYMMDD.parquet}
#' @export
parse_vi_parquet_file_date <- function(path) {
  bn <- basename(path)
  m <- regexec("^vi_(modis|viirs)_([0-9]{8})\\.parquet$", bn, perl = TRUE)
  hit <- regmatches(bn, m)[[1]]
  if (length(hit) < 3L) {
    return(as.Date(NA))
  }
  as.Date(hit[[3]], format = "%Y%m%d")
}

#' @title Sensor stem from a VI parquet basename
#' @param path File path or basename
#' @return \code{"modis"}, \code{"viirs"}, or \code{NA_character_}
#' @export
parse_vi_parquet_sensor <- function(path) {
  bn <- basename(path)
  m <- regexec("^vi_(modis|viirs)_([0-9]{8})\\.parquet$", bn, perl = TRUE)
  hit <- regmatches(bn, m)[[1]]
  if (length(hit) < 2L) {
    return(NA_character_)
  }
  hit[[2]]
}

#' @title Release tag for a VI parquet path
#' @param path File path or basename
#' @return \code{"vi_modis_parquet"}, \code{"vi_viirs_parquet"}, or NA
#' @export
vi_parquet_release_tag <- function(path) {
  sensor <- parse_vi_parquet_sensor(path)
  if (is.na(sensor)) {
    return(NA_character_)
  }
  paste0("vi_", sensor, "_parquet")
}

#' @title Summarize date alignment for one VI parquet
#' @param path Path to a \code{vi_*.parquet} file
#' @param hash_values If TRUE, digest the \code{value} column (detects
#'   identical-value duplicates across filenames)
#' @param file_date Optional pre-parsed composite Date (otherwise from basename)
#' @return One-row data.frame with alignment metrics and \code{status}
#' @export
vi_parquet_date_summary <- function(path,
                                    hash_values = TRUE,
                                    file_date = NULL) {
  path <- as.character(path)[[1]]
  bn <- basename(path)
  if (is.null(file_date)) {
    file_date <- parse_vi_parquet_file_date(path)
  } else {
    file_date <- as.Date(file_date)[[1]]
  }

  empty <- data.frame(
    file = bn,
    path = path,
    sensor = parse_vi_parquet_sensor(path),
    file_date = file_date,
    n_rows = 0L,
    frac_in_filename_month = NA_real_,
    frac_in_window = NA_real_,
    modal_month = NA_integer_,
    min_date = as.Date(NA),
    max_date = as.Date(NA),
    value_hash = NA_character_,
    aligned = FALSE,
    status = "error",
    stringsAsFactors = FALSE
  )

  if (is.na(file_date)) {
    empty$status <- "bad_name"
    return(empty)
  }
  if (!file.exists(path)) {
    empty$status <- "missing"
    return(empty)
  }

  cols <- if (isTRUE(hash_values)) c("date", "value") else "date"
  df <- tryCatch(
    arrow::read_parquet(path, col_select = tidyselect::all_of(cols)),
    error = function(e) e
  )
  if (inherits(df, "error")) {
    empty$status <- paste0("read_error: ", conditionMessage(df))
    return(empty)
  }
  if (!("date" %in% names(df)) || nrow(df) == 0L) {
    empty$status <- "empty"
    return(empty)
  }

  dates <- as.Date(as.integer(df$date), origin = "1970-01-01")
  ok <- !is.na(dates)
  dates <- dates[ok]
  n <- length(dates)
  if (n == 0L) {
    empty$status <- "empty_dates"
    return(empty)
  }

  # Converter contract: epoch date = DOY within the *filename* year
  # (vi_*_geotiff_to_parquet). Late-Dec composites that extend into January
  # store Jan DOYs under that same year (e.g. 2022-01-05 for a 2022-12-31
  # file). Undo that wrap for alignment metrics only — same rule as
  # MODIS::reformatDOY (pixel DOY ≪ composite DOY → next calendar year).
  dates_cmp <- .vi_parquet_dates_for_align(dates, file_date)

  file_month <- as.integer(format(file_date, "%m"))
  months <- as.integer(format(dates_cmp, "%m"))
  frac_month <- mean(months == file_month)
  # Slack window: composite is [start, start+15]; allow a few days either side
  # for DOY jitter / adjacent-month fill inside the same 16-day product.
  window_lo <- file_date - 7L
  window_hi <- file_date + 22L
  frac_window <- mean(dates_cmp >= window_lo & dates_cmp <= window_hi)
  # modal_month from raw stored dates (diagnostics / duplicate keep_score)
  month_tab <- sort(table(as.integer(format(dates, "%m"))), decreasing = TRUE)
  modal_month <- as.integer(names(month_tab)[[1]])

  value_hash <- NA_character_
  if (isTRUE(hash_values) && "value" %in% names(df)) {
    vals <- as.integer(df$value)[ok]
    value_hash <- digest::digest(vals, algo = "sha1")
  }

  aligned <- isTRUE(frac_month >= .vi_parquet_min_frac_month) ||
    isTRUE(frac_window >= .vi_parquet_min_frac_window)

  data.frame(
    file = bn,
    path = path,
    sensor = parse_vi_parquet_sensor(path),
    file_date = file_date,
    n_rows = as.integer(n),
    frac_in_filename_month = as.numeric(frac_month),
    frac_in_window = as.numeric(frac_window),
    modal_month = modal_month,
    min_date = min(dates),
    max_date = max(dates),
    value_hash = value_hash,
    aligned = aligned,
    status = if (aligned) "ok" else "misaligned",
    stringsAsFactors = FALSE
  )
}

#' @title Whether parquet row dates match the filename composite
#' @param path Path to parquet
#' @param min_frac_month Minimum fraction of rows in the filename month
#' @param min_frac_window Minimum fraction of rows in the composite slack window
#' @return Logical (FALSE on read/name errors)
#' @export
vi_parquet_content_matches_file_date <- function(
    path,
    min_frac_month = .vi_parquet_min_frac_month,
    min_frac_window = .vi_parquet_min_frac_window) {
  s <- vi_parquet_date_summary(path, hash_values = FALSE)
  if (!identical(s$status, "ok") && !identical(s$status, "misaligned")) {
    return(FALSE)
  }
  isTRUE(s$frac_in_filename_month >= min_frac_month) ||
    isTRUE(s$frac_in_window >= min_frac_window)
}

#' @title Audit a vector of VI parquet paths
#' @param paths Character vector of parquet paths
#' @param hash_values Digest value columns for duplicate detection
#' @param flag_duplicate_values If TRUE, mark non-canonical paths that share a
#'   value hash with another file as \code{status = "duplicate_values"}
#'   (only when also misaligned, or always when \code{flag_all_duplicates})
#' @param flag_all_duplicates If TRUE, flag every duplicate-hash group member
#'   except the first (by filename); if FALSE (default), only upgrade
#'   misaligned rows that share a hash with any other file
#' @param verbose Print progress every 25 files
#' @return Data frame of per-file summaries (sorted by sensor, file_date)
#' @export
audit_vi_parquet_paths <- function(paths,
                                   hash_values = TRUE,
                                   flag_duplicate_values = TRUE,
                                   flag_all_duplicates = FALSE,
                                   verbose = TRUE) {
  paths <- unique(as.character(paths[!is.na(paths) & nzchar(paths)]))
  if (length(paths) == 0L) {
    return(.vi_parquet_empty_audit_df())
  }

  rows <- vector("list", length(paths))
  for (i in seq_along(paths)) {
    if (verbose && (i == 1L || i %% 25L == 0L || i == length(paths))) {
      message("  audit VI parquet ", i, "/", length(paths), ": ", basename(paths[[i]]))
    }
    rows[[i]] <- vi_parquet_date_summary(paths[[i]], hash_values = hash_values)
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL

  if (isTRUE(flag_duplicate_values) && isTRUE(hash_values)) {
    out <- .vi_parquet_flag_value_duplicates(
      out,
      flag_all = isTRUE(flag_all_duplicates)
    )
  }

  out[order(out$sensor, out$file_date, out$file, na.last = TRUE), , drop = FALSE]
}

#' @keywords internal
.vi_parquet_empty_audit_df <- function() {
  data.frame(
    file = character(),
    path = character(),
    sensor = character(),
    file_date = as.Date(character()),
    n_rows = integer(),
    frac_in_filename_month = numeric(),
    frac_in_window = numeric(),
    modal_month = integer(),
    min_date = as.Date(character()),
    max_date = as.Date(character()),
    value_hash = character(),
    aligned = logical(),
    status = character(),
    stringsAsFactors = FALSE
  )
}

#' @keywords internal
.vi_parquet_flag_value_duplicates <- function(out, flag_all = FALSE) {
  if (nrow(out) == 0L) {
    return(out)
  }
  hash <- out$value_hash
  ok_hash <- !is.na(hash) & nzchar(hash)
  if (!any(ok_hash)) {
    return(out)
  }
  tab <- table(hash[ok_hash])
  dup_hashes <- names(tab)[tab > 1L]
  if (length(dup_hashes) == 0L) {
    return(out)
  }

  for (h in dup_hashes) {
    idx <- which(out$value_hash == h)
    # Prefer keeping the file whose filename month matches modal content month
    keep_score <- ifelse(
      !is.na(out$modal_month[idx]) & !is.na(out$file_date[idx]),
      as.integer(
        as.integer(format(out$file_date[idx], "%m")) == out$modal_month[idx]
      ),
      0L
    )
    # Break ties: prefer aligned, then earliest file_date
    ord <- order(
      -keep_score,
      -as.integer(out$aligned[idx]),
      out$file_date[idx],
      out$file[idx]
    )
    keep_i <- idx[[ord[[1]]]]
    drop_i <- setdiff(idx, keep_i)
    if (isTRUE(flag_all)) {
      out$status[drop_i] <- "duplicate_values"
      out$aligned[drop_i] <- FALSE
    } else {
      # Only annotate misaligned members of a duplicate group
      mis <- drop_i[!out$aligned[drop_i]]
      if (length(mis)) {
        out$status[mis] <- "duplicate_values"
      }
      # Also mark aligned-but-byte-identical peers when another copy exists
      # with the same hash and a better month match — rare but useful.
      peers <- drop_i[out$aligned[drop_i]]
      if (length(peers) && keep_score[match(keep_i, idx)] >
            max(keep_score[match(peers, idx)], 0L)) {
        out$status[peers] <- "duplicate_values"
        out$aligned[peers] <- FALSE
      }
    }
  }
  out
}

#' @title Audit local MODIS/VIIRS VI parquet directories
#' @param dirs Directories to scan (default CCR product dirs)
#' @param pattern Basename regex
#' @param out_csv Optional CSV path for the report
#' @param hash_values Digest values for duplicate detection
#' @param verbose Progress messages
#' @return Data frame (also written to \code{out_csv} when set)
#' @export
audit_vi_parquet_dirs <- function(
    dirs = c(
      "data/target_outputs/modis_vi",
      "data/target_outputs/viirs_vi"
    ),
    pattern = "^vi_(modis|viirs)_[0-9]{8}\\.parquet$",
    out_csv = NULL,
    hash_values = TRUE,
    verbose = TRUE) {
  paths <- unlist(lapply(dirs, function(d) {
    if (!dir.exists(d)) {
      if (verbose) message("Missing dir (skip): ", d)
      return(character(0))
    }
    list.files(d, pattern = pattern, full.names = TRUE)
  }), use.names = FALSE)

  if (verbose) {
    message("Auditing ", length(paths), " VI parquet(s) under: ",
            paste(dirs, collapse = ", "))
  }
  report <- audit_vi_parquet_paths(
    paths,
    hash_values = hash_values,
    verbose = verbose
  )

  if (verbose && nrow(report) > 0L) {
    n_bad <- sum(report$status != "ok", na.rm = TRUE)
    message(
      "Audit complete: ", nrow(report), " files; ",
      sum(report$aligned, na.rm = TRUE), " aligned; ",
      n_bad, " flagged (",
      paste(
        names(sort(table(report$status[report$status != "ok"]), decreasing = TRUE)),
        collapse = ", "
      ),
      ")"
    )
  }

  if (!is.null(out_csv) && nzchar(out_csv)) {
    dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(report, out_csv, row.names = FALSE)
    if (verbose) message("Wrote ", out_csv)
  }
  invisible(report)
}

#' @title Filter VI parquets before GitHub release upload
#' @description Drops files whose content dates do not match the filename
#'   composite. Set \code{EMMA_VI_PARQUET_STRICT=1} (or \code{strict = TRUE})
#'   to stop instead of skipping.
#' @param files Character vector of paths from \code{list_release_inventory()}
#' @param strict Logical; NA reads env \code{EMMA_VI_PARQUET_STRICT}
#' @param verbose Messages
#' @return Character vector of paths safe to upload
#' @export
filter_vi_parquets_for_upload <- function(files,
                                          strict = NA,
                                          verbose = TRUE) {
  files <- as.character(files)
  files <- files[!is.na(files) & nzchar(files)]
  if (length(files) == 0L) {
    return(character(0))
  }

  # Only gate VI parquet product names; pass everything else through.
  is_vi <- grepl("^vi_(modis|viirs)_[0-9]{8}\\.parquet$", basename(files))
  other <- files[!is_vi]
  vi_files <- files[is_vi]
  if (length(vi_files) == 0L) {
    return(files)
  }

  if (is.na(strict)) {
    strict <- identical(Sys.getenv("EMMA_VI_PARQUET_STRICT", unset = ""), "1")
  }

  keep <- logical(length(vi_files))
  bad_names <- character(0)
  for (i in seq_along(vi_files)) {
    ok <- vi_parquet_content_matches_file_date(vi_files[[i]])
    keep[[i]] <- isTRUE(ok)
    if (!ok) {
      bad_names <- c(bad_names, basename(vi_files[[i]]))
    }
  }

  if (length(bad_names) > 0L) {
    msg <- paste0(
      length(bad_names), " VI parquet(s) fail date/filename alignment",
      " (frac_month < ", .vi_parquet_min_frac_month,
      " and frac_window < ", .vi_parquet_min_frac_window, "): ",
      paste(utils::head(bad_names, 15L), collapse = ", "),
      if (length(bad_names) > 15L) " ..." else ""
    )
    if (isTRUE(strict)) {
      stop(msg, ". Refusing upload (EMMA_VI_PARQUET_STRICT=1).", call. = FALSE)
    }
    if (verbose) {
      warning(msg, " — skipping upload of those files.", call. = FALSE)
    }
  } else if (verbose) {
    message(
      "VI parquet date-align guard: ", length(vi_files),
      " file(s) OK"
    )
  }

  c(other, vi_files[keep])
}

#' Retry a GitHub API call on transient DNS / connection errors.
#' @keywords internal
.gh_retry <- function(expr, tries = 6L, base_sleep = 2, verbose = TRUE) {
  last_err <- NULL
  for (i in seq_len(as.integer(tries))) {
    out <- tryCatch(force(expr), error = function(e) e)
    if (!inherits(out, "error")) {
      return(out)
    }
    last_err <- out
    msg <- conditionMessage(out)
    transient <- grepl(
      "resolve host|Could not resolve|Timeout|timed out|Connection|HTTP 5|SSL|TLS|Temporary failure",
      msg,
      ignore.case = TRUE
    )
    if (!transient || i >= tries) {
      stop(last_err)
    }
    wait <- base_sleep * (2^(i - 1L))
    if (isTRUE(verbose)) {
      message("GitHub API retry ", i, "/", tries, " in ", wait, "s: ", msg)
    }
    Sys.sleep(wait)
  }
  stop(last_err)
}

#' @title Delete named assets from a GitHub release (paginated)
#' @description Unlike the embedded \code{rel$assets} list (capped ~30), this
#'   pages the assets API so large VI parquet releases can be cleaned.
#' @param repo owner/repo
#' @param release_tag Tag name
#' @param asset_names Character vector of basenames to delete
#' @param token GitHub token (optional; uses upload token helper when empty)
#' @param verbose Messages
#' @return Invisibly, character vector of deleted basenames
#' @export
gh_delete_release_assets_by_name <- function(repo,
                                             release_tag,
                                             asset_names,
                                             token = NULL,
                                             verbose = TRUE) {
  asset_names <- unique(as.character(asset_names[!is.na(asset_names)]))
  if (length(asset_names) == 0L) {
    return(invisible(character(0)))
  }
  if (is.null(token) || !nzchar(token)) {
    token <- .gh_upload_token(verbose = verbose)
  }
  parts <- strsplit(repo, "/")[[1]]
  rel <- .gh_retry(
    gh::gh(
      "GET /repos/{owner}/{repo}/releases/tags/{tag}",
      owner = parts[[1]], repo = parts[[2]], tag = release_tag,
      .token = token
    ),
    verbose = verbose
  )
  assets <- .gh_retry(
    gh::gh(
      "GET /repos/{owner}/{repo}/releases/{release_id}/assets",
      owner = parts[[1]], repo = parts[[2]], release_id = rel$id,
      per_page = 100,
      .token = token,
      .limit = Inf
    ),
    verbose = verbose
  )
  if (length(assets) == 0L) {
    return(invisible(character(0)))
  }
  if (!is.null(assets$name) && is.character(assets$name)) {
    assets <- list(assets)
  }

  deleted <- character(0)
  for (a in assets) {
    if (!(a$name %in% asset_names)) {
      next
    }
    tryCatch({
      .gh_retry(
        gh::gh(
          "DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}",
          owner = parts[[1]], repo = parts[[2]], asset_id = a$id,
          .token = token
        ),
        tries = 4L,
        verbose = verbose
      )
      deleted <- c(deleted, a$name)
      if (verbose) message("Deleted release asset: ", a$name, " @ ", release_tag)
      Sys.sleep(0.3)
    }, error = function(e) {
      warning(
        "Could not delete ", a$name, " from ", release_tag, ": ",
        conditionMessage(e),
        call. = FALSE
      )
    })
  }
  invisible(deleted)
}
