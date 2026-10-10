# GitHub Actions entry point. Restores targets metadata, rebuilds only
# outdated MODIS/VIIRS VI and burned-area branches, and uploads the new
# COGs and parquets. Aggregate upload, STAC, and README targets stay on
# the CCR run because they read every historical branch.
#
# Run with: Rscript R/ci_appeears_update.R
# Not sourced by _targets.R.

options(error = function() {
  traceback(2)
  quit(status = 1)
})

appeears_name_pattern <- paste0(
  "^(vi_modis|vi_viirs|burn_modis|burn_viirs)_",
  "(pending|task_ids|geotiff|grid|parquet)",
  "($|_)"
)

product_branch_pattern <- paste0(
  "^(vi_modis|vi_viirs|burn_modis|burn_viirs)_",
  "(grid|parquet)_[0-9a-f]+$"
)

# Filenames must stay aligned with release_tags in _targets.R.
.product_release_tag <- function(path) {
  bn <- basename(path)
  if (grepl("^vi_modis_terra_.*\\.tif$", bn)) return("vi_modis_terra_raster")
  if (grepl("^vi_modis_aqua_.*\\.tif$", bn)) return("vi_modis_aqua_raster")
  if (grepl("^vi_modis_.*\\.parquet$", bn)) return("vi_modis_parquet")
  if (grepl("^vi_viirs_.*\\.tif$", bn)) return("vi_viirs_raster")
  if (grepl("^vi_viirs_.*\\.parquet$", bn)) return("vi_viirs_parquet")
  if (grepl("^burn_modis_.*\\.tif$", bn)) return("burn_modis_raster")
  if (grepl("^burn_modis_.*\\.parquet$", bn)) return("burn_modis_parquet")
  if (grepl("^burn_viirs_.*\\.tif$", bn)) return("burn_viirs_raster")
  if (grepl("^burn_viirs_.*\\.parquet$", bn)) return("burn_viirs_parquet")
  NA_character_
}

.appeears_outdated <- function() {
  outdated <- targets::tar_outdated(callr_function = NULL)
  outdated[grepl(appeears_name_pattern, outdated)]
}

# Direct target dependencies of `names`. Edges point from the dependency
# (and a self-loop) to the target. Sibling months are not included.
.upstream_objects <- function(names) {
  if (!length(names)) return(character(0))
  net <- targets::tar_network(
    targets_only = TRUE,
    names = names,
    shortcut = FALSE,
    callr_function = NULL
  )
  edges <- net$edges
  if (!nrow(edges)) return(character(0))
  upstream <- edges$from[edges$to %in% names & edges$from != edges$to]
  unique(upstream)
}

.product_paths <- function(branch_names) {
  paths <- character(0)
  for (name in branch_names) {
    value <- tryCatch(
      targets::tar_read_raw(name),
      error = function(e) {
        message("[ci_appeears] No product from ", name, ": ", conditionMessage(e))
        NULL
      }
    )
    if (is.character(value)) paths <- c(paths, value)
  }
  paths <- unique(paths)
  paths[file.exists(paths) & !grepl("\\.skip$", paths)]
}

# Pattern stems keyed by the pending target they map over.
.pending_stem_map <- list(
  vi_modis_pending = c(
    "vi_modis_task_ids", "vi_modis_geotiff", "vi_modis_grid", "vi_modis_parquet"
  ),
  vi_viirs_pending = c(
    "vi_viirs_task_ids", "vi_viirs_geotiff", "vi_viirs_grid", "vi_viirs_parquet"
  ),
  burn_modis_pending = c(
    "burn_modis_task_ids", "burn_modis_geotiff", "burn_modis_grid",
    "burn_modis_parquet"
  ),
  burn_viirs_pending = c(
    "burn_viirs_task_ids", "burn_viirs_geotiff", "burn_viirs_grid",
    "burn_viirs_parquet"
  )
)

