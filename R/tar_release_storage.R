# ---------------------------------------------------------------------------
# Internal helper: resolve a GitHub token without triggering gh package format
# validation.  gh::gh_token() rejects ghs_ GitHub Actions service tokens when
# they appear in GITHUB_PAT, and newer gh versions may also validate
# GITHUB_TOKEN.  Reading GITHUB_TOKEN directly bypasses all validation.
# Falls back to gh::gh_token() for interactive use (GITHUB_PAT / credential
# store) when GITHUB_TOKEN is not set.
# ---------------------------------------------------------------------------
.gh_token <- function() {
  tok <- Sys.getenv("GITHUB_TOKEN")
  if (nzchar(tok)) return(tok)
  gh::gh_token()
}

# ---------------------------------------------------------------------------
# Internal helper: verify a downloaded file can actually be opened.
# Returns TRUE if the file passes its format-specific integrity check,
# FALSE on any read error. Used by tar_download_github_release() to avoid
# silently accepting truncated or corrupted downloads.
# ---------------------------------------------------------------------------
.check_file_integrity <- function(path) {
  ext <- tolower(tools::file_ext(path))
  tryCatch({
    switch(ext,
      parquet = { arrow::open_dataset(path); TRUE },
      tif     = ,
      tiff    = { terra::rast(path);          TRUE },
      nc      = {
        # NC assets in the targets-cache may be actual NetCDF files OR may be
        # format="file" RDS path-string wrappers (e.g. elevation.nc). Try
        # readRDS first; if it returns a character string, the file is valid.
        rds_val <- tryCatch(readRDS(path), error = function(e) NULL)
        if (is.character(rds_val)) return(TRUE)
        terra::rast(path)
        TRUE
      },
      gpkg    = { sf::st_read(path, quiet = TRUE); TRUE },
      rds     = { readRDS(path);               TRUE },
      # For binary objects with no extension (targets rds objects): verify
      # the file is non-empty and does NOT look like a GitHub API error response
      # (which is a JSON object starting with '{', ASCII 0x7B).
      {
        if (!file.exists(path) || file.size(path) == 0) return(FALSE)
        con <- file(path, "rb")
        fb  <- readBin(con, raw(), n = 1L)
        close(con)
        if (length(fb) == 1L && fb[[1L]] == as.raw(0x7b)) return(FALSE)  # JSON
        TRUE
      }
    )
  }, error = function(e) FALSE)
}

