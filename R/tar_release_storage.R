#' Create GitHub Releases repository for targets
#' @description Create a tar_repository_cas() object that stores targets 
#'   using GitHub releases as the backend, with local persistent caching.
#' @param repo Repository in "owner/repo" format
#' @param tag Release tag to store objects (e.g., "objects_v2024" or "objects_current")
#' @param format Serialization format: "qs" (fast, recommended), "rds", or "parquet"
#' @param cache_dir Persistent cache directory for downloaded files (default: "data/.tar_cache")
#' @return tar_repository_cas() object for use with tar_target(repository = ...)
#' @details
#'   Use with tar_target(..., repository = tar_github_release_repo(...))
#'   
#'   This implements the Content Addressable Storage (CAS) pattern where targets
#'   are stored with serialized R objects, with GitHub releases as the backend
#'   and local persistent caching for speed.
#'   
#'   Example:
#'   ```
#'   gh_repo <- tar_github_release_repo(
#'     repo = "AdamWilsonLab/emma_envdata",
#'     tag = "objects_current",
#'     format = "qs",
#'     cache_dir = "data/.tar_cache"
#'   )
#'   
#'   tar_target(
#'     my_object,
#'     some_computation(),
#'     repository = gh_repo,
#'     cue = tar_cue(mode = "never")
#'   )
#'   ```
#' @export
tar_github_release_repo <- function(
  repo,
  tag,
  format = "qs",
  cache_dir = "data/.tar_cache"
) {
  
  stopifnot(
    is.character(repo) && nchar(repo) > 0,
    is.character(tag) && nchar(tag) > 0,
    format %in% c("qs", "rds", "parquet")
  )
  
  # Create a tar_repository_cas() object with self-contained functions
  # that read config from environment variables
  tar_repository_cas(
    upload = function(key, path) {
      repo <- Sys.getenv("TAR_GH_RELEASE_REPO")
      tag <- Sys.getenv("TAR_GH_RELEASE_TAG")
      format <- Sys.getenv("TAR_GH_RELEASE_FORMAT")
      
      # Ensure release exists before uploading
      release_exists <- FALSE
      tryCatch({
        assets <- piggyback::pb_list(repo = repo, tag = tag)
        release_exists <- TRUE
      }, error = function(e) {
        # pb_list throws error if release doesn't exist
        release_exists <<- FALSE
      })
      
      if (!release_exists) {
        message("[tar_github_release] Creating release: ", tag)
        tryCatch({
          piggyback::pb_new_release(repo = repo, tag = tag)
          message("[tar_github_release] Release created: ", tag)
        }, error = function(e) {
          if (!grepl("already exists", tolower(conditionMessage(e)))) {
            stop("[tar_github_release] Failed to create release: ", conditionMessage(e))
          }
        })
      }
      
      if (file.exists(path) && !dir.exists(path)) {
        message("[tar_github_release] Uploading file: ", key)
        tryCatch({
          piggyback::pb_upload(
            file = path,
            repo = repo,
            tag = tag,
            name = key,
            overwrite = TRUE,
            .token = NULL
          )
          message("[tar_github_release] File uploaded: ", key)
        }, error = function(e) {
          stop("[tar_github_release] Failed to upload file: ", conditionMessage(e))
        })
      } else {
        obj <- readRDS(path)
        temp_file <- tempfile(fileext = paste0(".", format))
        on.exit(unlink(temp_file), add = TRUE)
        
        if (format == "qs") {
          qs::qsave(obj, temp_file)
        } else if (format == "rds") {
          saveRDS(obj, temp_file)
        } else if (format == "parquet") {
          arrow::write_parquet(obj, temp_file)
        }
        
        max_attempts <- 5
        for (attempt in 1:max_attempts) {
          tryCatch({
            piggyback::pb_upload(
              file = temp_file,
              repo = repo,
              tag = tag,
              name = key,
              overwrite = TRUE,
              .token = NULL
            )
            message("[tar_github_release] Object uploaded: ", key)
            return(invisible())
          }, error = function(e) {
            if (attempt < max_attempts) {
              message("[tar_github_release] Upload attempt ", attempt, " failed: ", conditionMessage(e))
              Sys.sleep(2)
            } else {
              stop("[tar_github_release] Failed to upload after ", max_attempts, " attempts: ", conditionMessage(e))
            }
          })
        }
      }
    },
    download = function(key, path) {
      repo <- Sys.getenv("TAR_GH_RELEASE_REPO")
      tag <- Sys.getenv("TAR_GH_RELEASE_TAG")
      format <- Sys.getenv("TAR_GH_RELEASE_FORMAT")
      cache_dir <- Sys.getenv("TAR_GH_RELEASE_CACHE_DIR")
      
      dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
      cached_file <- file.path(cache_dir, key)
      
      need_download <- TRUE
      if (file.exists(cached_file)) {
        tryCatch({
          remote_assets <- piggyback::pb_list(repo = repo, tag = tag)
          remote_asset <- remote_assets[remote_assets$file_name == key, ]
          
          if (nrow(remote_asset) > 0) {
            local_size <- file.size(cached_file)
            remote_size <- remote_asset$size[1]
            
            if (local_size == remote_size) {
              message("[tar_github_release] Cache valid (size match: ", local_size, " bytes)")
              need_download <- FALSE
            }
          }
        }, error = function(e) {
          message("[tar_github_release] Could not verify cache: ", conditionMessage(e))
        })
      }
      
      if (need_download) {
        max_attempts <- 5
        for (attempt in 1:max_attempts) {
          tryCatch({
            piggyback::pb_download(
              file = key,
              repo = repo,
              tag = tag,
              dest = cache_dir,
              overwrite = TRUE
            )
            message("[tar_github_release] Downloaded: ", key)
            break
          }, error = function(e) {
            if (attempt < max_attempts) {
              message("[tar_github_release] Download attempt ", attempt, " failed: ", conditionMessage(e))
              Sys.sleep(2)
            } else {
              stop("[tar_github_release] Failed to download after ", max_attempts, " attempts: ", conditionMessage(e))
            }
          })
        }
      }
      
      if (!file.exists(cached_file)) {
        stop("[tar_github_release] Failed to retrieve: ", key)
      }
      
      file_exts <- c("parquet", "nc", "tif", "gpkg", "shp", "dbf", "prj", "shx")
      is_spatial_file <- any(endsWith(tolower(key), paste0(".", file_exts)))
      
      if (is_spatial_file) {
        file.copy(cached_file, path, overwrite = TRUE)
        message("[tar_github_release] Retrieved file: ", key)
      } else {
        if (format == "qs") {
          obj <- qs::qread(cached_file)
        } else if (format == "rds") {
          obj <- readRDS(cached_file)
        } else if (format == "parquet") {
          obj <- arrow::read_parquet(cached_file)
        }
        
        saveRDS(obj, path)
        message("[tar_github_release] Retrieved and deserialized: ", key)
      }
      invisible()
    },
    exists = function(key) {
      repo <- Sys.getenv("TAR_GH_RELEASE_REPO")
      tag <- Sys.getenv("TAR_GH_RELEASE_TAG")
      
      tryCatch({
        assets <- piggyback::pb_list(repo = repo, tag = tag)
        any(assets$file_name == key)
      }, error = function(e) {
        FALSE
      })
    }
  )
}

# Helper to set up tar_resources_repository_cas with environment variables
tar_github_release_resources <- function(
  repo,
  tag,
  format = "qs",
  cache_dir = "data/.tar_cache"
) {
  tar_resources_repository_cas(
    envvars = c(
      TAR_GH_RELEASE_REPO = repo,
      TAR_GH_RELEASE_TAG = tag,
      TAR_GH_RELEASE_FORMAT = format,
      TAR_GH_RELEASE_CACHE_DIR = cache_dir
    )
  )
}
