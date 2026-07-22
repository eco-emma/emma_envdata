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
# Internal helper: deterministic shard assignment (1..n_shards) for a target
# object name.  GitHub limits releases to ~1,000 assets; sharding spreads
# objects across n_shards releases named "{base_tag}-1" … "{base_tag}-N".
#
# Assignment uses the last two hex characters of the name (all branch-target
# names end in a 16-char hex hash) giving a stable, roughly-uniform split.
# Names without a hex suffix fall back to a char-sum of the first 8 chars.
# ---------------------------------------------------------------------------
.target_shard <- function(name, n_shards) {
  suffix <- substr(name, nchar(name) - 1L, nchar(name))
  val    <- suppressWarnings(strtoi(suffix, 16L))
  if (is.na(val) || !is.finite(val)) {
    val <- sum(utf8ToInt(substr(name, 1L, min(8L, nchar(name)))))
  }
  (as.integer(val) %% as.integer(n_shards)) + 1L
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

# ---------------------------------------------------------------------------
# Internal helper: fetch all assets from a single release by ID.
# Returns a data.frame(file_name, id, size) or an empty frame on error.
# ---------------------------------------------------------------------------
.fetch_release_assets <- function(owner, repo, release_id, token) {
  al <- tryCatch(
    gh::gh(
      "GET /repos/{owner}/{repo}/releases/{release_id}/assets",
      owner = owner, repo = repo,
      release_id = release_id, .limit = Inf, .token = token
    ),
    error = function(e) list()
  )
  if (length(al) == 0) {
    return(data.frame(file_name = character(0), id = integer(0),
                      size = integer(0), stringsAsFactors = FALSE))
  }
  data.frame(
    file_name = vapply(al, `[[`, character(1), "name"),
    id        = vapply(al, `[[`, numeric(1),   "id"),
    size      = vapply(al, `[[`, numeric(1),   "size"),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Internal helper: ensure a GitHub release exists (create if absent).
# Returns the release object from the API.
# ---------------------------------------------------------------------------
.ensure_release <- function(owner, repo, tag, existing_tags, token, verbose) {
  if (!tag %in% existing_tags) {
    if (verbose) message("[tar_github_release] Creating shard release: ", tag)
    gh::gh(
      "POST /repos/{owner}/{repo}/releases",
      owner      = owner, repo = repo,
      tag_name   = tag,
      name       = tag,
      prerelease = TRUE,
      .token     = token
    )
    Sys.sleep(3)  # let GitHub propagate before first upload
  }
  gh::gh(
    "GET /repos/{owner}/{repo}/releases/tags/{tag}",
    owner = owner, repo = repo, tag = tag,
    .token = token
  )
}

#' Download targets from GitHub Release (sharded)
#'
#' Downloads the targets-cache from up to \code{n_shards} GitHub releases
#' named \code{{tag}-1} … \code{{tag}-n_shards}.  Used on GitHub Actions to
#' restore the pipeline state before \code{tar_make()}.
#'
#' @param repo       Repository in "owner/repo" format.
#' @param tag        Base release tag (objects live in "{tag}-1", "{tag}-2", …).
#' @param n_shards   Number of shard releases to search (default 4).
#' @param cache_dir  Local cache directory (default "_targets/user/cache").
#' @param which_targets Optional vector of specific target names to download.
#' @param verbose    Print progress messages.
#' @export
tar_download_github_release <- function(
  repo          = NULL,
  tag           = NULL,
  n_shards      = 4L,
  cache_dir     = "_targets/user/cache",
  which_targets = NULL,
  verbose       = TRUE
) {
  repo      <- repo      %||% Sys.getenv("TAR_GH_RELEASE_REPO") %||% "eco-emma/emma_envdata"
  tag       <- tag       %||% Sys.getenv("TAR_GH_RELEASE_TAG")  %||% "targets-cache"
  cache_dir <- cache_dir %||% Sys.getenv("TAR_GH_RELEASE_CACHE_DIR") %||% "_targets/cache"
  objects_dir <- "_targets/objects"

  if (!nzchar(repo) || !nzchar(tag)) {
    stop("GitHub release configuration not set.")
  }

  .token     <- .gh_token()
  owner_repo <- strsplit(repo, "/")[[1]]
  owner      <- owner_repo[1]; repo_name <- owner_repo[2]

  dir.create(cache_dir,   recursive = TRUE, showWarnings = FALSE)
  dir.create(objects_dir, recursive = TRUE, showWarnings = FALSE)

  # Helper: download a single release asset by numeric ID.
  .download_asset <- function(asset_id, dest_path) {
    r <- httr::RETRY(
      verb  = "GET",
      url   = sprintf("https://api.github.com/repos/%s/%s/releases/assets/%s",
                      owner, repo_name, asset_id),
      httr::add_headers(Authorization = paste("token", .token),
                        Accept        = "application/octet-stream"),
      httr::write_disk(dest_path, overwrite = TRUE),
      times        = 3,
      terminate_on = c(401, 403, 404)
    )
    httr::stop_for_status(r)
    invisible(dest_path)
  }

  # ── Collect assets from all shard releases ─────────────────────────────────
  shard_tags <- paste0(tag, "-", seq_len(n_shards))
  all_assets <- data.frame(file_name = character(0), id = integer(0),
                           size = integer(0), stringsAsFactors = FALSE)

  for (stag in shard_tags) {
    rel <- tryCatch(
      gh::gh("GET /repos/{owner}/{repo}/releases/tags/{tag}",
             owner = owner, repo = repo_name, tag = stag, .token = .token),
      error = function(e) NULL
    )
    if (is.null(rel)) {
      if (verbose) message("[tar_github_release] Shard release not found (skipping): ", stag)
      next
    }
    df <- .fetch_release_assets(owner, repo_name, rel$id, .token)
    if (nrow(df) > 0) {
      all_assets <- rbind(all_assets, df)
      if (verbose) message("[tar_github_release] Shard ", stag, ": ",
                           nrow(df), " assets")
    }
  }

  if (verbose) message("[tar_github_release] Total assets across all shards: ",
                       nrow(all_assets))

  # ── Restore _targets/meta/meta ─────────────────────────────────────────────
  meta_dest   <- "_targets/meta/meta"
  meta_cached <- file.path(cache_dir, "_targets_meta")
  meta_row    <- all_assets[all_assets$file_name == "_targets_meta", ]
  if (nrow(meta_row) > 0) {
    tryCatch({
      .download_asset(meta_row$id[1], meta_cached)
      if (file.exists(meta_cached) && file.size(meta_cached) > 0) {
        dir.create("_targets/meta", recursive = TRUE, showWarnings = FALSE)
        file.copy(meta_cached, meta_dest, overwrite = TRUE)
        if (verbose) message("[tar_github_release] Restored targets meta")
      }
    }, error = function(e) {
      if (verbose) message("[tar_github_release] Failed to download targets meta: ",
                           conditionMessage(e))
    })
  } else {
    if (verbose) message("[tar_github_release] No targets meta found in any shard (first run?)")
  }

  # Exclude _targets_meta from the object download loop
  assets <- all_assets[all_assets$file_name != "_targets_meta", ]

  if (!is.null(which_targets)) {
    assets <- assets[assets$file_name %in% which_targets |
                       vapply(assets$file_name,
                              function(n) any(startsWith(n, which_targets)),
                              logical(1)), ]
  }

  if (nrow(assets) == 0) {
    if (verbose) message("[tar_github_release] No assets to download")
    return(invisible(NULL))
  }

  # ── Download each object ───────────────────────────────────────────────────
  for (i in seq_len(nrow(assets))) {
    asset_name  <- assets$file_name[i]
    cached_path <- file.path(cache_dir, asset_name)
    obj_path    <- file.path(objects_dir, asset_name)

    # Download to cache if missing or corrupt
    if (!file.exists(cached_path) || !.check_file_integrity(cached_path)) {
      if (file.exists(cached_path)) {
        if (verbose) message("[tar_github_release] Re-downloading (corrupt cache): ", asset_name)
        file.remove(cached_path)
      } else {
        if (verbose) message("[tar_github_release] Downloading: ", asset_name)
      }
      for (attempt in seq_len(5L)) {
        tryCatch(
          .download_asset(assets$id[i], cached_path),
          error = function(e) {
            if (verbose) message("[tar_github_release] Attempt ", attempt,
                                 " error: ", conditionMessage(e))
          }
        )
        if (.check_file_integrity(cached_path)) {
          if (verbose) message("[tar_github_release] Verified: ", asset_name)
          break
        }
        if (attempt < 5L) {
          if (verbose) message("[tar_github_release] Integrity failed (attempt ",
                               attempt, "), retrying...")
          if (file.exists(cached_path)) file.remove(cached_path)
          Sys.sleep(2)
        } else {
          warning("[tar_github_release] Failed to download valid file after 5 attempts: ",
                  asset_name)
        }
      }
    } else {
      if (verbose) message("[tar_github_release] Already cached: ", asset_name)
    }

    # Copy verified file to _targets/objects/
    if (file.exists(cached_path) && .check_file_integrity(cached_path)) {
      dir.create(objects_dir, recursive = TRUE, showWarnings = FALSE)
      file.copy(cached_path, obj_path, overwrite = TRUE)
      if (verbose) message("[tar_github_release] Restored: ", asset_name)
    }
  }

  if (verbose) message("[tar_github_release] Download complete")
  invisible(NULL)
}


#' Upload targets cache to sharded GitHub Releases
#'
#' Uploads \code{_targets/objects/} to \code{n_shards} GitHub releases named
#' \code{{tag}-1} … \code{{tag}-n_shards}, keeping each release under GitHub's
#' ~1,000-asset limit.  Object-to-shard assignment is deterministic (based on
#' the last two hex characters of the object name) so the same object always
#' goes to the same shard.  \code{_targets_meta} lives on shard 1 only.
#'
#' @param repo      Repository in "owner/repo" format.
#' @param tag       Base tag; shard releases are named "{tag}-1", "{tag}-2", …
#' @param n_shards  Number of shard releases (default 4, handles ~3 600 objects).
#' @param cache_dir Local cache directory (unused during upload; kept for API
#'   symmetry with \code{tar_download_github_release}).
#' @param which_targets Optional vector of specific target names to upload.
#' @param verbose   Print progress messages.
#' @export
tar_upload_github_release <- function(
  repo          = NULL,
  tag           = NULL,
  n_shards      = 4L,
  format        = "rds",   # kept for API compat; not used
  cache_dir     = "_targets/cache",
  which_targets = NULL,
  verbose       = TRUE
) {
  repo      <- repo      %||% Sys.getenv("TAR_GH_RELEASE_REPO") %||% "eco-emma/emma_envdata"
  tag       <- tag       %||% Sys.getenv("TAR_GH_RELEASE_TAG")  %||% "targets-cache"
  cache_dir <- cache_dir %||% Sys.getenv("TAR_GH_RELEASE_CACHE_DIR") %||% "_targets/cache"

  if (!nzchar(repo) || !nzchar(tag)) {
    stop("GitHub release configuration not set.")
  }

  .token     <- .gh_token()
  owner_repo <- strsplit(repo, "/")[[1]]
  owner      <- owner_repo[1]; repo_name <- owner_repo[2]

  # ── Enumerate existing releases ────────────────────────────────────────────
  existing_tags <- tryCatch({
    rels <- gh::gh("GET /repos/{owner}/{repo}/releases",
                   owner = owner, repo = repo_name,
                   .limit = Inf, .token = .token)
    vapply(rels, `[[`, character(1), "tag_name")
  }, error = function(e) character(0))

  # ── Ensure all shard releases exist and fetch their metadata ───────────────
  shard_tags     <- paste0(tag, "-", seq_len(n_shards))
  shard_releases <- vector("list", n_shards)  # release objects
  shard_urls     <- character(n_shards)        # upload URLs
  shard_assets   <- vector("list", n_shards)  # data.frames of remote assets

  for (s in seq_len(n_shards)) {
    stag <- shard_tags[s]
    rel  <- tryCatch(
      .ensure_release(owner, repo_name, stag, existing_tags, .token, verbose),
      error = function(e) {
        stop("[tar_github_release] Cannot access shard release '", stag,
             "': ", conditionMessage(e))
      }
    )
    shard_releases[[s]] <- rel
    shard_urls[s]       <- sub("\\{.*", "", rel$upload_url)
    shard_assets[[s]]   <- .fetch_release_assets(owner, repo_name, rel$id, .token)
    if (verbose) message("[tar_github_release] Shard ", stag, ": ",
                         nrow(shard_assets[[s]]), " existing assets")
  }

  # Merged remote asset table (with shard column for upload routing)
  remote_assets_all <- do.call(rbind, lapply(seq_len(n_shards), function(s) {
    df <- shard_assets[[s]]
    if (nrow(df) == 0) return(data.frame(file_name = character(0), id = integer(0),
                                         size = integer(0), shard = integer(0),
                                         stringsAsFactors = FALSE))
    df$shard <- s
    df
  }))

  # ── One-time cleanup of legacy workspace assets ────────────────────────────
  # Delete any {name}.{ext} assets whose bare name also exists — these are
  # leftover workspace debug files from older code, not real target values.
  legacy_mask <- grepl("\\.[^.]+$", remote_assets_all$file_name) &
    remote_assets_all$file_name != "_targets_meta"
  if (any(legacy_mask)) {
    legacy_df  <- remote_assets_all[legacy_mask, ]
    bare_names <- sub("\\.[^.]+$", "", legacy_df$file_name)
    has_bare   <- bare_names %in% remote_assets_all$file_name
    for (i in which(has_bare)) {
      s <- legacy_df$shard[i]
      if (verbose) message("[tar_github_release] Deleting legacy asset: ",
                           legacy_df$file_name[i])
      tryCatch(
        gh::gh("DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}",
               owner = owner, repo = repo_name,
               asset_id = legacy_df$id[i], .token = .token),
        error = function(e) NULL
      )
      Sys.sleep(0.5)
    }
    remote_assets_all <- remote_assets_all[
      !remote_assets_all$file_name %in% legacy_df$file_name[has_bare], , drop = FALSE]
  }

  # ── Load local targets metadata (for hash comparison) ─────────────────────
  meta_df <- tryCatch(
    targets::tar_meta(),
    error = function(e) {
      if (verbose) message("[tar_github_release] Could not read targets metadata")
      data.frame(name = character(0), data = character(0), stringsAsFactors = FALSE)
    }
  )

  # ── Download _targets_meta from shard 1 for content-hash comparison ────────
  # We can skip uploading any object whose data-hash in the local meta matches
  # the remote meta — a reliable idempotency check that survives re-runs.
  # NOTE: do NOT use return() inside tryCatch({}) — it exits the enclosing
  # function, not just the tryCatch block.  Use if/else branching instead.
  remote_meta_hashes <- tryCatch({
    meta_row <- shard_assets[[1]][shard_assets[[1]]$file_name == "_targets_meta", ]
    if (nrow(meta_row) == 0) {
      # No remote meta yet (first run) — upload everything
      if (verbose) message("[tar_github_release] No remote meta on shard 1 ",
                           "(first run — all objects will be uploaded)")
      NULL
    } else {
      tmp_store    <- tempfile(pattern = "tar_upload_meta_")
      tmp_meta_dir <- file.path(tmp_store, "meta")
      dir.create(tmp_meta_dir, recursive = TRUE, showWarnings = FALSE)
      tmp_meta_path <- file.path(tmp_meta_dir, "meta")

      r <- httr::GET(
        sprintf("https://api.github.com/repos/%s/%s/releases/assets/%s",
                owner, repo_name, meta_row$id[1]),
        httr::add_headers(Authorization = paste("token", .token),
                          Accept = "application/octet-stream"),
        httr::write_disk(tmp_meta_path, overwrite = TRUE)
      )
      httr::stop_for_status(r)

      remote_df <- targets::tar_meta(store = tmp_store)
      unlink(tmp_store, recursive = TRUE)
      if (verbose) message("[tar_github_release] Fetched remote meta (",
                           nrow(remote_df), " targets) for hash comparison")
      setNames(remote_df$data, remote_df$name)
    }
  }, error = function(e) {
    if (verbose) message("[tar_github_release] Could not fetch remote meta ",
                         "(will upload all objects): ", conditionMessage(e))
    NULL
  })

  # ── Collect local files to upload ─────────────────────────────────────────
  if (is.null(which_targets)) {
    local_files <- list.files("_targets/objects", full.names = TRUE, recursive = FALSE)
    local_files <- local_files[basename(local_files) != "_targets_meta"]
    if (verbose) message("[tar_github_release] Found ", length(local_files),
                         " local target files to upload across ", n_shards, " shards")
  } else {
    local_files <- file.path("_targets/objects", which_targets)
    local_files <- local_files[file.exists(local_files)]
  }

  if (length(local_files) == 0) {
    message("[tar_github_release] No targets to upload")
    return(invisible(NULL))
  }

  # ── Helper: upload / replace _targets_meta on shard 1 ─────────────────────
  meta_path <- "_targets/meta/meta"
  .upload_meta <- function(label = "") {
    if (!file.exists(meta_path)) return(invisible(NULL))
    upload_name <- "_targets_meta"
    if (verbose) message("[tar_github_release] Uploading targets meta",
                         if (nzchar(label)) paste0(" (", label, ")") else "",
                         ": ", meta_path)
    # Re-fetch shard-1 assets so the ID is always current
    fresh <- .fetch_release_assets(owner, repo_name,
                                   shard_releases[[1]]$id, .token)
    if (any(fresh$file_name == upload_name)) {
      tryCatch({
        gh::gh("DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}",
               owner = owner, repo = repo_name,
               asset_id = fresh$id[fresh$file_name == upload_name][1],
               .token = .token)
        Sys.sleep(1)
      }, error = function(e) NULL)
    }
    tryCatch({
      r <- httr::RETRY(
        verb  = "POST", url = shard_urls[1],
        query = list(name = upload_name),
        httr::add_headers(Authorization = paste("token", .token)),
        body  = httr::upload_file(meta_path),
        times = 3, terminate_on = c(400, 401, 403, 404, 422)
      )
      httr::stop_for_status(r)
      if (verbose) message("[tar_github_release] Uploaded targets meta")
    }, error = function(e) {
      warning("[tar_github_release] Failed to upload targets meta: ", conditionMessage(e))
    })
  }

  # Pre-loop meta upload: ensures meta is always current even if the object
  # loop is interrupted by a timeout or rate limit.
  .upload_meta("pre-object sync")

  # ── Rate-limit constants ───────────────────────────────────────────────────
  # GitHub secondary rate limit: ≤ 80 content-creating calls/minute.
  # 1 s between calls → ≤ 60/min, safely under the limit.
  upload_sleep_s   <- 1.0
  ratelimit_wait_s <- 60L
  n_failed         <- 0L

  # ── Upload loop ────────────────────────────────────────────────────────────
  for (local_file in local_files) {
    target_name <- basename(local_file)
    upload_name <- target_name

    # Assign deterministic shard
    s           <- .target_shard(target_name, n_shards)
    upload_url  <- shard_urls[s]

    # Check existence across ALL shards (an object might be on the wrong shard
    # from a previous run with a different n_shards value).
    exists_rows <- remote_assets_all[remote_assets_all$file_name == upload_name, ]
    exists_on_github <- nrow(exists_rows) > 0

    # Skip if the object exists ANYWHERE across the shards with a matching hash.
    # Deliberately NOT checking which shard the object is currently on: this
    # lets n_shards be increased later (e.g. 4 → 6) without forcing a full
    # re-upload of all unchanged objects.  Objects migrate to their assigned
    # shard naturally the next time their content changes (i.e. tar_make
    # rebuilds them), at which point the old asset is deleted and a new one
    # is uploaded to the correct shard.
    if (exists_on_github) {
      local_hash <- meta_df$data[meta_df$name == target_name]
      if (!is.null(remote_meta_hashes) &&
          length(local_hash) == 1L && !is.na(local_hash) &&
          target_name %in% names(remote_meta_hashes) &&
          identical(local_hash, remote_meta_hashes[[target_name]])) {
        if (verbose) message("[tar_github_release] Skipping (hash unchanged): ", upload_name)
        next
      }
    }

    if (verbose) message("[tar_github_release] Uploading object (shard ", s, "): ", target_name)

    # Delete existing asset — handle the case where it may be on a different shard
    if (exists_on_github) {
      for (row_i in seq_len(nrow(exists_rows))) {
        old_shard <- exists_rows$shard[row_i]
        old_id    <- exists_rows$id[row_i]
        tryCatch({
          gh::gh("DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}",
                 owner = owner, repo = repo_name,
                 asset_id = old_id, .token = .token)
          Sys.sleep(upload_sleep_s)
        }, error = function(e) NULL)
      }
    }

    # Upload to the assigned shard
    upload_ok <- tryCatch({
      r <- httr::RETRY(
        verb  = "POST", url = upload_url,
        query = list(name = upload_name),
        httr::add_headers(Authorization = paste("token", .token)),
        body  = httr::upload_file(local_file),
        times = 3, terminate_on = c(400, 401, 403, 404, 422)
      )
      status <- httr::status_code(r)
      if (status == 429 ||
          (status == 403 &&
           grepl("secondary rate limit",
                 tryCatch(httr::content(r, "text", encoding = "UTF-8"),
                          error = function(e) ""),
                 ignore.case = TRUE))) {
        message("[tar_github_release] Secondary rate limit — sleeping ",
                ratelimit_wait_s, "s")
        Sys.sleep(ratelimit_wait_s)
        n_failed <<- n_failed + 1L
        warning("[tar_github_release] Rate-limited on ", upload_name,
                " — will retry on next run")
        FALSE
      } else {
        httr::stop_for_status(r)
        if (verbose) message("[tar_github_release] Uploaded: ", upload_name)
        TRUE
      }
    }, error = function(e) {
      n_failed <<- n_failed + 1L
      warning("[tar_github_release] Failed to upload ", upload_name, ": ",
              conditionMessage(e))
      FALSE
    })

    # Always sleep to stay under the secondary rate limit
    Sys.sleep(upload_sleep_s)
  }

  if (n_failed > 0L) {
    warning("[tar_github_release] ", n_failed,
            " object(s) failed to upload — they will be retried on the next run.")
  }

  # Post-loop meta upload: reflects final object state after the upload session.
  .upload_meta("post-object sync")

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
