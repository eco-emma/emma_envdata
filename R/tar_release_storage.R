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
      tiff    = ,
      nc      = { terra::rast(path);          TRUE },
      gpkg    = { sf::st_read(path, quiet = TRUE); TRUE },
      qs      = { qs2::qread(path);             TRUE },
      rds     = { readRDS(path);               TRUE },
      # For binary objects with no extension (targets qs/qs2 objects): verify
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
  cache_dir = "_targets/cache",
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
  
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(objects_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Get list of assets on GitHub release
  # pb_list() throws "undefined columns selected" on empty releases (piggyback bug) — treat as 0 assets
  assets <- tryCatch({
    result <- piggyback::pb_list(repo = repo, tag = tag)
    if (is.null(result)) result <- data.frame(file_name = character(0), stringsAsFactors = FALSE)
    if (verbose) message("[tar_github_release] Found ", nrow(result), " assets on GitHub release")
    result
  }, error = function(e) {
    msg <- conditionMessage(e)
    if (grepl("undefined columns selected|subscript out of bounds|no releases found|values must be length|Cannot find release|HTTP error 404|release not found", msg, ignore.case = TRUE)) {
      if (verbose) message("[tar_github_release] Release has no assets or does not exist yet, skipping download")
      return(data.frame(file_name = character(0), stringsAsFactors = FALSE))
    }
    stop("[tar_github_release] Could not access GitHub release: ", msg)
  })
  
  # Filter assets if specific targets requested
  if (!is.null(which_targets)) {
    assets <- assets[assets$file_name %in% which_targets | startsWith(assets$file_name, which_targets), ]
  }
  
  if (is.null(assets) || nrow(assets) == 0) {
    if (verbose) message("[tar_github_release] No assets to download")
    return(invisible(NULL))
  }
  
  # Download each asset
  for (i in seq_len(nrow(assets))) {
    asset_name <- assets$file_name[i]
    
    # Check if this is a file-format target (has extension)
    # File-format targets are stored as "target_name.extension" (e.g., "country.parquet")
    # Regular objects are stored as "target_name" (e.g., "elevation_task_id")
    is_file_format <- grepl("\\.[^.]+$", asset_name)
    
    if (is_file_format) {
      # Extract target name by removing extension
      target_name <- sub("\\.[^.]+$", "", asset_name)
      file_ext <- sub(".*\\.", "", asset_name)
    } else {
      target_name <- asset_name
      file_ext <- NULL
    }
    
    local_path <- file.path(objects_dir, target_name)
    cached_path <- file.path(cache_dir, asset_name)

    # ── Skip if already valid in _targets/objects/ ──────────────────────────
    # Handles the case where _targets/cache/ was cleared but objects were
    # already restored from a previous run — avoids redundant downloads.
    already_valid <- tryCatch({
      obj_path_check <- file.path(objects_dir, target_name)
      if (is_file_format) {
        if (!file.exists(obj_path_check)) FALSE
        else {
          data_file <- readRDS(obj_path_check)
          is.character(data_file) && file.exists(data_file) && .check_file_integrity(data_file)
        }
      } else {
        file.exists(obj_path_check) && file.size(obj_path_check) > 0
      }
    }, error = function(e) FALSE)

    if (already_valid) {
      if (verbose) message("[tar_github_release] Already restored locally, skipping: ", target_name)
      next
    }

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
        tryCatch({
          piggyback::pb_download(
            file = asset_name,
            repo = repo,
            tag = tag,
            dest = cache_dir,
            overwrite = TRUE
          )
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
        
        # Create RDS wrapper in _targets/objects/ ONLY if the qs object is not already there.
        # The bare-name asset (e.g. "elevation") is the authoritative qs object.
        # The .ext asset (e.g. "elevation.nc") is just the data file — overwriting the already-
        # restored qs object with an RDS path causes a hash mismatch and forces re-runs.
        obj_dir <- "_targets/objects"
        dir.create(obj_dir, recursive = TRUE, showWarnings = FALSE)
        obj_path <- file.path(obj_dir, target_name)
        if (!file.exists(obj_path)) {
          saveRDS(ws_path, obj_path)
          if (verbose) message("[tar_github_release] Restored file-format target: ", target_name)
        } else {
          if (verbose) message("[tar_github_release] Skipped RDS write (qs object already present): ", target_name)
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
#' @param format Serialization format: "qs", "rds", or "parquet" (default: "qs")
#' @param cache_dir Cache directory (default: "_targets/cache")
#' @param which_targets Optional vector of specific target names to upload
#' @param verbose Logical for progress messages
#' @details Call this after tar_make() to upload all targets
#' @export
tar_upload_github_release <- function(
  repo = NULL,
  tag = NULL,
  format = "qs",
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
  
  # Ensure release exists.
  # Use pb_releases() (not pb_list()) to check existence — pb_list() populates
  # piggyback's internal memoise cache with a "not found" result, which then
  # causes pb_upload() to fail with "length(url) == 1 is not TRUE" even after
  # the release is created, because the stale memo is still in effect.
  existing_releases <- tryCatch(
    piggyback::pb_releases(repo = repo),
    error = function(e) data.frame(tag_name = character(0))
  )
  if (!tag %in% existing_releases$tag_name) {
    if (verbose) message("[tar_github_release] Creating release: ", tag)
    piggyback::pb_new_release(repo = repo, tag = tag)
    Sys.sleep(3)  # let GitHub propagate before first upload
  }

  # Get metadata to find file-format target paths
  meta_df <- tryCatch({
    tar_meta()
  }, error = function(e) {
    if (verbose) message("[tar_github_release] Could not read targets metadata")
    data.frame(name = character(0), format = character(0), path = list())
  })

  # Prime the piggyback release cache so pb_upload() finds the correct upload
  # URL on the first attempt.
  remote_assets <- tryCatch({
    piggyback::pb_list(repo = repo, tag = tag)
  }, error = function(e) {
    data.frame(file_name = character(0))
  })
  
  # Get list of local target files
  if (is.null(which_targets)) {
    # Get all targets from _targets/objects/ (regular objects)
    regular_files <- list.files("_targets/objects", full.names = TRUE, recursive = FALSE)
    
    # Also get file-format targets from _targets/workspaces/
    file_format_targets <- character(0)
    if (dir.exists("_targets/workspaces")) {
      ws_files <- list.files("_targets/workspaces", full.names = FALSE, recursive = FALSE)
      # Filter to only include those that are file-format targets (have metadata)
      for (ws_file in ws_files) {
        target_meta <- meta_df[meta_df$name == ws_file, ]
        if (nrow(target_meta) > 0 && target_meta$format[1] == "file") {
          file_format_targets <- c(file_format_targets, file.path("_targets/workspaces", ws_file))
        }
      }
    }
    
    # Also get actual data files from data/target_outputs/
    data_output_files <- character(0)
    if (dir.exists("data/target_outputs")) {
      all_output_files <- list.files("data/target_outputs", full.names = TRUE, recursive = FALSE)
      # Exclude hidden/system directories (e.g. .DS_Store)
      data_output_files <- all_output_files[!grepl("^\\.", basename(all_output_files))]
    }
    
    local_files <- c(regular_files, file_format_targets, data_output_files)
    if (verbose) message("[tar_github_release] Found ", length(local_files), " local target files to upload")
  } else {
    # Find specific targets - check all locations
    regular_files <- character(0)
    file_format_targets <- character(0)
    data_output_files <- character(0)
    
    for (target in which_targets) {
      obj_file <- file.path("_targets/objects", target)
      ws_file <- file.path("_targets/workspaces", target)
      data_file <- file.path("data/target_outputs", target)
      
      if (file.exists(obj_file)) {
        regular_files <- c(regular_files, obj_file)
      } else if (file.exists(ws_file)) {
        target_meta <- meta_df[meta_df$name == target, ]
        if (nrow(target_meta) > 0 && target_meta$format[1] == "file") {
          file_format_targets <- c(file_format_targets, ws_file)
        }
      } else if (file.exists(data_file)) {
        data_output_files <- c(data_output_files, data_file)
      }
    }
    local_files <- c(regular_files, file_format_targets, data_output_files)
  }
  
  if (length(local_files) == 0) {
    message("[tar_github_release] No targets to upload")
    return(invisible(NULL))
  }
  
  # Upload each file
  for (local_file in local_files) {
    target_name <- basename(local_file)
    
    # Determine if this is a file-format target based on location
    # Files in _targets/workspaces/ are file-format targets
    is_file_target <- grepl("_targets/workspaces", local_file)
    
    if (is_file_target) {
      # This is a file-format target in _targets/workspaces/
      # Use the file from workspaces as the source to upload
      # Get extension from metadata or from actual file
      target_meta <- meta_df[meta_df$name == target_name, ]
      
      # Try to get extension from metadata path
      ext <- ""
      if (nrow(target_meta) > 0) {
        metadata_path <- target_meta$path[[1]]
        # Handle case where path is a vector with multiple values
        if (is.character(metadata_path) && length(metadata_path) > 0) {
          # Take the first one and get the extension from it
          ext <- tools::file_ext(metadata_path[1])
        }
      }
      
      # If we couldn't get extension from metadata, skip this file
      if (nchar(ext) == 0) {
        if (verbose) message("[tar_github_release] Skipping file-format target (no extension found): ", target_name)
        next
      }
      
      # Create upload name - avoid double extensions
      # If target name already ends with this extension, don't add it again
      if (grepl(paste0("\\.", ext, "$"), target_name)) {
        upload_name <- target_name
      } else {
        upload_name <- paste0(target_name, ".", ext)
      }
      
      if (verbose) message("[tar_github_release] Uploading file-format target: ", upload_name, " from ", local_file)
      
      # Check if already exists on GitHub
      exists_on_github <- any(remote_assets$file_name == upload_name)
      if (exists_on_github) {
        if (verbose) message("[tar_github_release] File already on GitHub, deleting old version: ", upload_name)
        tryCatch({
          # Delete old version
          old_asset <- remote_assets[remote_assets$file_name == upload_name, ]
          if (nrow(old_asset) > 0) {
            piggyback::pb_delete(repo = repo, tag = tag, file = upload_name)
            Sys.sleep(1)
          }
        }, error = function(e) {
          if (verbose) message("[tar_github_release] Could not delete old asset: ", conditionMessage(e))
        })
      }
      
      max_attempts <- 3
      for (attempt in 1:max_attempts) {
        tryCatch({
          piggyback::pb_upload(
            file = local_file,
            repo = repo,
            tag = tag,
            name = upload_name,
            overwrite = FALSE
          )
          if (verbose) message("[tar_github_release] Uploaded: ", upload_name)
          Sys.sleep(1)
          break
        }, error = function(e) {
          if (attempt < max_attempts) {
            if (verbose) message("[tar_github_release] Upload attempt ", attempt, " failed: ", conditionMessage(e))
            Sys.sleep(2)
          } else {
            warning("[tar_github_release] Failed to upload after ", max_attempts, " attempts: ", conditionMessage(e))
          }
        })
      }
    } else {
      # Regular objects or data output files
      # Determine if it's from data/target_outputs or _targets/objects
      is_data_output <- grepl("data/target_outputs", local_file)
      
      if (is_data_output) {
        # Data output file - upload with its original name
        upload_name <- basename(local_file)
        if (verbose) message("[tar_github_release] Uploading data file: ", upload_name)
      } else {
        # Serialized object from _targets/objects
        upload_name <- target_name
        if (verbose) message("[tar_github_release] Uploading object: ", target_name)
      }
      
      # Check if already exists on GitHub
      exists_on_github <- any(remote_assets$file_name == upload_name)
      if (exists_on_github) {
        if (verbose) message("[tar_github_release] File already on GitHub, deleting old version: ", upload_name)
        tryCatch({
          # Delete old version
          piggyback::pb_delete(repo = repo, tag = tag, file = upload_name)
          Sys.sleep(1)
        }, error = function(e) {
          if (verbose) message("[tar_github_release] Could not delete old asset: ", conditionMessage(e))
        })
      }
      
      max_attempts <- 3
      for (attempt in 1:max_attempts) {
        tryCatch({
          piggyback::pb_upload(
            file = local_file,
            repo = repo,
            tag = tag,
            name = upload_name,
            overwrite = FALSE
          )
          if (verbose) message("[tar_github_release] Uploaded: ", upload_name)
          Sys.sleep(1)
          break
        }, error = function(e) {
          if (attempt < max_attempts) {
            if (verbose) message("[tar_github_release] Upload attempt ", attempt, " failed: ", conditionMessage(e))
            Sys.sleep(2)
          } else {
            warning("[tar_github_release] Failed to upload: ", conditionMessage(e))
          }
        })
      }
    }
  }
  
  if (verbose) message("[tar_github_release] Upload complete")
  invisible(NULL)
}

