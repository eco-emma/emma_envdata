# GitHub Actions entry point. Restores targets metadata, rebuilds only
# outdated MODIS/VIIRS VI and burned-area branches, and uploads the new
# COGs and parquets. After product upload, refreshes stac-vi (+ decade
# item releases) from GitHub release asset names so report latest-date
# advances without a CCR pass. Aggregate burn/static STAC and fireage
# still belong on CCR (they need the full historical branch set).
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

product_stem_pattern <- paste0(
  "^(vi_modis|vi_viirs|burn_modis|burn_viirs)_",
  "(grid|parquet)$"
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

# Flatten tar_read_raw() values (character paths, or list of those from a
# pattern stem) into a character vector of file paths.
.flatten_product_paths <- function(value) {
  if (is.null(value)) return(character(0))
  if (is.character(value)) return(value)
  if (is.list(value)) {
    return(unlist(lapply(value, .flatten_product_paths), use.names = FALSE))
  }
  character(0)
}

.product_paths <- function(target_names) {
  paths <- character(0)
  for (name in target_names) {
    value <- tryCatch(
      targets::tar_read_raw(name),
      error = function(e) {
        message(
          "[ci_appeears] No product from ", name, ": ",
          conditionMessage(e)
        )
        NULL
      }
    )
    paths <- c(paths, .flatten_product_paths(value))
  }
  paths <- unique(paths)
  paths[file.exists(paths) & !grepl("\\.skip$", paths)]
}

# After tar_make(), `todo` is often pattern stems (vi_modis_grid, …), not
# branch-hash names. Prefer freshly built product branches from progress;
# also resolve any pattern stems still listed in `todo`.
.product_target_names_for_upload <- function(todo) {
  names <- character(0)

  progress <- tryCatch(
    targets::tar_progress(),
    error = function(e) NULL
  )
  if (!is.null(progress) && nrow(progress)) {
    built <- progress$name[progress$progress == "built"]
    names <- c(names, built[grepl(product_branch_pattern, built)])
  }

  # Defensive: keep any branch-hash names still present in todo.
  names <- c(names, todo[grepl(product_branch_pattern, todo)])

  # Pattern stems must be read as wholes; tar_read_raw() returns every
  # child that is in the local store. file.exists() later keeps only
  # products written on this runner.
  stems <- todo[grepl(product_stem_pattern, todo)]
  names <- c(names, stems)

  unique(names)
}

# COGs/parquets written under data/target_outputs/ this session. Used when
# todo is pattern stems and tar_read_raw(stem) cannot load historical
# children missing from the Actions store (meta-only restore).
.local_product_files <- function() {
  specs <- list(
    list(
      dir = "data/target_outputs/modis_vi",
      pattern = paste0(
        "^vi_modis_(terra|aqua)_[0-9]{8}\\.tif$",
        "|^vi_modis_[0-9]{8}\\.parquet$"
      )
    ),
    list(
      dir = "data/target_outputs/viirs_vi",
      pattern = paste0(
        "^vi_viirs_(snpp|noaa20)_[0-9]{8}\\.tif$",
        "|^vi_viirs_[0-9]{8}\\.parquet$"
      )
    ),
    list(
      dir = "data/target_outputs/burndates",
      pattern = paste0(
        "^burn_(modis|viirs)_[0-9]{6}\\.(tif|parquet)$"
      )
    )
  )
  paths <- character(0)
  for (spec in specs) {
    if (!dir.exists(spec$dir)) next
    paths <- c(
      paths,
      list.files(spec$dir, pattern = spec$pattern, full.names = TRUE)
    )
  }
  unique(paths)
}

.collect_product_paths <- function(todo) {
  from_targets <- .product_paths(.product_target_names_for_upload(todo))
  from_disk <- .local_product_files()
  unique(c(from_targets, from_disk))
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
    return(invisible(character(0)))
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
  uploaded <- character(0)
  for (tag in unique(tags)) {
    tag_paths <- paths[tags == tag]
    withCallingHandlers(
      {
        result <- upload_to_github_release(
          files = tag_paths,
          repo = "eco-emma/emma_envdata",
          release_tag = tag,
          release_name = tag,
          overwrite = TRUE,
          verbose = TRUE
        )
        uploaded <- c(uploaded, result)
      },
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
  invisible(unique(uploaded))
}

# Composite YYYYMMDD strings for VI COGs that landed in `paths`.
.vi_dates_from_paths <- function(paths) {
  bn <- basename(paths)
  vi_bn <- bn[grepl(
    "^vi_(modis_(terra|aqua)|viirs_(snpp|noaa20))_[0-9]{8}\\.tif$",
    bn
  )]
  if (!length(vi_bn)) return(character(0))
  unique(regmatches(vi_bn, regexpr("[0-9]{8}", vi_bn)))
}

# Rebuild stac-vi (+ decade items) from release asset names so Actions can
# advance the report's latest STAC date after COGs publish. Only uploads the
# collection JSON plus items for `new_dates` (historical item JSONs stay).
.refresh_vi_stac <- function(new_dates, repo = "eco-emma/emma_envdata") {
  if (!length(new_dates)) {
    message("[ci_appeears] No new VI composite dates for STAC refresh")
    return(invisible(NULL))
  }

  source("R/stac_functions.R")

  token <- Sys.getenv("GITHUB_PAT")
  if (!nzchar(token)) token <- Sys.getenv("GITHUB_TOKEN")
  if (!nzchar(token)) {
    warning(
      "[ci_appeears] No GitHub token; skipping STAC refresh. ",
      "Run generate_modis_vi_stac + upload_stac_vi on CCR.",
      call. = FALSE
    )
    return(invisible(NULL))
  }

  terra_assets <- .gh_release_asset_names(
    repo, "vi_modis_terra_raster", token
  )
  aqua_assets <- .gh_release_asset_names(
    repo, "vi_modis_aqua_raster", token
  )
  viirs_assets <- .gh_release_asset_names(
    repo, "vi_viirs_raster", token
  )

  terra_tifs <- grep(
    "^vi_modis_terra_[0-9]{8}\\.tif$", terra_assets, value = TRUE
  )
  aqua_tifs <- grep(
    "^vi_modis_aqua_[0-9]{8}\\.tif$", aqua_assets, value = TRUE
  )
  viirs_tifs <- grep(
    "^vi_viirs_(snpp|noaa20)_[0-9]{8}\\.tif$", viirs_assets, value = TRUE
  )

  if (!length(terra_tifs) || !length(aqua_tifs)) {
    warning(
      "[ci_appeears] STAC refresh skipped: terra/aqua release assets missing",
      call. = FALSE
    )
    return(invisible(NULL))
  }

  # Synthetic paths — generate_modis_vi_stac() only needs basenames for HREFs.
  modis_paths <- file.path(
    "data/target_outputs/modis_vi",
    c(terra_tifs, aqua_tifs)
  )
  viirs_paths <- file.path("data/target_outputs/viirs_vi", viirs_tifs)

  message(
    "[ci_appeears] Refreshing stac-vi from release assets (",
    length(terra_tifs), " terra, ", length(aqua_tifs), " aqua, ",
    length(viirs_tifs), " viirs); new dates: ",
    paste(sort(new_dates), collapse = ", ")
  )

  stac_files <- generate_modis_vi_stac(
    tif_files = modis_paths,
    viirs_tif_files = viirs_paths,
    stac_dir = "data/stac/vi",
    parent_catalog_path = "data/stac",
    gh_repo = repo,
    gh_release_tag_modis_terra = "vi_modis_terra_raster",
    gh_release_tag_modis_aqua = "vi_modis_aqua_raster",
    gh_release_tag_viirs = "vi_viirs_raster",
    gh_stac_release_tag = "stac-vi",
    gh_stac_item_release_prefix = "stac-vi",
    gh_root_stac_release_tag = "stac",
    verbose = TRUE
  )

  collection_file <- stac_files[basename(stac_files) == "vi_collection.json"]
  new_item_files <- stac_files[
    basename(stac_files) %in% paste0("vi_", new_dates, ".json")
  ]
  new_item_files <- new_item_files[file.exists(new_item_files)]

  if (length(collection_file) && file.exists(collection_file)) {
    upload_to_github_release(
      files = collection_file,
      repo = repo,
      release_tag = "stac-vi",
      release_name = "STAC - Vegetation Indices",
      overwrite = TRUE,
      verbose = TRUE
    )
  }

  if (length(new_item_files)) {
    item_years <- substr(basename(new_item_files), 4L, 7L)
    item_decades <- paste0(substr(item_years, 1L, 3L), "0s")
    purrr::iwalk(
      split(new_item_files, item_decades),
      function(files, decade) {
        upload_to_github_release(
          files = files,
          repo = repo,
          release_tag = paste0("stac-vi-", decade),
          release_name = paste("STAC - Vegetation Indices", decade),
          overwrite = TRUE,
          verbose = TRUE
        )
      }
    )
  }

  message("[ci_appeears] stac-vi refresh finished")
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

  # todo is often pattern stems after pending rebuild; resolve via progress
  # branch-hashes, tar_read_raw on stems, and a local output-dir scan
  # (W1.1 / W1.3 / W1.4). upload_to_github_release() checksum-skips
  # unchanged assets, so scanning locals is safe.
  product_names <- .product_target_names_for_upload(todo)
  message(
    "[ci_appeears] Product targets for upload: ",
    if (length(product_names)) {
      paste(product_names, collapse = ", ")
    } else {
      "(none)"
    }
  )
  product_paths <- .collect_product_paths(todo)
  if (length(product_paths)) {
    message(
      "[ci_appeears] Local product files to publish: ",
      paste(basename(product_paths), collapse = ", ")
    )
  }
  uploaded_paths <- .upload_product_files(product_paths)

  # W1.2: advance stac-vi after VI COGs land. Uses release asset listing so
  # Actions does not need every historical COG on disk.
  vi_dates <- .vi_dates_from_paths(product_paths)
  if (length(vi_dates)) {
    .refresh_vi_stac(vi_dates)
  } else {
    message(
      "[ci_appeears] No VI COGs in this publish set; stac-vi unchanged. ",
      "Burn/static STAC remain CCR (tar_make upload_stac_*)."
    )
  }

  message("[ci_appeears] AppEEARS update finished")
  invisible(uploaded_paths)
}

if (sys.nframe() == 0L) {
  ci_appeears_update()
}