.pending_is_empty <- function(pending_name) {
  # tar_read() uses NSE; character names need tar_read_raw().
  value <- tryCatch(
    targets::tar_read_raw(pending_name),
    error = function(e) {
      stop(
        "[ci_appeears] Cannot read ", pending_name, ": ",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )
  if (is.data.frame(value)) return(nrow(value) == 0L)
  length(value) == 0L
}

.drop_empty_pending_stems <- function(todo) {
  drop <- character(0)
  for (pending_name in names(.pending_stem_map)) {
    if (!.pending_is_empty(pending_name)) next
    stems <- intersect(todo, .pending_stem_map[[pending_name]])
    if (length(stems)) {
      message(
        "[ci_appeears] Skipping ", paste(stems, collapse = ", "),
        " — ", pending_name, " is empty"
      )
      drop <- c(drop, stems)
    }
  }
  setdiff(todo, drop)
}

# Only branch-hash names are safe to skip. Pattern stems must stay when their
# pending table gained new months after a code-driven invalidate.
.drop_already_built_branches <- function(todo) {
  branch_todo <- todo[grepl(product_branch_pattern, todo)]
  if (!length(branch_todo)) return(todo)

  built <- character(0)
  meta <- tryCatch(
    targets::tar_meta(targets_only = TRUE),
    error = function(e) NULL
  )
  if (!is.null(meta) && nrow(meta)) {
    err <- as.character(meta$error)
    ok <- (is.na(err) | !nzchar(err)) & !is.na(meta$time)
    built <- meta$name[ok]
  }
  progress <- tryCatch(
    targets::tar_progress(),
    error = function(e) NULL
  )
  if (!is.null(progress) && nrow(progress)) {
    built <- union(built, progress$name[progress$progress == "built"])
  }

  skipped <- intersect(branch_todo, built)
  if (length(skipped)) {
    message(
      "[ci_appeears] Leaving ", length(skipped),
      " already-built branches in the cache"
    )
  }
  setdiff(todo, skipped)
}

.upload_product_files <- function(paths) {
  if (!length(paths)) {
    message("[ci_appeears] No new COGs or parquets to publish")
    return(invisible(NULL))
  }
  tags <- vapply(paths, .product_release_tag, character(1))
  unknown <- paths[is.na(tags)]
  if (length(unknown)) {
    stop(
      "No release tag for: ",
      paste(basename(unknown), collapse = ", "),
      call. = FALSE
    )
  }
  failed <- FALSE
  for (tag in unique(tags)) {
    tag_paths <- paths[tags == tag]
    withCallingHandlers(
      upload_to_github_release(
        files = tag_paths,
        repo = "eco-emma/emma_envdata",
        release_tag = tag,
        release_name = tag,
        overwrite = TRUE,
        verbose = TRUE
      ),
      warning = function(w) {
        if (grepl("failed to upload|still failed", conditionMessage(w),
                  ignore.case = TRUE)) {
          failed <<- TRUE
        }
      }
    )
  }
  if (failed) {
    stop(
      "Product upload failed. Targets cache was not updated.",
      call. = FALSE
    )
  }
  invisible(NULL)
}

ci_appeears_update <- function() {
  library(targets)
  source("R/tar_release_storage.R")
  source("R/upload_releases.R")

  message("[ci_appeears] Restoring targets metadata only")
  tar_download_github_release(
    repo = "eco-emma/emma_envdata",
    tag = "targets-cache",
    cache_dir = "_targets/user/cache",
    meta_only = TRUE,
    verbose = TRUE
  )
  meta_path <- "_targets/meta/meta"
  if (!file.exists(meta_path) || file.size(meta_path) == 0) {
    stop(
      "targets-cache meta was not restored. Prime on CCR before Actions.",
      call. = FALSE
    )
  }
  # Prevent _targets.R from re-downloading CCR meta on later tar_outdated()/
  # tar_make() parses and clobbering freshly built pending (run 38016708889).
  Sys.setenv(TAR_GH_META_RESTORED = "true")

  outdated <- .appeears_outdated()
  if (!length(outdated)) {
    message("[ci_appeears] No outdated AppEEARS targets")
    return(invisible(NULL))
  }
  message("[ci_appeears] Outdated before pending check: ",
          paste(utils::head(outdated, 20), collapse = ", "),
          if (length(outdated) > 20) paste0(" ... (", length(outdated), ")") else "")

  pending <- outdated[grepl("_pending$", outdated)]
  if (length(pending)) {
    message("[ci_appeears] Checking product releases via: ",
            paste(pending, collapse = ", "))
    targets::tar_make(names = pending, callr_function = NULL)
  }

  todo <- .appeears_outdated()
  todo <- todo[!grepl("_pending$", todo)]
  if (!length(todo)) {
    message("[ci_appeears] No new or unfinished AppEEARS months")
    return(invisible(NULL))
  }

  # Drop product stems whose pending table is empty. Building them would hit
  # targets' "cannot branch over empty target" error (seen 2026-10-05).
  todo <- .drop_empty_pending_stems(todo)
  if (!length(todo)) {
    message("[ci_appeears] No new or unfinished AppEEARS months")
    return(invisible(NULL))
  }

  # A code change marks every historical branch outdated. Skip branch names
  # that already finished successfully; leave them in the restored meta.
  # Do not pass names= to tar_progress()/tar_meta() — after a pending-only
  # tar_make those helpers only know the pending targets and tidyselect
  # errors on the remaining stems (failure in run 38015827855).
  todo <- .drop_already_built_branches(todo)
  if (!length(todo)) {
    message("[ci_appeears] No new or unfinished AppEEARS months")
    return(invisible(NULL))
  }
  message("[ci_appeears] Branches to build: ", length(todo))

  upstream <- .upstream_objects(todo)
  # Pattern stems would prefix-match every historical branch in the downloader.
  pattern_stems <- c(
    "vi_modis_task_ids", "vi_modis_geotiff", "vi_modis_grid", "vi_modis_parquet",
    "vi_viirs_task_ids", "vi_viirs_geotiff", "vi_viirs_grid", "vi_viirs_parquet",
    "burn_modis_task_ids", "burn_modis_geotiff", "burn_modis_grid", "burn_modis_parquet",
    "burn_viirs_task_ids", "burn_viirs_geotiff", "burn_viirs_grid", "burn_viirs_parquet"
  )
  # Freshly rebuilt pending must not be overwritten by the CCR cache. Doing so
  # resurrected full historical month lists after VI pending correctly returned
  # 0 rows (cancelled run 38010433480).
  pending_stems <- c(
    "vi_modis_pending", "vi_viirs_pending",
    "burn_modis_pending", "burn_viirs_pending"
  )
  upstream <- setdiff(upstream, c(pattern_stems, pending_stems))
  message("[ci_appeears] Upstream objects to restore: ", length(upstream))
  if (length(upstream)) {
    tar_download_github_release(
      repo = "eco-emma/emma_envdata",
      tag = "targets-cache",
      cache_dir = "_targets/user/cache",
      which_targets = upstream,
      verbose = TRUE
    )
  }

  targets::tar_make(names = todo, callr_function = NULL)

  product_branches <- todo[grepl(product_branch_pattern, todo)]
  .upload_product_files(.product_paths(product_branches))
  message("[ci_appeears] AppEEARS update finished")
  invisible(NULL)
}

if (sys.nframe() == 0L) {
  ci_appeears_update()
}
