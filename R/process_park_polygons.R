# =============================================================================
# Park products for emma_report → eco-emma/emma_envdata@static_data
#
# Inputs: flat shapefile assets from the `manual-data` release (no nested
# folders). Domain CRS / intersection mask from `domain.tif` on `static_data`
# (or the local geotargets domain.tif on CCR).
#
# Outputs (uploaded to `static_data`):
#   protected_areas.gpkg   — dissolved parks (name, type, area_ha); EPSG:9221
#   domain_outline.gpkg    — dissolved domain polygon (skip as.polygons on report)
#   parks_buffer_10km.gpkg — 10 km buffer of parks only (iNat AOI; no domain union)
#
# park_pids.parquet is intentionally omitted until domain/pid co-versioning exists.
# =============================================================================

#' Flat `manual-data` shapefile stems used by the park writers
#' @keywords internal
.manual_park_shapefile_stems <- function() {
  c(
    "SACAD_OR_2021_Q4",
    "SAPAD_OR_2021_Q4",
    "CapeNature_Reserves_gw"
  )
}

#' Required + optional sidecars for a shapefile stem (flat release asset names)
#' @keywords internal
.shapefile_sidecar_names <- function(stem) {
  required <- paste0(stem, c(".shp", ".shx", ".dbf", ".prj"))
  optional <- paste0(stem, c(".cpg", ".sbn", ".sbx"))
  list(required = required, optional = optional)
}

#' Download one release asset by flat name into dest_dir
#'
#' Uses the GitHub Releases download URL (public). Falls back to authenticated
#' API download when the public URL fails (private asset / rate limit).
#'
#' @param file Asset basename (no path separators).
#' @param dest_dir Local directory to write into.
#' @param repo Owner/repo string.
#' @param tag Release tag.
#' @param overwrite Re-download when the local file already exists?
#' @param token Optional GitHub token.
#' @return Absolute path to the downloaded file.
#' @export
download_release_asset_by_name <- function(
    file,
    dest_dir,
    repo = "eco-emma/emma_envdata",
    tag = "manual-data",
    overwrite = FALSE,
    token = NULL
) {
  if (grepl("[/\\\\]", file)) {
    stop(
      "Release assets must be flat names (no nested paths). Got: ", file,
      call. = FALSE
    )
  }
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(dest_dir, file)
  if (file.exists(dest) && !overwrite && file.size(dest) > 0) {
    return(normalizePath(dest, winslash = "/", mustWork = TRUE))
  }

  public_url <- sprintf(
    "https://github.com/%s/releases/download/%s/%s",
    repo, tag, utils::URLencode(file, reserved = TRUE)
  )
  ok <- tryCatch({
    utils::download.file(public_url, destfile = dest, mode = "wb", quiet = TRUE)
    file.exists(dest) && file.size(dest) > 0
  }, error = function(e) FALSE)

  if (!ok) {
    if (is.null(token) || !nzchar(token)) {
      token <- Sys.getenv("GITHUB_PAT", unset = Sys.getenv("GITHUB_TOKEN", unset = ""))
    }
    if (!nzchar(token) && exists(".gh_token", mode = "function")) {
      token <- tryCatch(.gh_token(), error = function(e) "")
    }
    parts <- strsplit(repo, "/", fixed = TRUE)[[1]]
    rel <- gh::gh(
      "GET /repos/{owner}/{repo}/releases/tags/{tag}",
      owner = parts[1], repo = parts[2], tag = tag,
      .token = if (nzchar(token)) token else NULL
    )
    asset <- Filter(function(a) identical(a$name, file), rel$assets)
    if (length(asset) == 0L) {
      stop("Asset '", file, "' not found on ", repo, "@", tag, call. = FALSE)
    }
    headers <- c(Accept = "application/octet-stream")
    if (nzchar(token)) {
      headers <- c(headers, Authorization = paste("token", token))
    }
    resp <- httr::GET(
      asset[[1]]$url,
      httr::add_headers(.headers = headers),
      httr::write_disk(dest, overwrite = TRUE),
      httr::timeout(600)
    )
    httr::stop_for_status(resp)
  }

  if (!file.exists(dest) || file.size(dest) == 0) {
    stop("Failed to download ", file, " from ", repo, "@", tag, call. = FALSE)
  }
  normalizePath(dest, winslash = "/", mustWork = TRUE)
}

