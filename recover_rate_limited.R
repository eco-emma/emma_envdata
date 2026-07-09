#!/usr/bin/env Rscript
# ============================================================================
# recover_rate_limited.R
#
# One-shot recovery script for AppEEARS branches that got stuck as
# "rate_limited:..." sentinels by an older version of the submit_*()
# functions (see commit 96467a98).  Those sentinels caused every downstream
# target (geotiff, grid, parquet) to silently succeed with all-NA / .skip
# placeholders, so `tar_make()` now skips them all and the pipeline never
# rechecks AppEEARS even after the daily rate limit resets.
#
# The script operates in two independent modes; you can enable one or both:
#
#   A. tar_meta scan (default): finds task_ids branches whose stored value is
#      a "rate_limited:..." sentinel, deletes the matching local artifacts,
#      and invalidates those branches so they re-run on the next tar_make().
#
#   B. Release scan (--scan-releases): downloads every small raster COG
#      asset published on the burn_modis_raster / burn_viirs_raster /
#      vi_modis_raster / vi_viirs_raster releases, checks whether it is an
#      all-NA placeholder, and — crucially — compares it against the
#      corresponding LOCAL COG.  An asset is flagged as STALE only when the
#      release version is a placeholder AND the local version contains real
#      data.  This avoids deleting legitimate no-data placeholders (e.g.,
#      MODIS Aqua composites before mid-2002, VIIRS burn before 2012) that
#      genuinely have no source pixels.  On --apply, flagged assets are
#      deleted from the release and the matching `upload_*_grid` targets are
#      invalidated so tar_make() re-uploads the current (fixed) local COGs.
#
#      Add --delete-if-local-missing to also flag release placeholders whose
#      LOCAL counterpart is missing (e.g., server-side cleanup happened
#      after the fix).  Legitimate no-data placeholders (local file exists
#      and is also all-NA) are still preserved.
#
# Usage on the server:
#   Rscript recover_rate_limited.R                       # dry-run tar_meta scan
#   Rscript recover_rate_limited.R --apply               # apply tar_meta scan
#   Rscript recover_rate_limited.R --apply --delete-release-assets
#                                                        # also clean release
#                                                        # assets found via
#                                                        # tar_meta scan
#   Rscript recover_rate_limited.R --scan-releases       # dry-run release scan
#   Rscript recover_rate_limited.R --scan-releases --apply
#                                                        # apply release scan
#                                                        # (deletes bad assets +
#                                                        # invalidates branches)
#
# After running with --apply, run tar_make() as usual.
# ============================================================================

suppressPackageStartupMessages({
  library(targets)
})

# Null-coalescing helper (base R has no equivalent as of R 4.3).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# ── Rate-limit helpers ─────────────────────────────────────────────────────
# gh::gh() throws an error whenever the API returns 403 with a rate-limit
# body, which aborts long-running scans mid-flight.  These helpers wrap
# gh::gh() so we can (a) check remaining quota before starting, and
# (b) sleep until reset on 403.  The /rate_limit endpoint itself does NOT
# count against the quota, so pre-flight checks are free.

.gh_rate_reset_wait <- function(token, max_sleep = 4000L) {
  rl <- tryCatch(
    gh::gh("GET /rate_limit", .token = token),
    error = function(e) NULL
  )
  if (is.null(rl)) return(invisible(NULL))
  reset <- rl$resources$core$reset %||% (as.integer(Sys.time()) + 60L)
  wait  <- max(0L, as.integer(reset) - as.integer(Sys.time()) + 5L)
  if (wait > max_sleep) {
    stop("Rate-limit reset is ", wait,
         "s away, which exceeds the max_sleep cap of ", max_sleep,
         "s. Aborting; re-run after the quota resets.", call. = FALSE)
  }
  message("[recover] Rate limit exhausted; sleeping ", wait,
          "s until reset...")
  Sys.sleep(wait)
}

