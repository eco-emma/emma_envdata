#' @title Audit and reprocess suspicious all-NA burn/VI placeholder grids
#' @description One-off maintenance script (not part of `_targets.R`). Before
#'   the `rs_transfer()` error-handling fix (see R/get_burn_dates_viirs.R,
#'   R/get_burn_dates_modis.R, R/get_modis_vi.R, R/get_viirs_vi.R), a
#'   transient AppEEARS/network failure during download could be silently
#'   written as a permanent "confirmed no data" all-NA COG or `.skip` marker.
#'   This script finds those placeholders within each sensor's valid
#'   observation window, and — unless `dry_run = TRUE` — deletes the local
#'   file and matching GitHub release asset so the next `tar_make()` submits
#'   a real AppEEARS task instead of trusting the stale placeholder.
#' @details Run manually from the repo root, e.g.:
#'   \preformatted{
#'   source("R/audit_na_placeholders.R")
#'   audit_burn_na_grids("burn_modis", valid_start = "2000-11-01", dry_run = TRUE)
#'   audit_burn_na_grids("burn_viirs", valid_start = "2012-01-01", dry_run = TRUE)
#'   audit_vi_na_grids("vi_modis", sensors = c("terra", "aqua"),
#'                      valid_start = "2000-02-01", dry_run = TRUE)
#'   audit_vi_na_grids("vi_viirs", sensors = c("snpp", "noaa20"),
#'                      valid_start = "2012-01-01", dry_run = TRUE)
#'   audit_skip_markers("data/target_outputs/burndates", valid_start = "2000-11-01",
#'                       dry_run = TRUE)
#'   }
#'   Inspect the returned data frame first; re-run with `dry_run = FALSE` only
#'   once you're satisfied the flagged months/composites should be reprocessed.
NULL

#' @keywords internal
.gh_delete_release_asset_by_name <- function(repo, release_tag, asset_name, token) {
  parts <- strsplit(repo, "/")[[1]]
  tryCatch({
    rel <- gh::gh("GET /repos/{owner}/{repo}/releases/tags/{tag}",
                  owner = parts[1], repo = parts[2], tag = release_tag, .token = token)
    match_asset <- Filter(function(a) identical(a$name, asset_name), rel$assets)
    if (length(match_asset) == 0L) return(invisible(FALSE))
    gh::gh("DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}",
           owner = parts[1], repo = parts[2], asset_id = match_asset[[1]]$id, .token = token)
    invisible(TRUE)
  }, error = function(e) {
    warning("Could not delete release asset ", asset_name, ": ", conditionMessage(e))
    invisible(FALSE)
  })
}

#' @keywords internal
.audit_github_token <- function() {
  token <- Sys.getenv("GITHUB_PAT")
  if (token == "") token <- Sys.getenv("GITHUB_TOKEN")
  token
}

