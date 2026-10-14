# =============================================================================
# iNaturalist invasives → eco-emma/emma_envdata@inat_data
#
# AOI (settled): parks_buffer_10km.gpkg from static_data — buffered parks only.
# Do NOT union with unbuffered domain.
#
# Output: inat_invasives.gpkg (WGS84) with columns
#   scientific_name, observed_on, longitude, latitude, invasive, geometry
#
# First publish: CCR after parks_buffer_10km.gpkg exists on static_data.
# GHA: dedicated workflow publish-inat (workflow_dispatch; nightly later).
# =============================================================================

#' Default invasive genus filters (parity with emma_report)
#' @keywords internal
.inat_invasive_taxa_default <- function() {
  c("Acacia", "Pinus", "Hakea", "Eucalyptus", "Leptospermum")
}

#' Empty invasives sf with the pinned §0.2 schema (WGS84)
#' @keywords internal
.empty_inat_invasives_sf <- function() {
  sf::st_sf(
    scientific_name = character(),
    observed_on = as.Date(character()),
    longitude = numeric(),
    latitude = numeric(),
    invasive = logical(),
    geometry = sf::st_sfc(crs = "WGS84")
  )
}

#' Resolve a GitHub token for release downloads
#' @keywords internal
.inat_github_token <- function() {
  token <- Sys.getenv("GITHUB_PAT", unset = "")
  if (!nzchar(token)) {
    token <- Sys.getenv("GITHUB_TOKEN", unset = "")
  }
  if (!nzchar(token) && exists(".gh_token", mode = "function")) {
    token <- tryCatch(.gh_token(), error = function(e) "")
  }
  if (!nzchar(token)) {
    token <- tryCatch(
      trimws(system("gh auth token", intern = TRUE, ignore.stderr = TRUE)[[1]]),
      error = function(e) ""
    )
  }
  if (is.na(token)) "" else token
}

#' Download a flat release asset by name into dest_dir
#'
#' Fails loud when the asset/tag is missing (no silent fallback).
#'
#' @param file Asset basename (no path separators).
#' @param dest_dir Local directory.
#' @param repo Owner/repo.
#' @param tag Release tag.
#' @param overwrite Re-download when local file exists?
#' @return Absolute path to the downloaded file.
#' @export
download_envdata_release_asset <- function(
    file,
    dest_dir,
    repo = "eco-emma/emma_envdata",
    tag,
    overwrite = FALSE
) {
  if (missing(tag) || !nzchar(tag)) {
    stop("`tag` is required.", call. = FALSE)
  }
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
    token <- .inat_github_token()
    parts <- strsplit(repo, "/", fixed = TRUE)[[1]]
    rel <- tryCatch(
      gh::gh(
        "GET /repos/{owner}/{repo}/releases/tags/{tag}",
        owner = parts[1], repo = parts[2], tag = tag,
        .token = if (nzchar(token)) token else NULL
      ),
      error = function(e) {
        stop(
          "Release tag '", tag, "' not found on ", repo, ": ",
          conditionMessage(e),
          call. = FALSE
        )
      }
    )
    asset <- Filter(function(a) identical(a$name, file), rel$assets)
    if (length(asset) == 0L) {
      stop(
        "Asset '", file, "' not found on ", repo, "@", tag,
        ". Publish parks_buffer_10km.gpkg to static_data first ",
        "(see docs/INAT_DATA_PUBLISH.md).",
        call. = FALSE
      )
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
    if (httr::http_error(resp) || !file.exists(dest) || file.size(dest) == 0) {
      stop(
        "Failed to download '", file, "' from ", repo, "@", tag,
        call. = FALSE
      )
    }
  }

  normalizePath(dest, winslash = "/", mustWork = TRUE)
}