#' Download flat SACAD / SAPAD / CapeNature shapefile assets from `manual-data`
#'
#' @param dest_dir Work directory for shapefile sidecars.
#' @param repo GitHub repository.
#' @param tag Input release tag (default `manual-data`).
#' @param overwrite Re-download existing files?
#' @return Named list of `.shp` paths: `sacad`, `sapad`, `cape_nature`.
#' @export
download_manual_park_shapefiles <- function(
    dest_dir = "data/temp/parks/manual-data",
    repo = "eco-emma/emma_envdata",
    tag = "manual-data",
    overwrite = FALSE
) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  stems <- .manual_park_shapefile_stems()
  shp_paths <- list()

  for (stem in stems) {
    parts <- .shapefile_sidecar_names(stem)
    for (asset in parts$required) {
      download_release_asset_by_name(
        file = asset, dest_dir = dest_dir, repo = repo, tag = tag,
        overwrite = overwrite
      )
    }
    for (asset in parts$optional) {
      tryCatch(
        download_release_asset_by_name(
          file = asset, dest_dir = dest_dir, repo = repo, tag = tag,
          overwrite = overwrite
        ),
        error = function(e) {
          message("Optional sidecar skipped (", asset, "): ", conditionMessage(e))
        }
      )
    }
    key <- switch(
      stem,
      "SACAD_OR_2021_Q4" = "sacad",
      "SAPAD_OR_2021_Q4" = "sapad",
      "CapeNature_Reserves_gw" = "cape_nature",
      stem
    )
    shp_paths[[key]] <- normalizePath(
      file.path(dest_dir, paste0(stem, ".shp")),
      winslash = "/", mustWork = TRUE
    )
  }

  shp_paths
}

#' Ensure a local `domain.tif` (CCR geotargets path or download from `static_data`)
#'
#' @param domain_tif Preferred local path (e.g. geotargets store). Used when present.
#' @param dest_dir Download destination when falling back to the release.
#' @param repo GitHub repository.
#' @param tag Release hosting `domain.tif` (default `static_data`).
#' @param overwrite Re-download?
#' @return Absolute path to `domain.tif`.
#' @export
ensure_domain_tif <- function(
    domain_tif = NULL,
    dest_dir = "data/temp/parks",
    repo = "eco-emma/emma_envdata",
    tag = "static_data",
    overwrite = FALSE
) {
  if (!is.null(domain_tif) && nzchar(domain_tif) && file.exists(domain_tif)) {
    return(normalizePath(domain_tif, winslash = "/", mustWork = TRUE))
  }
  local_default <- "data/target_outputs/domain.tif"
  if (file.exists(local_default) && !overwrite) {
    return(normalizePath(local_default, winslash = "/", mustWork = TRUE))
  }
  download_release_asset_by_name(
    file = "domain.tif",
    dest_dir = dest_dir,
    repo = repo,
    tag = tag,
    overwrite = overwrite
  )
}

#' Dissolved domain outline from `domain.tif` (EPSG:9221)
#'
#' @param domain_tif Path to domain raster.
#' @param out_file Output GeoPackage path.
#' @return `out_file` (invisible character).
#' @export
write_domain_outline_gpkg <- function(
    domain_tif,
    out_file = "data/target_outputs/domain_outline.gpkg"
) {
  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  domain_r <- terra::rast(domain_tif)
  mask_name <- if ("domain" %in% names(domain_r)) {
    "domain"
  } else {
    names(domain_r)[[1]]
  }
  # Match emma_report get_domain_polygon(): polygonize mask, then dissolve parts.
  domain_sf <- terra::as.polygons(
    domain_r[[mask_name]],
    values = TRUE,
    na.rm = TRUE
  ) |>
    sf::st_as_sf() |>
    sf::st_make_valid() |>
    sf::st_union() |>
    sf::st_as_sf()
  sf::st_geometry(domain_sf) <- "geometry"
  domain_sf$domain <- 1L
  domain_sf <- domain_sf[, c("domain", "geometry"), drop = FALSE]

  if (file.exists(out_file)) file.remove(out_file)
  sf::st_write(domain_sf, dsn = out_file, delete_dsn = TRUE, quiet = TRUE)
  normalizePath(out_file, winslash = "/", mustWork = TRUE)
}