#' @title Audit burn-date grid COGs for suspicious all-NA placeholders
#' @param dataset "burn_modis" or "burn_viirs"
#' @param local_dir Directory containing burn_*_YYYYMM.tif grid COGs
#' @param repo GitHub "owner/repo"
#' @param release_tag Release tag holding the grid COGs; defaults to
#'   "<dataset>_raster" (e.g. "burn_modis_raster")
#' @param valid_start Character "YYYY-MM-DD"; months before this are skipped
#'   (sensor not yet operating — genuinely no data expected, e.g. MCD64A1
#'   begins 2000-11, VNP64A1 begins 2012-01)
#' @param min_age_days Skip months newer than this many days old — they may
#'   still be legitimately mid-processing / awaiting the next scheduled run
#' @param dry_run If TRUE (default), only reports findings; deletes nothing
#' @return Data frame of flagged (all-NA) months: yyyymm, file, all_na
#' @export
audit_burn_na_grids <- function(
    dataset,
    local_dir    = "data/target_outputs/burndates",
    repo         = "eco-emma/emma_envdata",
    release_tag  = paste0(dataset, "_raster"),
    valid_start,
    min_age_days = 45,
    dry_run      = TRUE) {

  stopifnot(dataset %in% c("burn_modis", "burn_viirs"))

  local_files <- list.files(local_dir, pattern = paste0("^", dataset, "_[0-9]{6}\\.tif$"),
                            full.names = TRUE)
  if (length(local_files) == 0L) {
    message("No local ", dataset, " grid files found in ", local_dir)
    return(invisible(data.frame()))
  }

  valid_start_date <- as.Date(valid_start)
  cutoff_date       <- Sys.Date() - min_age_days

  results <- purrr::map_dfr(local_files, function(f) {
    yyyymm      <- sub(paste0("^", dataset, "_"), "", tools::file_path_sans_ext(basename(f)))
    month_start <- as.Date(paste0(yyyymm, "01"), format = "%Y%m%d")
    if (is.na(month_start) || month_start < valid_start_date || month_start > cutoff_date) {
      return(NULL)  # outside the audit window
    }
    r       <- terra::rast(f)
    n_valid <- terra::global(r, fun = "notNA")[1, 1]
    data.frame(yyyymm = yyyymm, file = f, all_na = n_valid == 0, stringsAsFactors = FALSE)
  })

  flagged <- results[results$all_na, , drop = FALSE]
  if (nrow(flagged) == 0L) {
    message("No suspicious all-NA ", dataset, " grids found in audit window.")
    return(invisible(flagged))
  }

  message(nrow(flagged), " suspicious all-NA ", dataset, " grid(s): ",
          paste(flagged$yyyymm, collapse = ", "))
  if (dry_run) {
    message("dry_run = TRUE \u2014 no files deleted. Re-run with dry_run = FALSE to reprocess.")
    return(flagged)
  }

  token <- .audit_github_token()
  for (f in flagged$file) {
    unlink(f)
    message("Deleted local placeholder: ", f)
    if (.gh_delete_release_asset_by_name(repo, release_tag, basename(f), token)) {
      message("Deleted release asset: ", basename(f))
    }
  }
  message("Run targets::tar_make() to resubmit AppEEARS tasks for: ",
          paste(flagged$yyyymm, collapse = ", "))
  invisible(flagged)
}

#' @title Audit VI grid COGs for placeholder ("no_data") composites
#' @param dataset "vi_modis" or "vi_viirs"
#' @param sensors Character vector of per-sensor file infixes, e.g.
#'   c("terra", "aqua") for MODIS or c("snpp", "noaa20") for VIIRS
#' @param local_dir Directory containing vi_*_<sensor>_YYYYMMDD.tif grid COGs;
#'   defaults to "data/target_outputs/modis_vi" or "data/target_outputs/viirs_vi"
#' @param repo GitHub "owner/repo"
#' @param release_tag Release tag holding the grid COGs; defaults to
#'   "<dataset>_raster" (e.g. "vi_modis_raster")
#' @param valid_start Character "YYYY-MM-DD"; composites before this are skipped
#' @param min_age_days Skip composites newer than this many days old
#' @param dry_run If TRUE (default), only reports findings; deletes nothing
#' @return Data frame of flagged (placeholder) composites: yyyymmdd, sensor, file
#' @export
audit_vi_na_grids <- function(
    dataset,
    sensors,
    local_dir    = if (dataset == "vi_modis") "data/target_outputs/modis_vi"
                  else "data/target_outputs/viirs_vi",
    repo         = "eco-emma/emma_envdata",
    release_tag  = paste0(dataset, "_raster"),
    valid_start,
    min_age_days = 45,
    dry_run      = TRUE) {

  stopifnot(dataset %in% c("vi_modis", "vi_viirs"))

  valid_start_date <- as.Date(valid_start)
  cutoff_date       <- Sys.Date() - min_age_days

  results <- purrr::map_dfr(sensors, function(sensor) {
    pattern <- paste0("^", dataset, "_", sensor, "_[0-9]{8}\\.tif$")
    files   <- list.files(local_dir, pattern = pattern, full.names = TRUE)
    if (length(files) == 0L) return(NULL)

    purrr::map_dfr(files, function(f) {
      yyyymmdd <- sub(paste0("^", dataset, "_", sensor, "_"), "",
                      tools::file_path_sans_ext(basename(f)))
      composite_date <- as.Date(yyyymmdd, format = "%Y%m%d")
      if (is.na(composite_date) || composite_date < valid_start_date ||
          composite_date > cutoff_date) {
        return(NULL)
      }
      # Placeholder COGs are tagged source = "no_data" in write_na_cog() —
      # a more reliable signal than an all-NA content check since this
      # metags value is only ever set by the placeholder path.
      r         <- terra::rast(f)
      src_tag   <- tryCatch(terra::metags(r)[["source"]], error = function(e) NA_character_)
      is_marker <- !is.na(src_tag) && identical(src_tag, "no_data")
      data.frame(yyyymmdd = yyyymmdd, sensor = sensor, file = f,
                is_no_data = is_marker, stringsAsFactors = FALSE)
    })
  })

  flagged <- results[results$is_no_data, , drop = FALSE]
  if (nrow(flagged) == 0L) {
    message("No suspicious no_data ", dataset, " grids found in audit window.")
    return(invisible(flagged))
  }

  message(nrow(flagged), " suspicious no_data ", dataset, " grid(s): ",
          paste(paste0(flagged$sensor, "/", flagged$yyyymmdd), collapse = ", "))
  if (dry_run) {
    message("dry_run = TRUE \u2014 no files deleted. Re-run with dry_run = FALSE to reprocess.")
    return(flagged)
  }

  token <- .audit_github_token()
  for (f in flagged$file) {
    unlink(f)
    message("Deleted local placeholder: ", f)
    if (.gh_delete_release_asset_by_name(repo, release_tag, basename(f), token)) {
      message("Deleted release asset: ", basename(f))
    }
  }
  message("Run targets::tar_make() to resubmit AppEEARS tasks for: ",
          paste(paste0(flagged$sensor, "/", flagged$yyyymmdd), collapse = ", "))
  invisible(flagged)
}