#' Ensure parks_buffer_10km.gpkg is available locally
#'
#' @param aoi_gpkg Optional local path; otherwise download from static_data.
#' @param dest_dir Scratch directory for the download.
#' @param repo GitHub repository.
#' @param static_tag Tag hosting the AOI gpkg.
#' @param overwrite Re-download?
#' @return Absolute path to parks_buffer_10km.gpkg.
#' @export
ensure_parks_buffer_10km <- function(
    aoi_gpkg = NULL,
    dest_dir = "data/temp/inat",
    repo = "eco-emma/emma_envdata",
    static_tag = "static_data",
    overwrite = FALSE
) {
  if (!is.null(aoi_gpkg) && nzchar(aoi_gpkg)) {
    if (!file.exists(aoi_gpkg)) {
      stop("AOI gpkg not found: ", aoi_gpkg, call. = FALSE)
    }
    return(normalizePath(aoi_gpkg, winslash = "/", mustWork = TRUE))
  }
  download_envdata_release_asset(
    file = "parks_buffer_10km.gpkg",
    dest_dir = dest_dir,
    repo = repo,
    tag = static_tag,
    overwrite = overwrite
  )
}

#' Load invasive species names from the curated seed list
#'
#' Source of truth for which taxa to query on the live iNaturalist API.
#' Derived from the emma_report iNat project CSV (genus filter §0.1).
#'
#' @param species_csv Path to CSV with a `scientific_name` column.
#' @param invasive_taxa Genera / substrings used to filter the list.
#' @return Character vector of unique scientific names.
#' @export
load_inat_invasive_species <- function(
    species_csv = "data/inat_invasive_species.csv",
    invasive_taxa = .inat_invasive_taxa_default()
) {
  if (!file.exists(species_csv)) {
    stop("Species seed CSV not found: ", species_csv, call. = FALSE)
  }
  species_df <- utils::read.csv(species_csv, stringsAsFactors = FALSE)
  if (!("scientific_name" %in% names(species_df))) {
    stop(
      "Species CSV must have a scientific_name column: ", species_csv,
      call. = FALSE
    )
  }
  species_list <- unique(stats::na.omit(species_df$scientific_name))
  species_list <- species_list[nzchar(species_list)]
  pattern <- paste(invasive_taxa, collapse = "|")
  invasive_species <- grep(pattern, species_list, value = TRUE)
  if (length(invasive_species) == 0L) {
    stop(
      "No invasive species matched taxa [", pattern, "] in ", species_csv,
      call. = FALSE
    )
  }
  invasive_species
}

#' Numeric rinat bounds (min_lat, min_lon, max_lat, max_lon) from an sf AOI
#' @keywords internal
.inat_bounds_from_aoi <- function(aoi_wgs84) {
  bb <- sf::st_bbox(aoi_wgs84)
  c(bb[["ymin"]], bb[["xmin"]], bb[["ymax"]], bb[["xmax"]])
}