# Wrap a gh::gh() call so it retries once after sleeping when the API
# returns HTTP 403 with a rate-limit message.  All other errors propagate.
gh_call <- function(..., token, max_retries = 2L) {
  attempt <- 0L
  repeat {
    attempt <- attempt + 1L
    res <- tryCatch(gh::gh(..., .token = token),
                    error = function(e) e)
    if (!inherits(res, "error")) return(res)
    msg <- conditionMessage(res)
    is_rate <- grepl("rate limit", msg, ignore.case = TRUE) ||
               grepl("secondary rate", msg, ignore.case = TRUE)
    if (!is_rate || attempt > max_retries) stop(res)
    .gh_rate_reset_wait(token)
  }
}

# Print current rate-limit status (does not count against the quota).
gh_report_rate_limit <- function(token) {
  rl <- tryCatch(gh::gh("GET /rate_limit", .token = token),
                 error = function(e) NULL)
  if (is.null(rl)) return(invisible(NULL))
  core <- rl$resources$core
  reset_utc <- format(as.POSIXct(core$reset, origin = "1970-01-01",
                                 tz = "UTC"),
                      "%Y-%m-%d %H:%M:%S UTC")
  message("[recover] GitHub API quota: ", core$remaining, " / ", core$limit,
          " remaining (resets at ", reset_utc, ")")
  invisible(core)
}

args           <- commandArgs(trailingOnly = TRUE)
apply_changes  <- "--apply" %in% args
delete_release <- "--delete-release-assets" %in% args
scan_releases  <- "--scan-releases" %in% args
delete_if_local_missing <- "--delete-if-local-missing" %in% args

if (!apply_changes) {
  message("[recover] Running in dry-run mode. Re-run with --apply to actually ",
          "delete artifacts and invalidate branches.")
}

# ── 1. Target-specific artifact locations ──────────────────────────────────
# One record per rate-limited task_ids target.  `key_from_sentinel` extracts
# the YYYYMM / YYYYMMDD / elevation key from "rate_limited:<key>".
# `tif_pattern` is a PCRE with a single capture group for the key; used by
# the release-scan mode to map an asset filename back to its parent target
# (so the corresponding branch can be invalidated after asset deletion).
artifact_specs <- list(
  burn_modis_task_ids = list(
    dir   = "data/target_outputs/burndates",
    files = function(k) c(
      paste0("burn_modis_", k, ".tif"),
      paste0("burn_modis_", k, ".skip"),
      paste0("burn_modis_", k, ".parquet")
    ),
    release_tag = "burn_modis_raster",
    tif_pattern = "^burn_modis_(\\d{6})\\.tif$"
  ),
  burn_viirs_task_ids = list(
    dir   = "data/target_outputs/burndates",
    files = function(k) c(
      paste0("burn_viirs_", k, ".tif"),
      paste0("burn_viirs_", k, ".skip"),
      paste0("burn_viirs_", k, ".parquet")
    ),
    release_tag = "burn_viirs_raster",
    tif_pattern = "^burn_viirs_(\\d{6})\\.tif$"
  ),
  vi_modis_task_ids = list(
    dir   = "data/target_outputs/modis_vi",
    files = function(k) c(
      paste0("vi_modis_terra_", k, ".tif"),
      paste0("vi_modis_aqua_",  k, ".tif"),
      paste0("vi_modis_",       k, ".skip"),
      paste0("vi_modis_",       k, ".parquet")
    ),
    release_tag = "vi_modis_raster",
    tif_pattern = "^vi_modis_(?:terra|aqua)_(\\d{8})\\.tif$"
  ),
  vi_viirs_task_ids = list(
    dir   = "data/target_outputs/viirs_vi",
    files = function(k) c(
      paste0("vi_viirs_snpp_",   k, ".tif"),
      paste0("vi_viirs_noaa20_", k, ".tif"),
      paste0("vi_viirs_",        k, ".skip"),
      paste0("vi_viirs_",        k, ".parquet")
    ),
    release_tag = "vi_viirs_raster",
    tif_pattern = "^vi_viirs_(?:snpp|noaa20)_(\\d{8})\\.tif$"
  ),
  elevation_task_id = list(
    dir   = ".",
    files = function(k) character(0),  # elevation.tif lives in _targets/objects; tar_invalidate handles it
    release_tag = NA_character_,
    tif_pattern = NA_character_
  )
)