#' Download targets from GitHub Release
#' @description Download locally stored targets from GitHub releases (useful for GitHub Actions)
#' @param repo Repository in "owner/repo" format (default from environment or "AdamWilsonLab/emma_envdata")
#' @param tag Release tag to store objects (default from environment or "targets-cache")
#' @param cache_dir Cache directory (default: "_targets/cache")
#' @param which_targets Optional vector of specific target names to download
#' @param verbose Logical for progress messages
#' @details Call this at the start of tar_make() in update mode to download targets
#' @export
tar_download_github_release <- function(
  repo = NULL,
  tag = NULL,
  cache_dir = "_targets/user/cache",
  which_targets = NULL,
  verbose = TRUE
) {
  # Use environment variables as fallback, but allow explicit parameters
  repo <- repo %||% Sys.getenv("TAR_GH_RELEASE_REPO") %||% "AdamWilsonLab/emma_envdata"
  tag <- tag %||% Sys.getenv("TAR_GH_RELEASE_TAG") %||% "targets-cache"
  cache_dir <- cache_dir %||% Sys.getenv("TAR_GH_RELEASE_CACHE_DIR") %||% "_targets/cache"
  objects_dir <- "_targets/objects"

  if (!nzchar(repo) || !nzchar(tag)) {
    stop("GitHub release configuration not set. Provide repo and tag parameters or set environment variables.")
  }

  # Resolve token once and pass explicitly to all API calls.
  # Use .gh_token() rather than gh::gh_token() directly to bypass gh package
  # format validation, which rejects ghs_ GitHub Actions service tokens.
  .token <- .gh_token()
  owner_repo <- strsplit(repo, "/")[[1]]

  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(objects_dir, recursive = TRUE, showWarnings = FALSE)

  # Fetch release and full asset list via direct gh::gh() calls.
  # piggyback::pb_list() / pb_download() call gh::gh_token() internally and
  # have been observed to fail silently (returning empty results) even when
  # the token is valid — direct API calls are more reliable.
  release_gh <- tryCatch(
    gh::gh(
      "GET /repos/{owner}/{repo}/releases/tags/{tag}",
      owner = owner_repo[1], repo = owner_repo[2], tag = tag,
      .token = .token
    ),
    error = function(e) NULL
  )

  if (is.null(release_gh)) {
    if (verbose) message("[tar_github_release] Release '", tag, "' not found, skipping download")
    return(invisible(NULL))
  }

  asset_list <- tryCatch(
    gh::gh(
      "GET /repos/{owner}/{repo}/releases/{release_id}/assets",
      owner = owner_repo[1], repo = owner_repo[2],
      release_id = release_gh$id, .limit = Inf, .token = .token
    ),
    error = function(e) list()
  )

  assets <- if (length(asset_list) > 0) {
    data.frame(
      file_name = vapply(asset_list, `[[`, character(1), "name"),
      id        = vapply(asset_list, `[[`, numeric(1),   "id"),
      size      = vapply(asset_list, `[[`, numeric(1),   "size"),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(file_name = character(0), id = integer(0), size = integer(0))
  }

  if (verbose) message("[tar_github_release] Found ", nrow(assets), " assets on GitHub release")

  # Helper: download a single asset by ID to a local path using httr (no piggyback).
  .download_asset <- function(asset_id, dest_path) {
    r <- httr::RETRY(
      verb  = "GET",
      url   = sprintf("https://api.github.com/repos/%s/%s/releases/assets/%s",
                      owner_repo[1], owner_repo[2], asset_id),
      httr::add_headers(Authorization  = paste("token", .token),
                        Accept         = "application/octet-stream"),
      httr::write_disk(dest_path, overwrite = TRUE),
      times = 3,
      terminate_on = c(401, 403, 404)
    )
    httr::stop_for_status(r)
    invisible(dest_path)
  }

  # Always restore _targets/meta/meta from the release so that the meta and
  # objects are consistent with each other (both from the same server run).
  meta_dest   <- "_targets/meta/meta"
  meta_cached <- file.path(cache_dir, "_targets_meta")
  meta_row    <- assets[assets$file_name == "_targets_meta", ]
  if (nrow(meta_row) > 0) {
    tryCatch({
      .download_asset(meta_row$id[1], meta_cached)
      if (file.exists(meta_cached) && file.size(meta_cached) > 0) {
        dir.create("_targets/meta", recursive = TRUE, showWarnings = FALSE)
        file.copy(meta_cached, meta_dest, overwrite = TRUE)
        if (verbose) message("[tar_github_release] Restored targets meta")
      }
    }, error = function(e) {
      if (verbose) message("[tar_github_release] Failed to download targets meta: ", conditionMessage(e))
    })
  } else {
    if (verbose) message("[tar_github_release] No targets meta in release (first run?)")
  }

  # Exclude _targets_meta from the per-object download loop
  assets <- assets[assets$file_name != "_targets_meta", ]
  
  # Filter assets if specific targets requested
  if (!is.null(which_targets)) {
    assets <- assets[assets$file_name %in% which_targets |
                       sapply(assets$file_name, function(n) any(startsWith(n, which_targets))), ]
  }
  
  if (is.null(assets) || nrow(assets) == 0) {
    if (verbose) message("[tar_github_release] No assets to download")
    return(invisible(NULL))
  }
  
  # Download each asset
  for (i in seq_len(nrow(assets))) {
    asset_name  <- assets$file_name[i]
    target_name <- asset_name   # bare name used for _targets/objects/ path
    local_path  <- file.path(objects_dir, target_name)
    cached_path <- file.path(cache_dir, asset_name)
    # All assets in the release are regular _targets/objects/ files (no file-format
    # workspace handling needed on download — format="file" targets store their
    # path string as an RDS in _targets/objects/ just like any other target).
    is_file_format <- FALSE

    # NOTE: no early-exit based on whether the object already exists locally.
    # A previous CI run may have left objects with different branch hashes than
    # the server release; keeping those would make the meta (always from the
    # server release) inconsistent with the objects and force re-runs.
    # The _targets/user/cache/ check below avoids redundant GitHub downloads.

    # Download to cache if not already there, with retry + integrity check
    if (!file.exists(cached_path) || !.check_file_integrity(cached_path)) {
      if (file.exists(cached_path)) {
        if (verbose) message("[tar_github_release] Cached file failed integrity check, re-downloading: ", asset_name)
        file.remove(cached_path)
      } else {
        if (verbose) message("[tar_github_release] Downloading: ", asset_name)
      }
      max_attempts <- 5
      for (attempt in 1:max_attempts) {
        asset_row <- assets[assets$file_name == asset_name, ]
        tryCatch({
          .download_asset(asset_row$id[1], cached_path)
        }, error = function(e) {
          if (verbose) message("[tar_github_release] Download attempt ", attempt, " error: ", conditionMessage(e))
        })
        # Validate the file — retry if corrupt or missing
        if (.check_file_integrity(cached_path)) {
          if (verbose) message("[tar_github_release] Downloaded and verified: ", asset_name)
          break
        } else {
          if (attempt < max_attempts) {
            if (verbose) message("[tar_github_release] Integrity check failed (attempt ", attempt, "), retrying...")
            if (file.exists(cached_path)) file.remove(cached_path)
            Sys.sleep(2)
          } else {
            warning("[tar_github_release] Failed to download valid file after ", max_attempts, " attempts: ", asset_name)
          }
        }
      }
    } else {
      if (verbose) message("[tar_github_release] Already cached: ", asset_name)
    }
    
    # Copy from cache to appropriate target location — only if the cached file
    # passed integrity validation (guards against GitHub API error JSON responses
    # that were saved when the release asset was missing or auth failed).
    if (file.exists(cached_path) && .check_file_integrity(cached_path)) {
      if (is_file_format) {
        # For file-format targets: 
        # 1. Copy actual file to _targets/workspaces/ (where targets expects it)
        # 2. Copy to data/target_outputs/ (for user access)
        # 3. Create RDS wrapper in _targets/objects/ pointing to workspaces location
        
        ws_dir <- "_targets/workspaces"
        dir.create(ws_dir, recursive = TRUE, showWarnings = FALSE)
        ws_path <- file.path(ws_dir, asset_name)
        file.copy(cached_path, ws_path, overwrite = TRUE)
        
        # Also copy to data/target_outputs/ for user access
        out_dir <- "data/target_outputs"
        dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
        out_path <- file.path(out_dir, asset_name)
        file.copy(cached_path, out_path, overwrite = TRUE)
        
        # Create RDS wrapper in _targets/objects/ ONLY if the rds object is not already there.
        # The bare-name asset (e.g. "elevation") is the authoritative rds object.
        # The .ext asset (e.g. "elevation.nc") is just the data file — overwriting the already-
        # restored rds object with an RDS path causes a hash mismatch and forces re-runs.
        obj_dir <- "_targets/objects"
        dir.create(obj_dir, recursive = TRUE, showWarnings = FALSE)
        obj_path <- file.path(obj_dir, target_name)
        if (!file.exists(obj_path)) {
          saveRDS(ws_path, obj_path)
          if (verbose) message("[tar_github_release] Restored file-format target: ", target_name)
        } else {
          if (verbose) message("[tar_github_release] Skipped RDS write (rds object already present): ", target_name)
        }
      } else {
        # Regular object file: copy to _targets/objects/
        obj_dir <- "_targets/objects"
        dir.create(obj_dir, recursive = TRUE, showWarnings = FALSE)
        obj_path <- file.path(obj_dir, target_name)
        file.copy(cached_path, obj_path, overwrite = TRUE)
        if (verbose) message("[tar_github_release] Restored: ", target_name)
      }
    }
  }
  
  if (verbose) message("[tar_github_release] Download complete")
  invisible(NULL)
}

#' Upload targets to GitHub Release after tar_make() completes
#' @description Upload locally stored targets to GitHub releases
#' @param repo Repository in "owner/repo" format (default from environment or "AdamWilsonLab/emma_envdata")
#' @param tag Release tag to store objects (default from environment or "targets-cache")
#' @param format Serialization format: "rds" or "parquet" (default: "rds")
#' @param cache_dir Cache directory (default: "_targets/cache")
#' @param which_targets Optional vector of specific target names to upload
#' @param verbose Logical for progress messages
#' @details Call this after tar_make() to upload all targets
#' @export
tar_upload_github_release <- function(
  repo = NULL,
  tag = NULL,
  format = "rds",
  cache_dir = "_targets/cache",
  which_targets = NULL,
  verbose = TRUE
) {
  # Use environment variables as fallback, but allow explicit parameters
  repo <- repo %||% Sys.getenv("TAR_GH_RELEASE_REPO") %||% "AdamWilsonLab/emma_envdata"
  tag <- tag %||% Sys.getenv("TAR_GH_RELEASE_TAG") %||% "targets-cache"
  cache_dir <- cache_dir %||% Sys.getenv("TAR_GH_RELEASE_CACHE_DIR") %||% "_targets/cache"

  if (!nzchar(repo) || !nzchar(tag)) {
    stop("GitHub release configuration not set. Provide repo and tag parameters or set environment variables.")
  }

  # Resolve token and repo parts early — needed for all gh::gh() calls below.
  # Use .gh_token() to bypass gh package format validation for ghs_ tokens.
  .token     <- .gh_token()
  owner_repo <- strsplit(repo, "/")[[1]]

  # Ensure release exists.
  # Use gh::gh() directly (not piggyback) so we can pass .token explicitly;
  # piggyback::pb_releases() and pb_new_release() call gh::gh_token() internally
  # regardless of the .token parameter, which fails with ghs_ service tokens.
  existing_releases <- tryCatch({
    rels <- gh::gh(
      "GET /repos/{owner}/{repo}/releases",
      owner = owner_repo[1], repo = owner_repo[2],
      .limit = Inf, .token = .token
    )
    data.frame(tag_name = vapply(rels, `[[`, character(1), "tag_name"),
               stringsAsFactors = FALSE)
  }, error = function(e) data.frame(tag_name = character(0)))

  if (!tag %in% existing_releases$tag_name) {
    if (verbose) message("[tar_github_release] Creating release: ", tag)
    gh::gh(
      "POST /repos/{owner}/{repo}/releases",
      owner      = owner_repo[1], repo = owner_repo[2],
      tag_name   = tag,
      name       = tag,
      prerelease = TRUE,
      .token     = .token
    )
    Sys.sleep(3)  # let GitHub propagate before first upload
  }

  # Get metadata to find file-format target paths
  meta_df <- tryCatch({
    tar_meta()
  }, error = function(e) {
    if (verbose) message("[tar_github_release] Could not read targets metadata")
    data.frame(name = character(0), format = character(0), path = list())
  })

  # Fetch the release and its assets directly via gh (no caching layer).
  # This avoids piggyback memoisation issues entirely after release creation.
  release_gh <- tryCatch(
    gh::gh(
      "GET /repos/{owner}/{repo}/releases/tags/{tag}",
      owner = owner_repo[1], repo = owner_repo[2], tag = tag,
      .token = .token
    ),
    error = function(e) stop("[tar_github_release] Release '", tag, "' not accessible: ", conditionMessage(e))
  )
  upload_url_base <- sub("\\{.*", "", release_gh$upload_url)

  asset_list <- tryCatch(
    gh::gh(
      "GET /repos/{owner}/{repo}/releases/{release_id}/assets",
      owner = owner_repo[1], repo = owner_repo[2],
      release_id = release_gh$id, .limit = Inf, .token = .token
    ),
    error = function(e) list()
  )
  remote_assets <- if (length(asset_list) > 0) {
    data.frame(
      file_name = vapply(asset_list, `[[`, character(1), "name"),
      id        = vapply(asset_list, `[[`, numeric(1),   "id"),
      size      = vapply(asset_list, `[[`, numeric(1),   "size"),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(file_name = character(0), id = integer(0), size = integer(0))
  }

  # One-time cleanup: delete any legacy workspace assets ({name}.{ext}) whose bare
  # name also exists as an asset. These were uploaded by older code from
  # _targets/workspaces/ and are debug environments, not real data files.
  legacy_mask <- grepl("\\.[^.]+$", remote_assets$file_name) &
    remote_assets$file_name != "_targets_meta"
  if (any(legacy_mask)) {
    legacy_assets <- remote_assets[legacy_mask, ]
    bare_names    <- sub("\\.[^.]+$", "", legacy_assets$file_name)
    has_bare      <- bare_names %in% remote_assets$file_name
    for (i in which(has_bare)) {
      if (verbose) message("[tar_github_release] Deleting legacy workspace asset: ", legacy_assets$file_name[i])
      tryCatch(
        gh::gh("DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}",
               owner = owner_repo[1], repo = owner_repo[2],
               asset_id = legacy_assets$id[i], .token = .token),
        error = function(e) {
          if (verbose) message("[tar_github_release] Could not delete legacy asset: ", conditionMessage(e))
        })
      Sys.sleep(0.5)
    }
    remote_assets <- remote_assets[!(remote_assets$file_name %in% legacy_assets$file_name[has_bare]), , drop = FALSE]
  }

  # Download the remote _targets_meta (a small file) and build a name → data-hash
  # lookup. Used by the objects upload loop to skip assets whose targets hash
  # matches the last uploaded meta — a reliable content-equality check that does
  # not depend on byte-count coincidences in serialisation.
  remote_meta_hashes <- tryCatch({
    meta_row <- remote_assets[remote_assets$file_name == "_targets_meta", ]
    if (nrow(meta_row) == 0) NULL  # no remote meta yet — will upload all objects

    temp_store    <- tempfile(pattern = "tar_upload_meta_")
    temp_meta_dir <- file.path(temp_store, "meta")
    dir.create(temp_meta_dir, recursive = TRUE, showWarnings = FALSE)
    temp_meta_path <- file.path(temp_meta_dir, "meta")

    r <- httr::GET(
      sprintf("https://api.github.com/repos/%s/%s/releases/assets/%s",
              owner_repo[1], owner_repo[2], meta_row$id[1]),
      httr::add_headers(Authorization = paste("token", .token),
                        Accept = "application/octet-stream"),
      httr::write_disk(temp_meta_path, overwrite = TRUE)
    )
    httr::stop_for_status(r)

    remote_df <- targets::tar_meta(store = temp_store)
    unlink(temp_store, recursive = TRUE)
    if (verbose) message("[tar_github_release] Fetched remote meta (",
                         nrow(remote_df), " targets) for hash comparison")
    setNames(remote_df$data, remote_df$name)
  }, error = function(e) {
    if (verbose) message("[tar_github_release] Could not fetch remote meta for hash comparison ",
                         "(will upload all objects): ", conditionMessage(e))
    NULL
  })

  # Get list of local target files
  if (is.null(which_targets)) {
    # Get all targets from _targets/objects/ (regular objects).
    # Exclude _targets_meta — it is a cached copy from the last download and is
    # uploaded separately (and authoritatively) from _targets/meta/meta at the
    # end of this function. Uploading it here too causes a GitHub 422 conflict.
    regular_files <- list.files("_targets/objects", full.names = TRUE, recursive = FALSE)
    regular_files <- regular_files[basename(regular_files) != "_targets_meta"]
    # Note: _targets/workspaces/ files are debug environments, not target values.
    # format="file" targets store the path string in _targets/objects/ (rds-serialized).
    # Uploading workspace files causes integrity check failures on download.
    local_files <- regular_files
    if (verbose) message("[tar_github_release] Found ", length(local_files), " local target files to upload")
  } else {
    # Find specific targets in _targets/objects/ only
    regular_files <- character(0)
    for (target in which_targets) {
      obj_file <- file.path("_targets/objects", target)
      if (file.exists(obj_file)) {
        regular_files <- c(regular_files, obj_file)
      }
    }
    local_files <- regular_files
  }
  
  if (length(local_files) == 0) {
    message("[tar_github_release] No targets to upload")
    return(invisible(NULL))
  }
  
  # Upload each file
  for (local_file in local_files) {
    target_name <- basename(local_file)
    upload_name <- target_name

      # Skip upload if the targets content hash matches the remote meta.
      # This is the authoritative content-equality check: same hash means the
      # object the server produced is identical to what was last uploaded,
      # regardless of byte-count coincidences in serialisation.
      exists_on_github <- any(remote_assets$file_name == upload_name)
      if (exists_on_github) {
        local_hash <- meta_df$data[meta_df$name == target_name]
        if (!is.null(remote_meta_hashes) &&
            length(local_hash) == 1 && !is.na(local_hash) &&
            target_name %in% names(remote_meta_hashes) &&
            identical(local_hash, remote_meta_hashes[[target_name]])) {
          if (verbose) message("[tar_github_release] Skipping (hash unchanged): ", upload_name)
          next
        }
      }

      if (verbose) message("[tar_github_release] Uploading object: ", target_name)

      # Delete existing asset if present
      if (exists_on_github) {
        if (verbose) message("[tar_github_release] Deleting old asset: ", upload_name)
        tryCatch({
          old_id <- remote_assets$id[remote_assets$file_name == upload_name]
          gh::gh("DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}",
                 owner = owner_repo[1], repo = owner_repo[2],
                 asset_id = old_id[1], .token = .token)
          Sys.sleep(1)
        }, error = function(e) {
          if (verbose) message("[tar_github_release] Could not delete old asset: ", conditionMessage(e))
        })
      }

      # Upload directly via httr (bypasses all piggyback caching)
      tryCatch({
        r <- httr::RETRY(
          verb = "POST",
          url  = upload_url_base,
          query = list(name = upload_name),
          httr::add_headers(Authorization = paste("token", .token)),
          body = httr::upload_file(local_file),
          times = 3,
          terminate_on = c(400, 401, 403, 404, 422)
        )
        httr::stop_for_status(r)
        if (verbose) message("[tar_github_release] Uploaded: ", upload_name)
        Sys.sleep(0.5)
      }, error = function(e) {
        warning("[tar_github_release] Failed to upload ", upload_name, ": ", conditionMessage(e))
      })
  }
  
  # Upload _targets/meta/meta so CI can restore the pipeline state and avoid
  # re-running targets that were already completed on the server.
  meta_path <- "_targets/meta/meta"
  if (file.exists(meta_path)) {
    upload_name <- "_targets_meta"
    if (verbose) message("[tar_github_release] Uploading targets meta: ", meta_path)
    # Delete old asset if present
    if (any(remote_assets$file_name == upload_name)) {
      tryCatch({
        old_id <- remote_assets$id[remote_assets$file_name == upload_name]
        gh::gh("DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}",
               owner = owner_repo[1], repo = owner_repo[2],
               asset_id = old_id[1], .token = .token)
        Sys.sleep(1)
      }, error = function(e) {
        if (verbose) message("[tar_github_release] Could not delete old meta asset: ", conditionMessage(e))
      })
    }
    tryCatch({
      r <- httr::RETRY(
        verb  = "POST",
        url   = upload_url_base,
        query = list(name = upload_name),
        httr::add_headers(Authorization = paste("token", .token)),
        body  = httr::upload_file(meta_path),
        times = 3,
        terminate_on = c(400, 401, 403, 404, 422)
      )
      httr::stop_for_status(r)
      if (verbose) message("[tar_github_release] Uploaded targets meta")
    }, error = function(e) {
      warning("[tar_github_release] Failed to upload targets meta: ", conditionMessage(e))
    })
  } else {
    if (verbose) message("[tar_github_release] No targets meta file found, skipping")
  }

  if (verbose) message("[tar_github_release] Upload complete")
  invisible(NULL)
}

# ============================================================================
# GitHub release asset presence check (used by idempotent submit functions)
# ============================================================================

# Session-level cache so repeated calls within one tar_make() worker don't
# repeat the API call for the same release tag.
.gh_release_asset_cache <- new.env(parent = emptyenv())

#' Check whether a named asset exists on a GitHub release
#'
#' @param repo         "owner/repo" string.
#' @param release_tag  Release tag string (e.g. "vi_modis_dynamic_raster").
#' @param asset_name   File name to look for (e.g. "vi_modis_202601_terra.nc").
#' @param verbose      Print a message when the release is fetched from GitHub.
#' @return Logical scalar.
#' @export
gh_release_has_asset <- function(repo, release_tag, asset_name, verbose = FALSE) {
  # Populate cache for this release tag if not already fetched this session
  if (!exists(release_tag, envir = .gh_release_asset_cache, inherits = FALSE)) {
    token      <- .gh_token()
    owner_repo <- strsplit(repo, "/")[[1]]
    asset_names <- tryCatch({
      if (verbose) message("[gh_release_has_asset] Fetching asset list for release: ", release_tag)
      # Step 1: get release metadata (id, etc.)
      rel <- gh::gh(
        "GET /repos/{owner}/{repo}/releases/tags/{tag}",
        owner  = owner_repo[1],
        repo   = owner_repo[2],
        tag    = release_tag,
        .token = token
      )
      # Step 2: fetch ALL assets via the paginated assets endpoint.
      # The releases-by-tag endpoint embeds only the first 30 assets in its
      # JSON response; releases with >30 files (e.g. burn_viirs_raster) would
      # silently miss older months, causing unnecessary AppEEARS re-submissions.
      asset_list <- gh::gh(
        "GET /repos/{owner}/{repo}/releases/{release_id}/assets",
        owner      = owner_repo[1],
        repo       = owner_repo[2],
        release_id = rel$id,
        .limit     = Inf,
        .token     = token
      )
      vapply(asset_list, `[[`, character(1), "name")
    }, error = function(e) {
      # Release doesn't exist yet — treat as empty
      character(0)
    })
    assign(release_tag, asset_names, envir = .gh_release_asset_cache)
  }
  asset_name %in% get(release_tag, envir = .gh_release_asset_cache, inherits = FALSE)
}