#' Query iNaturalist for invasive taxa within the buffered-parks AOI
#'
#' Uses \code{rinat::get_inat_obs()} per species (report parity), then
#' spatially filters to \code{parks_buffer_10km} only (no domain union).
#'
#' @param aoi_gpkg Path to parks_buffer_10km.gpkg (or other AOI polygon).
#' @param species_csv Curated scientific-name list.
#' @param invasive_taxa Genera filter applied to the seed list.
#' @param oldest_date Discard observations on or before this date (yyyy-mm-dd).
#' @param maxresults Per-species rinat cap.
#' @param sleep_sec Pause between species queries (API courtesy).
#' @param verbose Print progress?
#' @return sf with pinned schema; may have zero rows.
#' @export
harvest_inat_invasives <- function(
    aoi_gpkg,
    species_csv = "data/inat_invasive_species.csv",
    invasive_taxa = .inat_invasive_taxa_default(),
    oldest_date = "2020-01-01",
    maxresults = 10000L,
    sleep_sec = 1,
    verbose = TRUE
) {
  if (!requireNamespace("rinat", quietly = TRUE)) {
    stop(
      "Package 'rinat' is required (provided by adamwilsonlab/emma image).",
      call. = FALSE
    )
  }

  invasive_species <- load_inat_invasive_species(
    species_csv = species_csv,
    invasive_taxa = invasive_taxa
  )
  if (verbose) {
    message(
      "iNat harvest: ", length(invasive_species),
      " invasive taxa; AOI = ", aoi_gpkg
    )
  }

  aoi <- sf::st_read(aoi_gpkg, quiet = TRUE) |>
    sf::st_make_valid() |>
    sf::st_transform("WGS84") |>
    sf::st_union() |>
    sf::st_make_valid() |>
    sf::st_as_sf()
  bounds <- .inat_bounds_from_aoi(aoi)

  full_records <- NULL
  for (i in seq_along(invasive_species)) {
    if (verbose) {
      message(
        "Getting data for species ", i, " of ", length(invasive_species),
        ": ", invasive_species[[i]]
      )
    }
    data_i <- tryCatch(
      rinat::get_inat_obs(
        taxon_name = invasive_species[[i]],
        bounds = bounds,
        maxresults = maxresults
      ),
      error = function(e) e
    )
    # rinat often returns NULL when the API is down — not always an error.
    if (inherits(data_i, "error") ||
        is.null(data_i) ||
        !inherits(data_i, "data.frame") ||
        nrow(data_i) == 0L) {
      if (sleep_sec > 0) Sys.sleep(sleep_sec)
      next
    }

    data_i <- dplyr::filter(data_i, .data$observed_on > oldest_date)
    if (nrow(data_i) == 0L) {
      if (sleep_sec > 0) Sys.sleep(sleep_sec)
      next
    }

    data_i <- sf::st_as_sf(
      data_i,
      coords = c("longitude", "latitude"),
      remove = FALSE
    )
    sf::st_crs(data_i) <- sf::st_crs("WGS84")
    data_i <- sf::st_filter(data_i, aoi)
    if (nrow(data_i) == 0L) {
      if (sleep_sec > 0) Sys.sleep(sleep_sec)
      next
    }

    full_records <- dplyr::bind_rows(full_records, data_i)
    if (sleep_sec > 0) Sys.sleep(sleep_sec)
  }

  if (is.null(full_records) ||
      !inherits(full_records, "data.frame") ||
      nrow(full_records) == 0L) {
    warning(
      "No iNaturalist records retrieved (API unavailable, all empty, ",
      "or none inside parks_buffer_10km). Returning empty sf.",
      call. = FALSE
    )
    return(.empty_inat_invasives_sf())
  }

  out <- full_records |>
    dplyr::mutate(
      invasive = TRUE,
      observed_on = as.Date(.data$observed_on)
    ) |>
    dplyr::select(
      "scientific_name",
      "observed_on",
      "longitude",
      "latitude",
      "invasive",
      "geometry"
    )

  if (verbose) {
    message("iNat harvest rows after AOI filter: ", nrow(out))
  }
  out
}

#' Write inat_invasives.gpkg (WGS84) from an sf object
#'
#' @param invasives_sf sf from \code{harvest_inat_invasives()}.
#' @param out_file Output GeoPackage path.
#' @return Absolute path to \code{out_file}.
#' @export
write_inat_invasives_gpkg <- function(
    invasives_sf,
    out_file = "data/target_outputs/inat_invasives.gpkg"
) {
  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  if (is.null(invasives_sf) || nrow(invasives_sf) == 0L) {
    invasives_sf <- .empty_inat_invasives_sf()
  } else {
    invasives_sf <- sf::st_transform(invasives_sf, "WGS84")
    need <- c(
      "scientific_name", "observed_on", "longitude", "latitude", "invasive"
    )
    missing <- setdiff(need, names(invasives_sf))
    if (length(missing) > 0L) {
      stop(
        "inat_invasives missing columns: ", paste(missing, collapse = ", "),
        call. = FALSE
      )
    }
    invasives_sf <- invasives_sf[, c(need, "geometry"), drop = FALSE]
  }

  if (file.exists(out_file)) {
    file.remove(out_file)
  }
  sf::st_write(invasives_sf, dsn = out_file, delete_dsn = TRUE, quiet = TRUE)
  normalizePath(out_file, winslash = "/", mustWork = TRUE)
}