# ── 2. Scan tar_meta for rate_limited branches ─────────────────────────────
meta <- targets::tar_meta()
task_id_parents <- names(artifact_specs)

# All rows whose parent (dynamic branching parent) is one of the task_ids
# targets, plus the elevation_task_id target itself (not branched).
branch_rows <- meta[!is.na(meta$parent) & meta$parent %in% task_id_parents, ]
elev_row    <- meta[meta$name == "elevation_task_id" &
                    (is.na(meta$parent) | meta$parent == ""), ]

stuck <- list()   # parent -> list(branch_name, key, files)

check_branch <- function(branch_name, parent) {
  v <- tryCatch(targets::tar_read_raw(branch_name), error = function(e) NULL)
  if (is.null(v) || !is.character(v) || length(v) != 1L) return(NULL)
  if (!startsWith(v, "rate_limited:")) return(NULL)

  key   <- sub("^rate_limited:", "", v)
  spec  <- artifact_specs[[parent]]
  files <- if (nchar(key) > 0) file.path(spec$dir, spec$files(key)) else character(0)
  list(branch_name = branch_name, key = key, files = files,
       release_tag = spec$release_tag)
}

for (i in seq_len(nrow(branch_rows))) {
  hit <- check_branch(branch_rows$name[i], branch_rows$parent[i])
  if (!is.null(hit)) {
    stuck[[branch_rows$parent[i]]] <- c(stuck[[branch_rows$parent[i]]], list(hit))
  }
}

# elevation_task_id (singleton, not branched)
if (nrow(elev_row) > 0) {
  hit <- check_branch("elevation_task_id", "elevation_task_id")
  if (!is.null(hit)) {
    stuck[["elevation_task_id"]] <- list(hit)
  }
}

# ── 3. Report tar_meta findings ────────────────────────────────────────────
total_branches <- sum(vapply(stuck, length, integer(1)))
if (total_branches == 0L) {
  message("[recover] No rate_limited task_ids branches found in tar_meta.")
  if (!scan_releases) {
    message("[recover] Nothing to do. Re-run with --scan-releases to also ",
            "check GitHub release assets.")
    quit(save = "no", status = 0)
  }
} else {
  message("[recover] Found ", total_branches,
          " rate_limited task_ids branch(es):")
  for (parent in names(stuck)) {
    keys <- vapply(stuck[[parent]], `[[`, character(1), "key")
    message("  - ", parent, ": ", length(keys), " branch(es) [",
            paste(utils::head(keys, 5), collapse = ", "),
            if (length(keys) > 5) ", ..." else "", "]")
  }
}