#' Build dissolved protected-area polygons (ecological rules §0.1)
#'
#' SACAD/SAPAD: keep `SITE_TYPE` matching "national park" (case-insensitive).
#' CapeNature: `COMPLEX` → `name`, `RESERVECON` → `type`, `WMCM_TYPE = Provincial`.
#' Intersect domain; dissolve by `name` only; attrs `name`, `type`, `area_ha`;
#' CRS = domain template (EPSG:9221 Albers).
#'
#' @param sacad_shp,sapad_shp,cape_nature_shp Paths to input shapefiles.
#' @param domain_sf Domain outline `sf` (same CRS used for intersection).
#' @param out_file Output GeoPackage path.
#' @return `out_file`.
#' @export
write_protected_areas_gpkg <- function(
    sacad_shp,
    sapad_shp,
    cape_nature_shp,
    domain_sf,
    out_file = "data/target_outputs/protected_areas.gpkg"
) {
  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)

  sacad <- sf::st_read(sacad_shp, quiet = TRUE)
  sapad <- sf::st_read(sapad_shp, quiet = TRUE)
  cn <- sf::st_read(cape_nature_shp, quiet = TRUE)

  # Align SACAD columns to SAPAD before bind (report parity).
  if (!("PROC_DOC" %in% names(sacad))) {
    sacad$PROC_DOC <- NA
  }
  sacad <- dplyr::select(sacad, dplyr::all_of(colnames(sapad)))
  all_pas <- dplyr::bind_rows(sacad, sapad)
  rm(sacad, sapad)

  domain_sf <- domain_sf |>
    sf::st_make_valid() |>
    sf::st_union() |>
    sf::st_as_sf()

  all_pas <- sf::st_transform(all_pas, sf::st_crs(domain_sf))
  cn <- sf::st_transform(cn, sf::st_crs(domain_sf))

  all_pas <- all_pas[
    grepl("national park", all_pas$SITE_TYPE, ignore.case = TRUE),
  ]

  keep_pas <- lengths(sf::st_intersects(all_pas, domain_sf)) > 0L
  all_pas <- all_pas[keep_pas, ] |>
    sf::st_make_valid()

  keep_cn <- lengths(sf::st_intersects(cn, domain_sf)) > 0L
  cn <- cn[keep_cn, ] |>
    sf::st_make_valid()

  cn2 <- cn |>
    dplyr::mutate(WMCM_TYPE = "Provincial") |>
    dplyr::rename(CUR_NME = COMPLEX, SITE_TYPE = RESERVECON)

  protected_areas <- dplyr::bind_rows(all_pas, cn2) |>
    dplyr::select(name = CUR_NME, type = SITE_TYPE) |>
    dplyr::group_by(name) |>
    dplyr::summarise(
      type = dplyr::first(.data$type),
      geometry = sf::st_union(.data$geometry),
      .groups = "drop"
    )

  # area_ha in projected metres → hectares (EPSG:9221)
  protected_areas$area_ha <- as.numeric(sf::st_area(protected_areas)) / 1e4

  if (file.exists(out_file)) file.remove(out_file)
  sf::st_write(protected_areas, dsn = out_file, delete_dsn = TRUE, quiet = TRUE)
  normalizePath(out_file, winslash = "/", mustWork = TRUE)
}

#' 10 km buffer of dissolved parks only (iNat AOI; no domain union)
#'
#' @param protected_areas_gpkg Path to `protected_areas.gpkg`.
#' @param out_file Output GeoPackage path.
#' @param buffer_m Buffer distance in metres (default 10000).
#' @return `out_file`.
#' @export
write_parks_buffer_10km_gpkg <- function(
    protected_areas_gpkg,
    out_file = "data/target_outputs/parks_buffer_10km.gpkg",
    buffer_m = 10000
) {
  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  parks <- sf::st_read(protected_areas_gpkg, quiet = TRUE)
  aoi <- parks |>
    sf::st_union() |>
    sf::st_buffer(dist = buffer_m) |>
    sf::st_make_valid() |>
    sf::st_as_sf()
  sf::st_geometry(aoi) <- "geometry"
  aoi$aoi <- "parks_buffer_10km"
  aoi <- aoi[, c("aoi", "geometry"), drop = FALSE]

  if (file.exists(out_file)) file.remove(out_file)
  sf::st_write(aoi, dsn = out_file, delete_dsn = TRUE, quiet = TRUE)
  normalizePath(out_file, winslash = "/", mustWork = TRUE)
}