#' Build inat_invasives.gpkg (download AOI → harvest → write; no upload)
#'
#' @param out_dir Output directory for the gpkg.
#' @param work_dir Scratch directory.
#' @param aoi_gpkg Optional local parks_buffer_10km.gpkg.
#' @param species_csv Curated species list.
#' @param repo GitHub repository.
#' @param static_tag Tag for parks_buffer_10km.gpkg.
#' @param overwrite_aoi Re-download AOI?
#' @param verbose Print progress?
#' @param ... Passed to \code{harvest_inat_invasives()}.
#' @return Named character path \code{inat_invasives}.
#' @export
build_inat_invasives_product <- function(
    out_dir = "data/target_outputs",
    work_dir = "data/temp/inat",
    aoi_gpkg = NULL,
    species_csv = "data/inat_invasive_species.csv",
    repo = "eco-emma/emma_envdata",
    static_tag = "static_data",
    overwrite_aoi = FALSE,
    verbose = TRUE,
    ...
) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)

  if (verbose) {
    message("Ensuring parks_buffer_10km.gpkg from ", static_tag, " ...")
  }
  aoi_path <- ensure_parks_buffer_10km(
    aoi_gpkg = aoi_gpkg,
    dest_dir = work_dir,
    repo = repo,
    static_tag = static_tag,
    overwrite = overwrite_aoi
  )

  invasives_sf <- harvest_inat_invasives(
    aoi_gpkg = aoi_path,
    species_csv = species_csv,
    verbose = verbose,
    ...
  )

  out_file <- write_inat_invasives_gpkg(
    invasives_sf = invasives_sf,
    out_file = file.path(out_dir, "inat_invasives.gpkg")
  )
  if (verbose) {
    message("Wrote ", out_file)
  }
  c(inat_invasives = out_file)
}

#' Build and optionally upload inat_invasives.gpkg to the inat_data release
#'
#' Prefer CCR for the first publish (after parks buffer is on static_data).
#' The same function is GHA-capable via workflow_dispatch publish-inat.
#'
#' @param upload Upload via \code{upload_to_github_release()}?
#' @param inat_tag Release tag for the product.
#' @param ... Passed to \code{build_inat_invasives_product()}.
#' @return Character vector of product paths.
#' @export
publish_inat_invasives_product <- function(
    out_dir = "data/target_outputs",
    work_dir = "data/temp/inat",
    aoi_gpkg = NULL,
    species_csv = "data/inat_invasive_species.csv",
    repo = "eco-emma/emma_envdata",
    static_tag = "static_data",
    inat_tag = "inat_data",
    upload = TRUE,
    overwrite_aoi = FALSE,
    verbose = TRUE,
    ...
) {
  files <- build_inat_invasives_product(
    out_dir = out_dir,
    work_dir = work_dir,
    aoi_gpkg = aoi_gpkg,
    species_csv = species_csv,
    repo = repo,
    static_tag = static_tag,
    overwrite_aoi = overwrite_aoi,
    verbose = verbose,
    ...
  )

  if (isTRUE(upload)) {
    if (verbose) {
      message(
        "Uploading ", basename(files), " to ", repo, "@", inat_tag,
        " (overwrite if checksum changed) ..."
      )
    }
    upload_to_github_release(
      files = unname(files),
      repo = repo,
      release_tag = inat_tag,
      release_name = "iNaturalist invasive observations",
      overwrite = TRUE,
      verbose = verbose
    )
  }

  files
}