# ── 3b. Scan GitHub releases for stale placeholder assets ─────────────────
# When --scan-releases is set, list every .tif asset on the raster releases
# and compare it against the corresponding local COG.  A GitHub asset is
# considered STALE (and eligible for deletion) only when BOTH of the
# following are true:
#
#   (1) The published asset is an all-NA / placeholder COG.  Detected via:
#       (a) file fails to open as a raster; or
#       (b) `terra::metags()` contains "source=no_data" (the marker
#           write_na_cog() sets in get_modis_vi.R / get_viirs_vi.R when it
#           writes a placeholder because AppEEARS returned no source
#           tiles — this happens for both legitimate no-data months AND
#           rate-limited ones); or
#       (c) every band reports zero non-NA cells.
#
#   (2) The corresponding LOCAL .tif exists and is NOT itself a placeholder.
#       This is the discriminator that distinguishes "rate-limited artefact
#       that has since been fixed locally" (delete) from "legitimately no
#       source data for this date/sensor combo, e.g. MODIS Aqua before
#       2002-07 or VIIRS burn before 2012-01" (keep).
#
# Pre-filter by asset size: real MODIS/VIIRS COGs are typically hundreds of
# kB to several MB.  All-NA COGs written with SPARSE_OK=YES are only a few
# kB.  Larger assets are skipped for speed (they are effectively guaranteed
# to contain data).
release_bad <- list()  # tag -> list(list(asset_name, asset_id, key, tag, local_path))
if (scan_releases) {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("--scan-releases requires the 'terra' package.")
  }
  if (!requireNamespace("httr", quietly = TRUE)) {
    stop("--scan-releases requires the 'httr' package.")
  }

  repo       <- Sys.getenv("TAR_GH_RELEASE_REPO", unset = "eco-emma/emma_envdata")
  owner_repo <- strsplit(repo, "/")[[1]]
  gh_token   <- Sys.getenv("GITHUB_PAT", unset = Sys.getenv("GITHUB_TOKEN"))
  if (!nzchar(gh_token)) {
    stop("--scan-releases requires GITHUB_PAT or GITHUB_TOKEN to be set.")
  }

  # Pre-flight rate-limit check: print current status and, if the quota is
  # already exhausted from a previous run, wait for the reset before scanning.
  core <- gh_report_rate_limit(gh_token)
  if (!is.null(core) && isTRUE(core$remaining < 200L)) {
    .gh_rate_reset_wait(gh_token)
    gh_report_rate_limit(gh_token)
  }

  # Any COG larger than this is assumed to hold real data and is skipped.
  # All-NA COGs written with SPARSE_OK=YES are typically ~1-3 kB per band.
  size_probe_bytes <- 200 * 1024L  # 200 kB

  # Helper: decide whether a COG looks like an all-NA placeholder.
  is_placeholder_cog <- function(path) {
    r <- tryCatch(terra::rast(path), error = function(e) NULL)
    if (is.null(r)) return(TRUE)                       # (1a)
    tags <- tryCatch(terra::metags(r), error = function(e) character(0))
    tag_hits <- if (length(tags) == 0L) character(0)
                else if (is.character(tags)) tags
                else unlist(tags, use.names = TRUE)
    if (any(grepl("no_data", tag_hits, fixed = TRUE))) return(TRUE)  # (1b)
    notna <- tryCatch(terra::global(r, "notNA")[, 1],
                      error = function(e) NA_real_)
    isTRUE(all(is.na(notna))) || isTRUE(sum(notna, na.rm = TRUE) == 0)  # (1c)
  }

  # Helper: match an asset filename to (parent, key, local_path).
  match_asset <- function(asset_name) {
    for (parent in names(artifact_specs)) {
      spec <- artifact_specs[[parent]]
      if (is.na(spec$tif_pattern)) next
      m <- regmatches(asset_name, regexec(spec$tif_pattern, asset_name))[[1]]
      if (length(m) == 2L) {
        return(list(
          parent     = parent,
          key        = m[[2]],
          local_path = file.path(spec$dir, asset_name)
        ))
      }
    }
    NULL
  }

  tmp_dir <- tempfile("recover_release_scan_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  release_tags_to_scan <- unique(unlist(lapply(artifact_specs, `[[`, "release_tag")))
  release_tags_to_scan <- release_tags_to_scan[!is.na(release_tags_to_scan)]

  # Running tallies for a summary report at the end of the scan.
  scan_stats <- list()

  message("[recover] Scanning ", length(release_tags_to_scan),
          " GitHub release(s) for stale placeholder COGs...")

  for (tag in release_tags_to_scan) {
    rel <- tryCatch(
      gh_call("GET /repos/{owner}/{repo}/releases/tags/{tag}",
              owner = owner_repo[1], repo = owner_repo[2],
              tag = tag, token = gh_token),
      error = function(e) NULL
    )
    if (is.null(rel)) {
      message("  - release '", tag, "' not found; skipping")
      next
    }
    assets <- gh_call(
      "GET /repos/{owner}/{repo}/releases/{release_id}/assets",
      owner = owner_repo[1], repo = owner_repo[2],
      release_id = rel$id, .limit = Inf, token = gh_token
    )
    tif_assets <- Filter(function(a) grepl("\\.tif$", a$name), assets)
    probe_assets <- Filter(function(a) isTRUE(a$size <= size_probe_bytes),
                           tif_assets)
    message("  - release '", tag, "': ", length(tif_assets),
            " .tif asset(s), probing ", length(probe_assets),
            " small candidate(s) (\u2264 ",
            format(size_probe_bytes, big.mark = ","), " bytes)")

    stats <- list(placeholders_on_release = 0L,
                  local_missing           = 0L,
                  local_also_placeholder  = 0L,
                  stale_flagged           = 0L)

    for (a in probe_assets) {
      dest <- file.path(tmp_dir, a$name)

      # Download via the release's browser_download_url rather than
      # `GET /releases/assets/{id}` with `Accept: application/octet-stream`.
      # The browser URL redirects to a signed S3 CDN link and does NOT count
      # against the 5000/hr REST API quota, so we can probe thousands of
      # small assets without tripping the primary or secondary rate limits.
      dl_url <- a$browser_download_url
      ok <- FALSE
      if (!is.null(dl_url) && nzchar(dl_url)) {
        ok <- tryCatch({
          r <- httr::GET(
            dl_url,
            # Public releases don't require auth here; the token is harmless
            # if the repo is private and required if so.
            httr::add_headers(Authorization = paste("Bearer", gh_token)),
            httr::write_disk(dest, overwrite = TRUE)
          )
          !httr::http_error(r)
        }, error = function(e) FALSE)
      }

      if (!ok) {
        message("    ! failed to download probe: ", a$name)
        next
      }

      if (!is_placeholder_cog(dest)) {
        unlink(dest)
        next
      }
      stats$placeholders_on_release <- stats$placeholders_on_release + 1L

      # Compare against local file to distinguish stale vs. legitimate.
      parsed <- match_asset(a$name)
      local_here <- !is.null(parsed) && file.exists(parsed$local_path)
      if (!local_here) {
        stats$local_missing <- stats$local_missing + 1L
        if (!delete_if_local_missing) {
          unlink(dest)
          next
        }
        # Fall through: flag as stale despite missing local file.
      } else if (is_placeholder_cog(parsed$local_path)) {
        # Local file is also all-NA — the placeholder is legitimate (no
        # source data for this date/sensor combination).  Leave the release
        # alone regardless of --delete-if-local-missing.
        stats$local_also_placeholder <- stats$local_also_placeholder + 1L
        unlink(dest)
        next
      }

      # Flagged stale: release placeholder AND (local is real data, OR local
      # is missing and --delete-if-local-missing is set).
      stats$stale_flagged <- stats$stale_flagged + 1L
      release_bad[[tag]] <- c(release_bad[[tag]], list(list(
        asset_name = a$name,
        asset_id   = a$id,
        size       = a$size,
        parent     = if (is.null(parsed)) NA_character_ else parsed$parent,
        key        = if (is.null(parsed)) NA_character_ else parsed$key,
        local_path = if (is.null(parsed)) NA_character_ else parsed$local_path,
        tag        = tag
      )))
      unlink(dest)
    }

    scan_stats[[tag]] <- stats
    message("      placeholders on release: ", stats$placeholders_on_release,
            " | local missing: ",              stats$local_missing,
            " | local also placeholder: ",     stats$local_also_placeholder,
            " | flagged stale: ",              stats$stale_flagged)
  }

  n_bad <- sum(vapply(release_bad, length, integer(1)))
  if (n_bad == 0L) {
    message("[recover] Release scan complete: no stale placeholder .tif ",
            "assets found (all release placeholders match local placeholders ",
            "and are therefore legitimate).")
  } else {
    message("[recover] Release scan complete: ", n_bad,
            " stale .tif asset(s) flagged (release placeholder but local is real data):")
    for (tag in names(release_bad)) {
      names_bad <- vapply(release_bad[[tag]], `[[`, character(1), "asset_name")
      message("  - ", tag, ": ", length(names_bad), " asset(s) [",
              paste(utils::head(names_bad, 5), collapse = ", "),
              if (length(names_bad) > 5) ", ..." else "", "]")
    }
  }
}

