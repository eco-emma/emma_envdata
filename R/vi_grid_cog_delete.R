#' @title Delete bad VI sensor grid COGs (local + GitHub Releases)
#' @description Maps flagged \code{vi_*.parquet} audit rows to per-sensor
#'   COG assets (\code{vi_modis_{terra,aqua}_YYYYMMDD.tif},
#'   \code{vi_viirs_{snpp,noaa20}_YYYYMMDD.tif}) so CCR can remove poisoned
#'   grids. \code{filter_pending_composites()} is name-only: once a bad COG
#'   is on the release, AppEEARS never re-queues that date until the asset
#'   is deleted.
#' @name vi_grid_cog_delete
NULL

#' Local product dirs for VI sensor grids.
#' @keywords internal
.vi_grid_local_dirs <- function() {
  list(
    modis = "data/target_outputs/modis_vi",
    viirs = "data/target_outputs/viirs_vi"
  )
}

#' @title Map one VI parquet basename to sensor grid assets
#' @param path Parquet path or basename (\code{vi_modis_YYYYMMDD.parquet} /
#'   \code{vi_viirs_YYYYMMDD.parquet})
#' @return data.frame with columns \code{yyyymmdd}, \code{sensor},
#'   \code{dataset}, \code{asset}, \code{release_tag}, \code{local_path},
#'   \code{parquet_file}
#' @export
vi_parquet_to_grid_assets <- function(path) {
  path <- as.character(path)
  empty <- data.frame(
    yyyymmdd = character(0),
    sensor = character(0),
    dataset = character(0),
    asset = character(0),
    release_tag = character(0),
    local_path = character(0),
    parquet_file = character(0),
    stringsAsFactors = FALSE
  )
  if (!length(path)) {
    return(empty)
  }

  rows <- lapply(path, function(p) {
    bn <- basename(p)
    sensor <- parse_vi_parquet_sensor(bn)
    file_date <- parse_vi_parquet_file_date(bn)
    if (is.na(sensor) || is.na(file_date)) {
      return(NULL)
    }
    yyyymmdd <- format(file_date, "%Y%m%d")
    dirs <- .vi_grid_local_dirs()
    if (identical(sensor, "modis")) {
      sensors <- c("terra", "aqua")
      tags <- c("vi_modis_terra_raster", "vi_modis_aqua_raster")
      local_dir <- dirs$modis
      dataset <- "vi_modis"
    } else {
      sensors <- c("snpp", "noaa20")
      tags <- rep("vi_viirs_raster", 2L)
      local_dir <- dirs$viirs
      dataset <- "vi_viirs"
    }
    assets <- paste0(dataset, "_", sensors, "_", yyyymmdd, ".tif")
    data.frame(
      yyyymmdd = yyyymmdd,
      sensor = sensors,
      dataset = dataset,
      asset = assets,
      release_tag = tags,
      local_path = file.path(local_dir, assets),
      parquet_file = bn,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  if (is.null(out) || !nrow(out)) {
    return(empty)
  }
  rownames(out) <- NULL
  out
}

#' @title Build grid-asset delete list from a parquet date-audit CSV
#' @description Uses rows with \code{status != "ok"}. If the CSV has no
#'   flagged rows (e.g. overwritten after local-only deletes left only the
#'   262 aligned survivors), returns an empty frame and sets
#'   \code{attr(,"csv_warning")}.
#' @param csv_path Path to \code{vi_parquet_date_audit.csv}
#' @return data.frame from [vi_parquet_to_grid_assets()]; may be empty
#' @export
vi_grid_assets_from_parquet_audit <- function(csv_path) {
  csv_path <- as.character(csv_path)[[1L]]
  if (!file.exists(csv_path)) {
    stop("Missing audit CSV: ", csv_path, call. = FALSE)
  }
  report <- utils::read.csv(csv_path, stringsAsFactors = FALSE)
  if (!("file" %in% names(report)) || !("status" %in% names(report))) {
    stop(
      "Audit CSV must have columns 'file' and 'status': ", csv_path,
      call. = FALSE
    )
  }
  n_ok <- sum(report$status == "ok", na.rm = TRUE)
  flagged <- report[report$status != "ok", , drop = FALSE]
  assets <- vi_parquet_to_grid_assets(flagged$file)
  if (!nrow(flagged)) {
    attr(assets, "csv_warning") <- paste0(
      "CSV has 0 flagged rows (", n_ok, " status=ok). ",
      "This looks like a post-local-delete survivor scan, not the 683-flagged ",
      "pre-delete audit. Prefer an older CSV, or use --from-local-doy / ",
      "--dates-file."
    )
  } else {
    attr(assets, "csv_warning") <- NULL
    attr(assets, "n_flagged_parquet") <- nrow(flagged)
  }
  assets
}

#' Candidate paths for a pre-delete flagged parquet audit CSV on CCR.
#' @export
vi_parquet_audit_csv_candidates <- function(
    primary = "data/target_outputs/vi_parquet_date_audit.csv") {
  unique(c(
    primary,
    "data/target_outputs/vi_parquet_date_audit_pre_delete.csv",
    "data/target_outputs/vi_parquet_date_audit_flagged.csv",
    "data/target_outputs/vi_parquet_date_audit_683.csv",
    "data/target_outputs/vi_parquet_date_audit.csv.bak"
  ))
}

#' Pick the best available parquet audit CSV (prefer one with flagged rows).
#' @return Path string, or NA if none exist
#' @export
resolve_vi_parquet_audit_csv <- function(
    primary = "data/target_outputs/vi_parquet_date_audit.csv") {
  cands <- vi_parquet_audit_csv_candidates(primary)
  existing <- cands[file.exists(cands)]
  if (!length(existing)) {
    return(NA_character_)
  }
  scored <- lapply(existing, function(p) {
    r <- tryCatch(
      utils::read.csv(p, stringsAsFactors = FALSE),
      error = function(e) NULL
    )
    if (is.null(r) || !("status" %in% names(r))) {
      return(list(path = p, n_flagged = -1L, n = 0L))
    }
    list(
      path = p,
      n_flagged = sum(r$status != "ok", na.rm = TRUE),
      n = nrow(r)
    )
  })
  n_flagged <- vapply(scored, function(x) x$n_flagged, integer(1))
  best <- which.max(n_flagged)
  if (n_flagged[[best]] <= 0L) {
    # Still return primary/existing so caller can emit the survivor warning.
    return(existing[[1L]])
  }
  scored[[best]]$path
}

#' @title Flag local VI grid COGs that fail the DOY/filename guard
#' @description Scans product dirs for sensor COGs where
#'   [vi_cog_doy_matches_composite()] is FALSE (Jul–Aug template on wrong
#'   basename dates). Does not download release assets.
#' @param modis_dir Local MODIS VI dir
#' @param viirs_dir Local VIIRS VI dir
#' @param verbose Messages
#' @return data.frame with same columns as [vi_parquet_to_grid_assets()]
#'   plus \code{reason}
#' @export
vi_flag_local_grids_by_doy <- function(
    modis_dir = .vi_grid_local_dirs()$modis,
    viirs_dir = .vi_grid_local_dirs()$viirs,
    verbose = TRUE) {
  patterns <- c(
    list.files(modis_dir, pattern = "^vi_modis_(terra|aqua)_[0-9]{8}\\.tif$",
               full.names = TRUE),
    list.files(viirs_dir, pattern = "^vi_viirs_(snpp|noaa20)_[0-9]{8}\\.tif$",
               full.names = TRUE)
  )
  if (!length(patterns)) {
    if (verbose) {
      message("No local VI sensor COGs found under ", modis_dir, " / ", viirs_dir)
    }
    return(vi_parquet_to_grid_assets(character(0)))
  }

  bad <- character(0)
  for (f in patterns) {
    if (!isTRUE(vi_cog_doy_matches_composite(f))) {
      bad <- c(bad, f)
    }
  }
  if (verbose) {
    message(
      "Local DOY scan: ", length(bad), " / ", length(patterns),
      " COG(s) fail vi_cog_doy_matches_composite()"
    )
  }
  if (!length(bad)) {
    return(data.frame(
      yyyymmdd = character(0),
      sensor = character(0),
      dataset = character(0),
      asset = character(0),
      release_tag = character(0),
      local_path = character(0),
      parquet_file = character(0),
      reason = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # Build asset rows from basenames (no parquet intermediate).
  rows <- lapply(bad, function(f) {
    bn <- basename(f)
    m <- regexec(
      "^vi_(modis|viirs)_(terra|aqua|snpp|noaa20)_([0-9]{8})\\.tif$",
      bn,
      perl = TRUE
    )
    hit <- regmatches(bn, m)[[1]]
    if (length(hit) < 4L) {
      return(NULL)
    }
    dataset <- paste0("vi_", hit[[2]])
    sensor <- hit[[3]]
    yyyymmdd <- hit[[4]]
    tag <- if (identical(dataset, "vi_modis") && identical(sensor, "terra")) {
      "vi_modis_terra_raster"
    } else if (identical(dataset, "vi_modis") && identical(sensor, "aqua")) {
      "vi_modis_aqua_raster"
    } else {
      "vi_viirs_raster"
    }
    data.frame(
      yyyymmdd = yyyymmdd,
      sensor = sensor,
      dataset = dataset,
      asset = bn,
      release_tag = tag,
      local_path = f,
      parquet_file = NA_character_,
      reason = "doy_mismatch",
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' @title Expand YYYYMMDD tokens to full sensor grid asset rows
#' @param yyyymmdd Character vector of composite starts
#' @param sensors Which sensor families: \code{"modis"}, \code{"viirs"}, or both
#' @return data.frame like [vi_parquet_to_grid_assets()]
#' @export
vi_grid_assets_from_dates <- function(yyyymmdd,
                                      sensors = c("modis", "viirs")) {
  yyyymmdd <- unique(as.character(yyyymmdd))
  yyyymmdd <- yyyymmdd[grepl("^[0-9]{8}$", yyyymmdd)]
  sensors <- match.arg(sensors, several.ok = TRUE)
  if (!length(yyyymmdd)) {
    return(vi_parquet_to_grid_assets(character(0)))
  }
  paths <- character(0)
  if ("modis" %in% sensors) {
    paths <- c(paths, paste0("vi_modis_", yyyymmdd, ".parquet"))
  }
  if ("viirs" %in% sensors) {
    paths <- c(paths, paste0("vi_viirs_", yyyymmdd, ".parquet"))
  }
  vi_parquet_to_grid_assets(paths)
}

#' @title Dry-run or delete VI grid assets (remote + optional local)
#' @param assets data.frame from the helpers above (\code{asset},
#'   \code{release_tag}, \code{local_path})
#' @param repo GitHub owner/repo
#' @param delete_remote Delete matching release assets
#' @param delete_local Unlink local COGs when present
#' @param dry_run If TRUE, only report
#' @param verbose Messages
#' @return Invisibly, list(\code{remote_deleted}, \code{local_deleted},
#'   \code{assets})
#' @export
delete_vi_grid_assets <- function(assets,
                                  repo = "eco-emma/emma_envdata",
                                  delete_remote = FALSE,
                                  delete_local = FALSE,
                                  dry_run = TRUE,
                                  verbose = TRUE) {
  if (!nrow(assets)) {
    if (verbose) message("No VI grid assets to delete.")
    return(invisible(list(
      remote_deleted = character(0),
      local_deleted = character(0),
      assets = assets
    )))
  }
  assets <- unique(assets[, c("asset", "release_tag", "local_path")])
  rownames(assets) <- NULL

  if (verbose) {
    by_tag <- split(assets$asset, assets$release_tag)
    message(
      "VI grid delete plan: ", nrow(assets), " asset(s) across ",
      length(by_tag), " release tag(s)"
    )
    for (tag in names(by_tag)) {
      message("  @", tag, ": ", length(by_tag[[tag]]),
              "  e.g. ", paste(utils::head(by_tag[[tag]], 3L), collapse = ", "))
    }
  }

  if (isTRUE(dry_run) || (!delete_remote && !delete_local)) {
    if (verbose) {
      message(
        "Dry run — not deleting. Re-run with delete_remote=TRUE / ",
        "delete_local=TRUE and dry_run=FALSE."
      )
    }
    return(invisible(list(
      remote_deleted = character(0),
      local_deleted = character(0),
      assets = assets
    )))
  }

  remote_deleted <- character(0)
  if (isTRUE(delete_remote)) {
    token <- .gh_upload_token(verbose = verbose)
    by_tag <- split(assets$asset, assets$release_tag)
    for (tag in names(by_tag)) {
      if (is.na(tag) || !nzchar(tag)) next
      if (verbose) {
        message(
          "Deleting ", length(by_tag[[tag]]),
          " release asset(s) from @", tag, " …"
        )
      }
      deleted <- gh_delete_release_assets_by_name(
        repo = repo,
        release_tag = tag,
        asset_names = by_tag[[tag]],
        token = token,
        verbose = verbose
      )
      remote_deleted <- c(remote_deleted, deleted)
    }
  }

  local_deleted <- character(0)
  if (isTRUE(delete_local)) {
    for (p in unique(assets$local_path)) {
      if (!is.na(p) && nzchar(p) && file.exists(p)) {
        unlink(p)
        local_deleted <- c(local_deleted, p)
        if (verbose) message("Deleted local: ", p)
      }
    }
  }

  invisible(list(
    remote_deleted = remote_deleted,
    local_deleted = local_deleted,
    assets = assets
  ))
}