#' Build all three park static products (no upload)
#'
#' @param out_dir Directory for the three `.gpkg` outputs.
#' @param work_dir Scratch directory for flat `manual-data` downloads.
#' @param domain_tif Optional local `domain.tif`; otherwise download from `static_data`.
#' @param repo GitHub repository.
#' @param manual_tag Input tag for park shapefiles.
#' @param static_tag Tag hosting `domain.tif` (fallback download).
#' @param overwrite_inputs Re-download input assets?
#' @param verbose Print progress?
#' @return Character vector of the three output paths (named).
#' @export
build_park_static_products <- function(
    out_dir = "data/target_outputs",
    work_dir = "data/temp/parks",
    domain_tif = NULL,
    repo = "eco-emma/emma_envdata",
    manual_tag = "manual-data",
    static_tag = "static_data",
    overwrite_inputs = FALSE,
    verbose = TRUE
) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)

  if (verbose) message("Ensuring domain.tif ...")
  domain_tif <- ensure_domain_tif(
    domain_tif = domain_tif,
    dest_dir = work_dir,
    repo = repo,
    tag = static_tag,
    overwrite = overwrite_inputs
  )

  if (verbose) message("Writing domain_outline.gpkg from ", domain_tif)
  domain_outline <- write_domain_outline_gpkg(
    domain_tif = domain_tif,
    out_file = file.path(out_dir, "domain_outline.gpkg")
  )
  domain_sf <- sf::st_read(domain_outline, quiet = TRUE)

  if (verbose) message("Downloading flat park shapefiles from ", manual_tag, " ...")
  shps <- download_manual_park_shapefiles(
    dest_dir = file.path(work_dir, "manual-data"),
    repo = repo,
    tag = manual_tag,
    overwrite = overwrite_inputs
  )

  if (verbose) message("Writing protected_areas.gpkg ...")
  protected_areas <- write_protected_areas_gpkg(
    sacad_shp = shps$sacad,
    sapad_shp = shps$sapad,
    cape_nature_shp = shps$cape_nature,
    domain_sf = domain_sf,
    out_file = file.path(out_dir, "protected_areas.gpkg")
  )

  if (verbose) message("Writing parks_buffer_10km.gpkg (parks only) ...")
  parks_buffer <- write_parks_buffer_10km_gpkg(
    protected_areas_gpkg = protected_areas,
    out_file = file.path(out_dir, "parks_buffer_10km.gpkg")
  )

  out <- c(
    protected_areas = protected_areas,
    domain_outline = domain_outline,
    parks_buffer_10km = parks_buffer
  )
  if (verbose) {
    message(
      "Park static products ready:\n  - ",
      paste(basename(out), collapse = "\n  - ")
    )
  }
  out
}

#' Build park products and optionally upload them to `static_data`
#'
#' Prefer CCR for the first publish. The same function is GHA-capable
#' (downloads `domain.tif` from `static_data` when no local path is given).
#'
#' @param upload Upload via \code{upload_to_github_release()}?
#' @param ... Passed to \code{build_park_static_products()}.
#' @return Character vector of product paths.
#' @export
publish_park_static_products <- function(
    out_dir = "data/target_outputs",
    work_dir = "data/temp/parks",
    domain_tif = NULL,
    repo = "eco-emma/emma_envdata",
    manual_tag = "manual-data",
    static_tag = "static_data",
    upload = TRUE,
    overwrite_inputs = FALSE,
    verbose = TRUE
) {
  files <- build_park_static_products(
    out_dir = out_dir,
    work_dir = work_dir,
    domain_tif = domain_tif,
    repo = repo,
    manual_tag = manual_tag,
    static_tag = static_tag,
    overwrite_inputs = overwrite_inputs,
    verbose = verbose
  )

  if (isTRUE(upload)) {
    if (verbose) {
      message(
        "Uploading park products to ", repo, "@", static_tag,
        " (overwrite if checksum changed) ..."
      )
    }
    upload_to_github_release(
      files = unname(files),
      repo = repo,
      release_tag = static_tag,
      release_name = "Static Environmental Data",
      overwrite = TRUE,
      verbose = verbose
    )
  }

  files
}