# ── 4. Collect on-disk artifacts to remove ─────────────────────────────────
all_files <- unlist(lapply(stuck, function(bs) {
  unlist(lapply(bs, `[[`, "files"))
}), use.names = FALSE)
if (is.null(all_files)) all_files <- character(0)
existing_files <- unique(all_files[file.exists(all_files)])

if (length(all_files) > 0L) {
  message("[recover] Local artifacts to delete: ", length(existing_files),
          " (of ", length(unique(all_files)), " candidate paths)")
  if (length(existing_files) > 0 && length(existing_files) <= 20) {
    message("  - ", paste(existing_files, collapse = "\n  - "))
  } else if (length(existing_files) > 20) {
    message("  (showing first 5) - ",
            paste(utils::head(existing_files, 5), collapse = "\n  - "))
  }
}

# ── 5. Collect release assets to remove ────────────────────────────────────
# Two sources feed into the deletion list:
#   (a) tar_meta scan, when --delete-release-assets is set: derive expected
#       .tif filenames from each stuck branch's key.
#   (b) release scan (--scan-releases): the concrete asset IDs already
#       confirmed as all-NA placeholders.  These come with `asset_id`, so we
#       don't need a second name-lookup round trip against GitHub.
release_assets_to_delete <- list()   # tag -> character() (names)
release_asset_ids        <- list()   # tag -> integer()   (matching IDs)
release_bad_tags         <- character(0)  # release tags with confirmed bad assets