#' @title Audit stale ".skip" markers left by past acquisition failures
#' @description `.skip` markers (written when AppEEARS returned zero GeoTIFFs)
#'   live only on local disk / the `targets-cache` release, never on the
#'   per-dataset raster/parquet releases, so no release-asset deletion is
#'   needed here — just remove the stale marker so the branch reprocesses.
#' @param local_dir Directory to scan for "*.skip" files
#' @param valid_start Character "YYYY-MM-DD"; dates before this are skipped
#' @param min_age_days Skip markers newer than this many days old
#' @param dry_run If TRUE (default), only reports findings; deletes nothing
#' @return Character vector of flagged marker file paths
#' @export
audit_skip_markers <- function(
    local_dir,
    valid_start,
    min_age_days = 45,
    dry_run      = TRUE) {

  markers <- list.files(local_dir, pattern = "\\.skip$", full.names = TRUE)
  if (length(markers) == 0L) {
    message("No .skip markers found in ", local_dir)
    return(invisible(character(0)))
  }

  valid_start_date <- as.Date(valid_start)
  cutoff_date       <- Sys.Date() - min_age_days

  # Extract the trailing 6- or 8-digit date token from the marker filename
  date_token <- regmatches(basename(markers), regexpr("[0-9]{6,8}(?=\\.skip$)",
                                                       basename(markers), perl = TRUE))
  marker_date <- as.Date(ifelse(nchar(date_token) == 6, paste0(date_token, "01"), date_token),
                         format = "%Y%m%d")

  in_window <- !is.na(marker_date) & marker_date >= valid_start_date & marker_date <= cutoff_date
  flagged   <- markers[in_window]

  if (length(flagged) == 0L) {
    message("No stale .skip markers found in audit window.")
    return(invisible(flagged))
  }

  message(length(flagged), " stale .skip marker(s): ", paste(basename(flagged), collapse = ", "))
  if (dry_run) {
    message("dry_run = TRUE \u2014 no files deleted. Re-run with dry_run = FALSE to reprocess.")
    return(flagged)
  }

  unlink(flagged)
  message("Deleted ", length(flagged), " stale .skip marker(s). ",
          "Run targets::tar_make() to reprocess.")
  invisible(flagged)
}
