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
# What this script does (in order):
#   1. Reads `tar_meta()` and finds every task_ids branch whose stored value
#      is a `rate_limited:...` sentinel (across MODIS VI, VIIRS VI, MODIS burn,
#      VIIRS burn, and elevation).
#   2. Deletes the corresponding local artifacts (all-NA `.tif` grid COGs,
#      `.skip` markers, and `.parquet` files) so `submit_*()` will re-check
#      AppEEARS instead of short-circuiting on the stale disk cache.
#   3. Optionally deletes matching assets from the GitHub release (so that
#      `gh_release_has_asset()` also stops short-circuiting).  Enable with
#      --delete-release-assets.
#   4. Calls `tar_invalidate()` on the stuck task_ids branches so they re-run
#      on the next `tar_make()`.  Their downstream branches will re-cascade
#      automatically because the branch output changes.
#
# Usage on the server:
#   Rscript recover_rate_limited.R                       # dry-run summary
#   Rscript recover_rate_limited.R --apply               # actually delete + invalidate
#   Rscript recover_rate_limited.R --apply --delete-release-assets
#                                                        # also clean release assets
#
# After running with --apply, run tar_make() as usual.
# ============================================================================

suppressPackageStartupMessages({
  library(targets)
})

args        <- commandArgs(trailingOnly = TRUE)
apply_changes <- "--apply" %in% args
delete_release <- "--delete-release-assets" %in% args

if (!apply_changes) {
  message("[recover] Running in dry-run mode. Re-run with --apply to actually ",
          "delete artifacts and invalidate branches.")
}

# ── 1. Target-specific artifact locations ──────────────────────────────────
# One record per rate-limited task_ids target.  `key_from_sentinel` extracts
# the YYYYMM / YYYYMMDD / elevation key from "rate_limited:<key>".
artifact_specs <- list(
  burn_modis_task_ids = list(
    dir   = "data/target_outputs/burndates",
    files = function(k) c(
      paste0("burn_modis_", k, ".tif"),
      paste0("burn_modis_", k, ".skip"),
      paste0("burn_modis_", k, ".parquet")
    ),
    release_tag = "burn_modis_raster"
  ),
  burn_viirs_task_ids = list(
    dir   = "data/target_outputs/burndates",
    files = function(k) c(
      paste0("burn_viirs_", k, ".tif"),
      paste0("burn_viirs_", k, ".skip"),
      paste0("burn_viirs_", k, ".parquet")
    ),
    release_tag = "burn_viirs_raster"
  ),
  vi_modis_task_ids = list(
    dir   = "data/target_outputs/modis_vi",
    files = function(k) c(
      paste0("vi_modis_terra_", k, ".tif"),
      paste0("vi_modis_aqua_",  k, ".tif"),
      paste0("vi_modis_",       k, ".skip"),
      paste0("vi_modis_",       k, ".parquet")
    ),
    release_tag = "vi_modis_raster"
  ),
  vi_viirs_task_ids = list(
    dir   = "data/target_outputs/viirs_vi",
    files = function(k) c(
      paste0("vi_viirs_snpp_",   k, ".tif"),
      paste0("vi_viirs_noaa20_", k, ".tif"),
      paste0("vi_viirs_",        k, ".skip"),
      paste0("vi_viirs_",        k, ".parquet")
    ),
    release_tag = "vi_viirs_raster"
  ),
  elevation_task_id = list(
    dir   = ".",
    files = function(k) character(0),  # elevation.tif lives in _targets/objects; tar_invalidate handles it
    release_tag = NA_character_
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

# ── 3. Report ──────────────────────────────────────────────────────────────
total_branches <- sum(vapply(stuck, length, integer(1)))
if (total_branches == 0L) {
  message("[recover] No rate_limited task_ids branches found. Nothing to do.")
  quit(save = "no", status = 0)
}

message("[recover] Found ", total_branches, " rate_limited task_ids branch(es):")
for (parent in names(stuck)) {
  keys <- vapply(stuck[[parent]], `[[`, character(1), "key")
  message("  - ", parent, ": ", length(keys), " branch(es) [",
          paste(utils::head(keys, 5), collapse = ", "),
          if (length(keys) > 5) ", ..." else "", "]")
}

# ── 4. Collect on-disk artifacts to remove ─────────────────────────────────
all_files <- unlist(lapply(stuck, function(bs) {
  unlist(lapply(bs, `[[`, "files"))
}), use.names = FALSE)
existing_files <- unique(all_files[file.exists(all_files)])

message("[recover] Local artifacts to delete: ", length(existing_files),
        " (of ", length(unique(all_files)), " candidate paths)")
if (length(existing_files) > 0 && length(existing_files) <= 20) {
  message("  - ", paste(existing_files, collapse = "\n  - "))
} else if (length(existing_files) > 20) {
  message("  (showing first 5) - ",
          paste(utils::head(existing_files, 5), collapse = "\n  - "))
}

# ── 5. Collect release assets to remove (optional) ─────────────────────────
release_assets_to_delete <- list()
if (delete_release) {
  # Group release-asset names by release tag
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
  n_release <- sum(vapply(release_assets_to_delete, length, integer(1)))
  message("[recover] Release assets to delete: ", n_release,
          " across ", length(release_assets_to_delete), " release(s)")
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
message("[recover] Deleted ", length(existing_files), " local artifact(s).")

# 6b. Delete release assets (if requested)
if (delete_release && length(release_assets_to_delete) > 0) {
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
      rel <- tryCatch(
        gh::gh("GET /repos/{owner}/{repo}/releases/tags/{tag}",
               owner = owner_repo[1], repo = owner_repo[2],
               tag = tag, .token = gh_token),
        error = function(e) NULL
      )
      if (is.null(rel)) {
        message("  ! release '", tag, "' not found; skipping")
        next
      }
      assets <- gh::gh("GET /repos/{owner}/{repo}/releases/{release_id}/assets",
                       owner = owner_repo[1], repo = owner_repo[2],
                       release_id = rel$id, .limit = Inf, .token = gh_token)
      hits <- Filter(function(a) a$name %in% names_to_del, assets)
      for (a in hits) {
        tryCatch({
          gh::gh("DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}",
                 owner = owner_repo[1], repo = owner_repo[2],
                 asset_id = a$id, .token = gh_token)
        }, error = function(e) {
          message("  ! failed to delete release asset ", a$name, ": ",
                  conditionMessage(e))
        })
      }
      message("  - release '", tag, "': deleted ", length(hits), " asset(s)")
    }
  }
}

# 6c. Invalidate task_ids branches (cascades to downstream on next tar_make)
all_branches <- unlist(lapply(stuck, function(bs) {
  vapply(bs, `[[`, character(1), "branch_name")
}), use.names = FALSE)
targets::tar_invalidate(any_of(all_branches))
message("[recover] Invalidated ", length(all_branches), " task_ids branch(es).")

message("\n[recover] Done. Run tar_make() next to re-submit and download.")