if (delete_release) {
  # Group release-asset names by release tag from tar_meta scan
  for (parent in names(stuck)) {
    tag <- artifact_specs[[parent]]$release_tag
    if (is.na(tag)) next
    for (bs in stuck[[parent]]) {
      # Only the ".tif" files land on the raster releases; keep parquet/skip
      # off the raster tag list. This matches the upload_*_grid targets.
      tif_names <- basename(grep("\\.tif$", bs$files, value = TRUE))
      release_assets_to_delete[[tag]] <- c(release_assets_to_delete[[tag]],
                                           tif_names)
    }
  }
  for (tag in names(release_assets_to_delete)) {
    release_assets_to_delete[[tag]] <- unique(release_assets_to_delete[[tag]])
  }
}

if (scan_releases) {
  # Fold results from release scan into the deletion list.  Use asset IDs
  # captured during scanning so we can DELETE without re-listing.
  for (tag in names(release_bad)) {
    ids   <- vapply(release_bad[[tag]], `[[`, integer(1),   "asset_id")
    names <- vapply(release_bad[[tag]], `[[`, character(1), "asset_name")
    release_assets_to_delete[[tag]] <- unique(c(release_assets_to_delete[[tag]],
                                                names))
    release_asset_ids[[tag]]        <- unique(c(release_asset_ids[[tag]], ids))
    if (length(ids) > 0L) release_bad_tags <- unique(c(release_bad_tags, tag))
  }
}

n_release <- sum(vapply(release_assets_to_delete, length, integer(1)))
if (n_release > 0L) {
  message("[recover] Release assets to delete: ", n_release,
          " across ", length(release_assets_to_delete), " release(s)")
}

# Which upload_*_grid targets need re-running because their release assets
# were deleted?  Map release tag → upload target name.
upload_targets_for_tag <- c(
  burn_modis_raster = "upload_burn_modis_grid",
  burn_viirs_raster = "upload_burn_viirs_grid",
  vi_modis_raster   = "upload_vi_modis_grid",
  vi_viirs_raster   = "upload_vi_viirs_grid"
)
upload_targets_to_invalidate <- unname(
  upload_targets_for_tag[intersect(names(upload_targets_for_tag),
                                   release_bad_tags)]
)
if (length(upload_targets_to_invalidate) > 0L) {
  message("[recover] Upload targets to invalidate: ",
          paste(upload_targets_to_invalidate, collapse = ", "))
}

# ── 6. Apply ───────────────────────────────────────────────────────────────
if (!apply_changes) {
  message("\n[recover] Dry-run complete. Re-run with --apply to execute.")
  quit(save = "no", status = 0)
}

# 6a. Delete local files
for (f in existing_files) {
  ok <- suppressWarnings(file.remove(f))
  if (!isTRUE(ok)) message("  ! failed to delete: ", f)
}
if (length(existing_files) > 0L) {
  message("[recover] Deleted ", length(existing_files), " local artifact(s).")
}

# 6b. Delete release assets (from tar_meta scan and/or --scan-releases)
if (n_release > 0L) {
  repo <- Sys.getenv("TAR_GH_RELEASE_REPO", unset = "eco-emma/emma_envdata")
  owner_repo <- strsplit(repo, "/")[[1]]

  # Resolve the GH token the same way tar_release_storage.R does.
  gh_token <- Sys.getenv("GITHUB_PAT", unset = Sys.getenv("GITHUB_TOKEN"))
  if (!nzchar(gh_token)) {
    warning("No GITHUB_PAT / GITHUB_TOKEN found; skipping release-asset deletion.",
            call. = FALSE)
  } else {
    for (tag in names(release_assets_to_delete)) {
      names_to_del <- release_assets_to_delete[[tag]]
      if (length(names_to_del) == 0L) next

      # Prefer IDs captured during --scan-releases (avoids re-listing).
      known_ids <- release_asset_ids[[tag]]
      hits_by_id <- if (length(known_ids) > 0L) {
        lapply(known_ids, function(id) list(id = id, name = NA_character_))
      } else list()

      # For names not covered by known_ids (i.e. from tar_meta path), resolve
      # via the release assets endpoint.
      needs_lookup <- setdiff(names_to_del,
                              vapply(release_bad[[tag]] %||% list(),
                                     `[[`, character(1), "asset_name"))
      if (length(needs_lookup) > 0L) {
        rel <- tryCatch(
          gh_call("GET /repos/{owner}/{repo}/releases/tags/{tag}",
                  owner = owner_repo[1], repo = owner_repo[2],
                  tag = tag, token = gh_token),
          error = function(e) NULL
        )
        if (is.null(rel)) {
          message("  ! release '", tag, "' not found; skipping name lookup")
        } else {
          assets <- gh_call(
            "GET /repos/{owner}/{repo}/releases/{release_id}/assets",
            owner = owner_repo[1], repo = owner_repo[2],
            release_id = rel$id, .limit = Inf, token = gh_token
          )
          extra <- Filter(function(a) a$name %in% needs_lookup, assets)
          hits_by_id <- c(hits_by_id,
                          lapply(extra, function(a) list(id = a$id,
                                                         name = a$name)))
        }
      }

      deleted <- 0L
      for (h in hits_by_id) {
        tryCatch({
          gh_call("DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}",
                  owner = owner_repo[1], repo = owner_repo[2],
                  asset_id = h$id, token = gh_token)
          deleted <- deleted + 1L
        }, error = function(e) {
          message("  ! failed to delete release asset ",
                  if (is.na(h$name)) as.character(h$id) else h$name,
                  ": ", conditionMessage(e))
        })
      }
      message("  - release '", tag, "': deleted ", deleted, " asset(s)")
    }
  }
}

# 6c. Invalidate task_ids branches (cascades to downstream on next tar_make)
all_branches <- unlist(lapply(stuck, function(bs) {
  vapply(bs, `[[`, character(1), "branch_name")
}), use.names = FALSE)
if (length(all_branches) > 0L) {
  targets::tar_invalidate(any_of(all_branches))
  message("[recover] Invalidated ", length(all_branches),
          " task_ids branch(es).")
}

# 6d. Invalidate upload_*_grid targets so tar_make() re-uploads the
# now-cleaned local files back to the release.  Only touch targets that
# actually exist in the current pipeline metadata to avoid errors when the
# pipeline layout changes.
if (length(upload_targets_to_invalidate) > 0L) {
  existing_targets <- meta$name
  to_hit <- intersect(upload_targets_to_invalidate, existing_targets)
  if (length(to_hit) > 0L) {
    targets::tar_invalidate(any_of(to_hit))
    message("[recover] Invalidated ", length(to_hit),
            " upload target(s): ", paste(to_hit, collapse = ", "))
  }
}

message("\n[recover] Done. Run tar_make() next to re-submit and download.")
