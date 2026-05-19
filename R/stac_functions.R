#' @title Generate STAC Collection for MODIS VI dataset
#' @description Creates a STAC Collection and individual Item files for monthly MODIS VI parquet data.
#' Items are configured to point to GitHub release URLs.
#' This is a dataset-specific collection that will be linked from a parent STAC Catalog.
#' @author EMMA Team
#' @param parquet_files Character vector of processed parquet file paths (from targets branching; used to establish dependency)
#' @param parquet_dir Directory containing monthly MODIS VI parquet files
#' @param stac_dir Output directory for this collection's STAC JSON files
#' @param parent_catalog_path Path to parent catalog (for generating relative links)
#' @param gh_repo GitHub repository in format "owner/repo"
#' @param gh_release_tag GitHub release tag where files will be hosted
#' @param verbose Logical for progress messages
#' @return Character path to collection.json for this dataset
#' @keywords internal
generate_modis_vi_stac <- function(
  parquet_files = NULL,  # Dependency on branched target, may be unused
  parquet_dir = "data/processed_data/dynamic_parquet/modis_vi",
  stac_dir = "data/stac/modis_vi",
  parent_catalog_path = "data/stac",
  gh_repo = "AdamWilsonLab/emma_envdata",
  gh_release_tag = "data_modis_vi_current",
  verbose = TRUE
) {
  
  # Create output directory
  dir.create(stac_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Find all monthly parquet files
  parquet_files <- list.files(
    parquet_dir,
    pattern = "^dynamic_modis_vi_\\d{6}\\.parquet$",
    full.names = FALSE
  )
  
  if (length(parquet_files) == 0) {
    stop("No MODIS VI parquet files found in ", parquet_dir,
         ". Check that modis_vi_parquet targets completed successfully.")
  }
  
  # Extract year-month from filenames
  dates <- as.Date(paste0(gsub(".*_(\\d{6})\\..*", "\\1", parquet_files), "01"), "%Y%m%d")
  
  if (verbose) message("Generating STAC Collection for MODIS VI with ", length(parquet_files), " monthly files")
  
  # Create STAC Collection (part of parent catalog)
  collection <- list(
    stac_version = "1.0.0",
    stac_extensions = list(
      "https://stac-extensions.github.io/scientific/v1.0.0/schema.json"
    ),
    type = "Collection",
    id = "modis_vi",
    description = "MODIS Enhanced Vegetation Index (EVI) observations from Terra and Aqua satellites. 500m resolution, 16-day composites. Data processed from AppEEARS.",
    license = "CC-BY-4.0",
    keywords = c("MODIS", "EVI", "vegetation", "Terra", "Aqua", "500m", "16-day"),
    extent = list(
      spatial = list(
        bbox = list(c(-180, -90, 180, 90))
      ),
      temporal = list(
        interval = list(c(
          paste0(format(min(dates), "%Y-%m-%d"), "T00:00:00Z"),
          paste0(format(max(dates), "%Y-%m-%d"), "T23:59:59Z")
        ))
      )
    ),
    links = list(
      list(
        rel = "root",
        href = "catalog.json",
        type = "application/json"
      ),
      list(
        rel = "parent",
        href = "catalog.json",
        type = "application/json"
      ),
      list(
        rel = "license",
        href = "https://creativecommons.org/licenses/by/4.0/",
        type = "text/html"
      ),
      list(
        rel = "about",
        href = "https://lpdaac.usgs.gov/products/mod13a1v061/",
        title = "MOD13A1.061 Product Information",
        type = "text/html"
      )
    ),
    providers = list(
      list(
        name = "USGS LP DAAC",
        description = "Data source for MOD13A1 and MYD13A1",
        roles = c("producer", "licensor"),
        url = "https://lpdaac.usgs.gov/"
      ),
      list(
        name = "NASA AppEEARS",
        description = "Data access and subsetting service",
        roles = list("processor"),
        url = "https://appeears.org/"
      ),
      list(
        name = "EMMA Lab",
        description = "Data processing and aggregation",
        roles = list("processor"),
        url = "https://adamwilsonlab.github.io/"
      )
    ),
    summaries = list(
      sci_doi = "10.5067/MODIS/MOD13A1.061|10.5067/MODIS/MYD13A1.061",
      platforms = c("Terra", "Aqua"),
      instruments = list("MODIS"),
      gsd = list(500),
      bands = list(
        list(
          name = "EVI",
          description = "Enhanced Vegetation Index",
          data_type = "int32",
          scale = 0.01,
          offset = 0,
          nodata = -9999
        )
      )
    )
  )
  
  # Write collection JSON with collection_id prefix to avoid filename collision on flat releases
  collection_file <- file.path(stac_dir, "modis_vi_collection.json")
  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)
  
  if (verbose) message("Created STAC Collection: ", collection_file)
  
  # Create individual Item files
  for (i in seq_along(parquet_files)) {
    pq_file <- parquet_files[i]
    pq_date <- dates[i]
    year_month <- format(pq_date, "%Y%m")
    
    # GitHub release URL — GitHub releases store files flat (no subdirs),
    # so only the basename is needed in the URL.
    gh_raw_url <- paste0(
      "https://github.com/", gh_repo, "/releases/download/", gh_release_tag, "/",
      basename(pq_file)
    )
    
    item <- list(
      stac_version = "1.0.0",
      stac_extensions = list(
        "https://stac-extensions.github.io/scientific/v1.0.0/schema.json"
      ),
      type = "Feature",
      id = paste0("modis_vi_", year_month),
      description = paste("MODIS EVI observations for", format(pq_date, "%B %Y")),
      geometry = list(
        type = "Polygon",
        coordinates = list(list(
          c(-180, -90), c(180, -90), c(180, 90), c(-180, 90), c(-180, -90)
        ))
      ),
      bbox = c(-180, -90, 180, 90),
      properties = list(
        `datetime` = paste0(format(pq_date, "%Y-%m-%d"), "T00:00:00Z"),
        start_datetime = paste0(format(pq_date, "%Y-%m-01"), "T00:00:00Z"),
        end_datetime = paste0(format(as.Date(paste0(format(pq_date + 31, "%Y-%m"), "-01")) - 1, "%Y-%m-%d"), "T23:59:59Z"),
        platforms = c("Terra", "Aqua"),
        instruments = list("MODIS"),
        gsd = 500,
        dataset = "modis_vi"
      ),
      links = list(
        list(
          rel = "collection",
          href = "modis_vi_collection.json",
          type = "application/json"
        ),
        list(
          rel = "root",
          href = "catalog.json",
          type = "application/json"
        ),
        list(
          rel = "parent",
          href = "modis_vi_collection.json",
          type = "application/json"
        )
      ),
      assets = list(
        data = list(
          href = gh_raw_url,
          title = paste0("MODIS VI Parquet - ", year_month),
          description = "Enhanced Vegetation Index observations in parquet format",
          type = "application/octet-stream",
          roles = list("data")
        )
      )
    )
    
    item_file <- file.path(stac_dir, paste0("modis_vi_", year_month, ".json"))
    jsonlite::write_json(item, item_file, pretty = TRUE, auto_unbox = TRUE)
    
    # Add item link to collection
    collection$links[[length(collection$links) + 1]] <- list(
      rel = "item",
      href = paste0("modis_vi_", year_month, ".json"),
      type = "application/json",
      title = paste("MODIS VI", year_month)
    )
  }
  
  # Update collection.json with all item links
  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)
  
  if (verbose) message("Generated ", length(parquet_files), " STAC Item files")
  
  collection_file
}


#' @title Generate parent STAC Catalog for EMMA environmental datasets
#' @description Creates a parent STAC Catalog that organizes and links all EMMA datasets
#' (MODIS VI, VIIRS VI, burned area, age, etc.).
#' @author EMMA Team
#' @param stac_base_dir Base directory for STAC output (datasets will be in subdirectories)
#' @param dataset_collections List of dataset collection paths (e.g., list(modis_vi = "data/stac/modis_vi"))
#' @param gh_repo GitHub repository in format "owner/repo"
#' @param verbose Logical for progress messages
#' @return Character path to parent catalog.json
#' @keywords internal
generate_emma_stac_catalog <- function(
  stac_base_dir = "data/stac",
  dataset_collections = list(
    modis_vi = "data/stac/modis_vi"
  ),
  gh_repo = "AdamWilsonLab/emma_envdata",
  verbose = TRUE
) {
  
  dir.create(stac_base_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Create parent STAC Catalog
  catalog <- list(
    stac_version = "1.0.0",
    type = "Catalog",
    id = "emma",
    description = "EMMA Environmental Data Catalog - A curated collection of environmental datasets for the Eastern Mediterranean and Maghreb region.",
    links = list(
      list(
        rel = "root",
        href = "catalog.json",
        type = "application/json",
        title = "EMMA Catalog"
      ),
      list(
        rel = "license",
        href = "https://creativecommons.org/licenses/by/4.0/",
        type = "text/html",
        title = "Creative Commons Attribution 4.0"
      ),
      list(
        rel = "about",
        href = paste0("https://github.com/", gh_repo),
        type = "text/html",
        title = "EMMA Project Repository"
      )
    )
  )
  
  if (verbose) message("Creating parent STAC Catalog with ", length(dataset_collections), " dataset(s)")
  
  # Add links to each dataset collection
  for (dataset_name in names(dataset_collections)) {
    collection_path <- dataset_collections[[dataset_name]]
    collection_file <- file.path(collection_path, paste0(dataset_name, "_collection.json"))
    
    if (file.exists(collection_file)) {
      # Flat href — GitHub releases store all JSON files without subdirectories
      rel_path <- paste0(dataset_name, "_collection.json")
      
      catalog$links[[length(catalog$links) + 1]] <- list(
        rel = "child",
        href = rel_path,
        type = "application/json",
        title = paste0(dataset_name, " - Dynamic VI observations")
      )
      
      if (verbose) message("  Linked collection: ", dataset_name)
    } else {
      if (verbose) warning("Collection not found: ", collection_file)
    }
  }
  
  # Write parent catalog
  catalog_file <- file.path(stac_base_dir, "catalog.json")
  jsonlite::write_json(catalog, catalog_file, pretty = TRUE, auto_unbox = TRUE)
  
  if (verbose) message("Created parent STAC Catalog: ", catalog_file)
  
  catalog_file
}


# ============================================================================
# STAC for burned area datasets (MODIS MCD64A1 and VIIRS VNP64A1)
# ============================================================================

#' @title Generate STAC Collection for burned area datasets
#'
#' @description Creates a STAC Collection and individual Item JSON files for
#'   monthly burned area parquets produced by the MODIS (MCD64A1.061) or VIIRS
#'   (VNP64A1.002) fire pipelines.
#'
#'   The function is shared between both sensors; pass \code{source = "modis"} or
#'   \code{source = "viirs"} to select the correct metadata.
#'
#' @param parquet_files Character vector of parquet file paths (all months for this sensor).
#' @param parquet_dir   Character. Directory containing parquets (used to scan for files
#'   when \code{parquet_files} is NULL).
#' @param stac_dir      Character. Output directory for collection.json + item files.
#' @param parent_catalog_path Character. Path to parent STAC catalog directory.
#' @param gh_repo       Character. GitHub repo in "owner/repo" format.
#' @param gh_release_tag Character. GitHub release tag used when constructing download URLs.
#' @param source        Character. One of \code{"modis"} or \code{"viirs"}.
#' @param verbose       Logical. Print progress messages?
#'
#' @return Character path to the collection.json file.
#' @export
generate_burn_dates_stac <- function(
    parquet_files      = NULL,
    parquet_dir        = NULL,
    stac_dir,
    parent_catalog_path = "data/stac",
    gh_repo            = "AdamWilsonLab/emma_envdata",
    gh_release_tag,
    source             = c("modis", "viirs"),
    verbose            = TRUE) {

  source <- match.arg(source)

  # ── Sensor-specific metadata ─────────────────────────────────────────────
  sensor_meta <- list(
    modis = list(
      title       = "MODIS Burned Area Monthly (MCD64A1 v061)",
      description = paste(
        "Monthly burned area detections derived from NASA MODIS MCD64A1.061 (500m).",
        "Each row represents a pixel that burned in that calendar month.",
        "Only confirmed burned pixels (QA flag 0) are retained.",
        "Pixel IDs (pid) align with the EMMA domain grid."
      ),
      sci_doi     = "10.5067/MODIS/MCD64A1.061",
      platforms   = list("Terra"),
      instruments = list("MODIS"),
      gsd         = 500,
      about_url   = "https://lpdaac.usgs.gov/products/mcd64a1v061/",
      start_date  = "2000-11-01",
      id_prefix   = "burn_dates_modis",
      bands       = list(
        list(name = "burn_doy", description = "Day of year of burn detection (0 = unburned)", data_type = "int16"),
        list(name = "qa",       description = "QA flag (0 = good quality)",                  data_type = "int8")
      )
    ),
    viirs = list(
      title       = "VIIRS Burned Area Monthly (VNP64A1 v002)",
      description = paste(
        "Monthly burned area detections derived from NASA VIIRS VNP64A1.002 (375m, resampled to 500m).",
        "Available from January 2012 onward.",
        "Only confirmed burned pixels (QA flag 0) are retained.",
        "Pixel IDs (pid) align with the EMMA domain grid."
      ),
      sci_doi     = "10.5067/VIIRS/VNP64A1.002",
      platforms   = list("Suomi NPP"),
      instruments = list("VIIRS"),
      gsd         = 375,
      about_url   = "https://lpdaac.usgs.gov/products/vnp64a1v002/",
      start_date  = "2012-01-01",
      id_prefix   = "burn_dates_viirs",
      bands       = list(
        list(name = "burn_doy", description = "Day of year of burn detection (0 = unburned)", data_type = "int16"),
        list(name = "qa",       description = "QA flag (0 = good quality)",                  data_type = "int8")
      )
    )
  )
  meta <- sensor_meta[[source]]

  dir.create(stac_dir, recursive = TRUE, showWarnings = FALSE)

  # Resolve parquet files if not supplied directly
  if (is.null(parquet_files) || length(parquet_files) == 0) {
    parquet_files <- list.files(
      parquet_dir %||% stac_dir,
      pattern    = "\\.parquet$",
      full.names = TRUE
    )
  }

  # Extract dates from filenames: e.g., "burn_dates_modis_200011.parquet"
  dates <- parquet_files |>
    basename() |>
    stringr::str_extract("\\d{6}") |>
    (\(ym) as.Date(paste0(ym, "01"), format = "%Y%m%d"))()

  parquet_files <- parquet_files[!is.na(dates)]
  dates         <- dates[!is.na(dates)]

  if (verbose) {
    message(
      "Generating ", source, " burn dates STAC collection: ",
      length(parquet_files), " items (", min(dates), " to ", max(dates), ")"
    )
  }

  # ── Build STAC Collection ────────────────────────────────────────────────
  collection <- list(
    stac_version = "1.0.0",
    stac_extensions = list("https://stac-extensions.github.io/scientific/v1.0.0/schema.json"),
    type        = "Collection",
    id          = meta$id_prefix,
    title       = meta$title,
    description = meta$description,
    license     = "proprietary",
    extent = list(
      spatial  = list(bbox = list(list(-180, -90, 180, 90))),
      temporal = list(interval = list(list(
        paste0(meta$start_date, "T00:00:00Z"),
        NULL
      )))
    ),
    links = list(
      list(rel = "root",    href = "catalog.json", type = "application/json"),
      list(rel = "self",    href = paste0(meta$id_prefix, "_collection.json"), type = "application/json"),
      list(rel = "license", href = "https://creativecommons.org/licenses/by/4.0/", type = "text/html"),
      list(rel = "about",   href = meta$about_url, title = meta$title, type = "text/html")
    ),
    providers = list(
      list(name = "NASA LP DAAC", roles = c("producer", "licensor"), url = "https://lpdaac.usgs.gov/"),
      list(name = "NASA AppEEARS", roles = list("processor"),           url = "https://appeears.org/"),
      list(name = "EMMA Lab",      roles = list("processor"),           url = "https://adamwilsonlab.github.io/")
    ),
    summaries = list(
      sci_doi     = meta$sci_doi,
      platforms   = meta$platforms,
      instruments = meta$instruments,
      gsd         = list(meta$gsd),
      bands       = meta$bands
    )
  )

  collection_file <- file.path(stac_dir, paste0(meta$id_prefix, "_collection.json"))
  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)

  # ── Build STAC Items (one per parquet file) ───────────────────────────────
  # Use purrr::pmap() for clean iteration over parallel vectors — no for loops
  item_files <- purrr::pmap_chr(
    list(pq_file = parquet_files, pq_date = dates),
    function(pq_file, pq_date) {

      year_month <- format(pq_date, "%Y%m")
      month_end  <- as.Date(paste0(format(pq_date + 31, "%Y-%m"), "-01")) - 1

      gh_url <- paste0(
        "https://github.com/", gh_repo,
        "/releases/download/", gh_release_tag, "/",
        basename(pq_file)
      )

      item <- list(
        stac_version = "1.0.0",
        stac_extensions = list("https://stac-extensions.github.io/scientific/v1.0.0/schema.json"),
        type        = "Feature",
        id          = paste0(meta$id_prefix, "_", year_month),
        description = paste(source, "burned area detections for", format(pq_date, "%B %Y")),
        geometry = list(
          type = "Polygon",
          coordinates = list(list(
            c(-180, -90), c(180, -90), c(180, 90), c(-180, 90), c(-180, -90)
          ))
        ),
        properties = list(
          datetime        = paste0(format(pq_date, "%Y-%m-%d"), "T00:00:00Z"),
          start_datetime  = paste0(format(pq_date, "%Y-%m-01"), "T00:00:00Z"),
          end_datetime    = paste0(format(month_end, "%Y-%m-%d"), "T23:59:59Z"),
          platforms       = meta$platforms,
          instruments     = meta$instruments,
          gsd             = meta$gsd,
          dataset         = meta$id_prefix
        ),
        links = list(
          list(rel = "collection", href = paste0(meta$id_prefix, "_collection.json"),  type = "application/json"),
          list(rel = "root",       href = "catalog.json",                           type = "application/json"),
          list(rel = "parent",     href = paste0(meta$id_prefix, "_collection.json"),  type = "application/json")
        ),
        assets = list(
          data = list(
            href        = gh_url,
            title       = paste0(toupper(source), " burned area parquet — ", year_month),
            description = "Burned pixels in this month (pid, date, burn_doy, qa) in gzip-compressed Parquet",
            type        = "application/octet-stream",
            roles       = list("data")
          )
        )
      )

      item_file <- file.path(stac_dir, paste0(meta$id_prefix, "_", year_month, ".json"))
      jsonlite::write_json(item, item_file, pretty = TRUE, auto_unbox = TRUE)
      item_file
    }
  )

  # Append item links to collection and re-write
  item_links <- purrr::map2(
    item_files, dates,
    ~ list(
      rel   = "item",
      href  = basename(.x),
      type  = "application/json",
      title = paste(toupper(source), "burned area", format(.y, "%Y-%m"))
    )
  )
  collection$links <- c(collection$links, item_links)
  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)

  if (verbose) message("Generated ", length(item_files), " STAC Item files for ", source, " burn dates")

  collection_file
}


#' @title Generate unified fire history STAC Collection
#' @description Creates a single STAC Collection combining MODIS MCD64A1 and VIIRS VNP64A1
#'   monthly burned area items plus a derived postfire-age item (most_recent_burn.parquet).
#'   Items carry a `source` property ("modis", "viirs", or "derived") so consumers can filter
#'   by sensor. Re-runs whenever any of its three inputs change.
#' @param modis_parquet_files Character vector of MODIS burn-date parquet paths (branched target)
#' @param viirs_parquet_files Character vector of VIIRS burn-date parquet paths (branched target)
#' @param most_recent_burn_file Single file path to most_recent_burn.parquet
#' @param modis_parquet_dir Fallback directory if modis_parquet_files is NULL
#' @param viirs_parquet_dir Fallback directory if viirs_parquet_files is NULL
#' @param stac_dir Output directory for fire_history STAC JSON files
#' @param gh_repo GitHub repository in format "owner/repo"
#' @param gh_release_tag_modis GitHub release tag hosting MODIS monthly parquets
#' @param gh_release_tag_viirs GitHub release tag hosting VIIRS monthly parquets
#' @param gh_release_tag_derived GitHub release tag hosting derived fire_history products
#' @param verbose Logical for progress messages
#' @return Character path to the fire_history collection.json
#' @keywords internal
generate_fire_history_stac <- function(
  modis_parquet_files    = NULL,
  viirs_parquet_files    = NULL,
  most_recent_burn_file  = NULL,
  modis_parquet_dir      = "data/target_outputs/burn_dates_modis",
  viirs_parquet_dir      = "data/target_outputs/burn_dates_viirs",
  stac_dir               = "data/stac/fire_history",
  gh_repo                = "AdamWilsonLab/emma_envdata",
  gh_release_tag_modis   = "dynamic_burn_dates_modis",
  gh_release_tag_viirs   = "dynamic_burn_dates_viirs",
  gh_release_tag_derived = "fire_history",
  verbose                = TRUE
) {
  dir.create(stac_dir, recursive = TRUE, showWarnings = FALSE)

  # Resolve parquet file lists from directories if not supplied directly
  if (is.null(modis_parquet_files) || length(modis_parquet_files) == 0) {
    modis_parquet_files <- list.files(modis_parquet_dir, pattern = "\\.parquet$", full.names = TRUE)
  }
  if (is.null(viirs_parquet_files) || length(viirs_parquet_files) == 0) {
    viirs_parquet_files <- list.files(viirs_parquet_dir, pattern = "\\.parquet$", full.names = TRUE)
  }

  # Extract YYYYMM dates from filenames; drop files that do not match the pattern
  parse_dates <- function(files) {
    ym    <- stringr::str_extract(basename(files), "\\d{6}")
    dates <- as.Date(paste0(ym, "01"), format = "%Y%m%d")
    list(files = files[!is.na(dates)], dates = dates[!is.na(dates)])
  }
  modis <- parse_dates(modis_parquet_files)
  viirs <- parse_dates(viirs_parquet_files)

  if (verbose) {
    message(
      "Generating fire_history STAC collection: ",
      length(modis$files), " MODIS + ",
      length(viirs$files), " VIIRS monthly items",
      if (!is.null(most_recent_burn_file) && nzchar(most_recent_burn_file))
        " + postfire_age item" else ""
    )
  }

  # ── Build STAC Collection ────────────────────────────────────────────────
  all_dates     <- c(modis$dates, viirs$dates)
  temporal_start <- if (length(all_dates) > 0) {
    paste0(format(min(all_dates), "%Y-%m-%d"), "T00:00:00Z")
  } else {
    "2000-11-01T00:00:00Z"
  }

  collection <- list(
    stac_version = "1.0.0",
    stac_extensions = list("https://stac-extensions.github.io/scientific/v1.0.0/schema.json"),
    type        = "Collection",
    id          = "fire_history",
    title       = "Fire History — MODIS MCD64A1 + VIIRS VNP64A1 Burned Area",
    description = paste(
      "Monthly burned area detections and derived postfire age for ecosystem fire-history analysis.",
      "Combines MODIS MCD64A1 (Terra, 500 m, 2000-present) and VIIRS VNP64A1 (Suomi NPP, 375 m",
      "resampled to 500 m, 2012-present). Also includes most_recent_burn.parquet: time-since-fire",
      "(days) at each MODIS VI observation date per pixel. Only confirmed burned pixels (QA = 0)",
      "are retained. Pixel IDs (pid) align with the EMMA domain grid."
    ),
    license = "proprietary",
    extent = list(
      spatial  = list(bbox = list(list(-180, -90, 180, 90))),
      temporal = list(interval = list(list(temporal_start, NULL)))
    ),
    links = list(
      list(rel = "root",    href = "catalog.json",          type = "application/json"),
      list(rel = "self",    href = "fire_history_collection.json", type = "application/json"),
      list(rel = "license", href = "https://creativecommons.org/licenses/by/4.0/",
           type = "text/html"),
      list(rel = "about",   href = "https://lpdaac.usgs.gov/products/mcd64a1v061/",
           title = "MCD64A1 v061 Product Page", type = "text/html"),
      list(rel = "about",   href = "https://lpdaac.usgs.gov/products/vnp64a1v002/",
           title = "VNP64A1 v002 Product Page", type = "text/html")
    ),
    providers = list(
      list(name = "NASA LP DAAC",  roles = c("producer", "licensor"),
           url = "https://lpdaac.usgs.gov/"),
      list(name = "NASA AppEEARS", roles = list("processor"),
           url = "https://appeears.org/"),
      list(name = "EMMA Lab",      roles = list("processor"),
           url = "https://adamwilsonlab.github.io/")
    ),
    summaries = list(
      platforms   = list("Terra", "Suomi NPP"),
      instruments = list("MODIS", "VIIRS"),
      sources     = list("modis", "viirs", "derived"),
      gsd         = list(500),
      sci_doi     = list(
        "10.5067/MODIS/MCD64A1.061",
        "10.5067/VIIRS/VNP64A1.002"
      )
    )
  )

  collection_file <- file.path(stac_dir, "fire_history_collection.json")
  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)

  # ── Helper: build and write one monthly burn-date item ───────────────────
  # Returns list(file, date, source) for link accumulation below
  make_monthly_item <- function(pq_file, pq_date, source, gh_release_tag) {
    sensor_meta <- list(
      modis = list(platforms = list("Terra"),     instruments = list("MODIS"), gsd = 500),
      viirs = list(platforms = list("Suomi NPP"), instruments = list("VIIRS"), gsd = 375)
    )
    smeta      <- sensor_meta[[source]]
    year_month <- format(pq_date, "%Y%m")
    month_end  <- as.Date(paste0(format(pq_date + 31, "%Y-%m"), "-01")) - 1
    item_id    <- paste0("fire_history_", source, "_", year_month)
    gh_url     <- paste0(
      "https://github.com/", gh_repo,
      "/releases/download/", gh_release_tag, "/",
      basename(pq_file)
    )

    item <- list(
      stac_version = "1.0.0",
      stac_extensions = list(
        "https://stac-extensions.github.io/scientific/v1.0.0/schema.json"
      ),
      type        = "Feature",
      id          = item_id,
      description = paste(toupper(source), "burned area detections for",
                          format(pq_date, "%B %Y")),
      geometry = list(
        type = "Polygon",
        coordinates = list(list(
          c(-180, -90), c(180, -90), c(180, 90), c(-180, 90), c(-180, -90)
        ))
      ),
      bbox = c(-180, -90, 180, 90),
      properties = list(
        datetime       = paste0(format(pq_date, "%Y-%m-%d"), "T00:00:00Z"),
        start_datetime = paste0(format(pq_date, "%Y-%m-01"), "T00:00:00Z"),
        end_datetime   = paste0(format(month_end, "%Y-%m-%d"), "T23:59:59Z"),
        platforms      = smeta$platforms,
        instruments    = smeta$instruments,
        gsd            = smeta$gsd,
        source         = source,
        dataset        = "fire_history"
      ),
      links = list(
        list(rel = "collection", href = "fire_history_collection.json", type = "application/json"),
        list(rel = "root",       href = "catalog.json",              type = "application/json"),
        list(rel = "parent",     href = "fire_history_collection.json", type = "application/json")
      ),
      assets = list(
        data = list(
          href        = gh_url,
          title       = paste0(toupper(source), " burned area parquet — ", year_month),
          description = "Burned pixels (pid, date, burn_doy, qa) in gzip-compressed Parquet",
          type        = "application/octet-stream",
          roles       = list("data")
        )
      )
    )

    item_file <- file.path(stac_dir, paste0(item_id, ".json"))
    jsonlite::write_json(item, item_file, pretty = TRUE, auto_unbox = TRUE)
    list(file = item_file, date = pq_date, source = source)
  }

  # ── Build all monthly items for both sensors ─────────────────────────────
  modis_items <- purrr::pmap(
    list(pq_file = modis$files, pq_date = modis$dates),
    ~ make_monthly_item(..1, ..2, source = "modis",
                        gh_release_tag = gh_release_tag_modis)
  )
  viirs_items <- purrr::pmap(
    list(pq_file = viirs$files, pq_date = viirs$dates),
    ~ make_monthly_item(..1, ..2, source = "viirs",
                        gh_release_tag = gh_release_tag_viirs)
  )
  all_items <- c(modis_items, viirs_items)

  # ── Derived postfire-age item (most_recent_burn.parquet) ─────────────────
  # Included only when the most_recent_burn target has produced its file.
  # Re-running this function after most_recent_burn updates refreshes this item.
  if (!is.null(most_recent_burn_file) && nzchar(most_recent_burn_file)) {
    mrb_url <- paste0(
      "https://github.com/", gh_repo,
      "/releases/download/", gh_release_tag_derived, "/",
      basename(most_recent_burn_file)
    )
    mrb_item <- list(
      stac_version = "1.0.0",
      type         = "Feature",
      id           = "fire_history_postfire_age",
      description  = paste(
        "Time-since-fire (days) at each MODIS VI observation date per pixel.",
        "Derived by merging MODIS MCD64A1 + VIIRS VNP64A1 burn records.",
        "Columns: pid, date, last_burn_date, fire_age_days."
      ),
      geometry = list(
        type = "Polygon",
        coordinates = list(list(
          c(-180, -90), c(180, -90), c(180, 90), c(-180, 90), c(-180, -90)
        ))
      ),
      bbox = c(-180, -90, 180, 90),
      properties = list(
        datetime       = NULL,
        start_datetime = "2000-11-01T00:00:00Z",
        end_datetime   = paste0(format(Sys.Date(), "%Y-%m-%d"), "T23:59:59Z"),
        source         = "derived",
        dataset        = "fire_history"
      ),
      links = list(
        list(rel = "collection", href = "fire_history_collection.json", type = "application/json"),
        list(rel = "root",       href = "catalog.json",              type = "application/json"),
        list(rel = "parent",     href = "fire_history_collection.json", type = "application/json")
      ),
      assets = list(
        data = list(
          href        = mrb_url,
          title       = "Postfire age parquet (most_recent_burn)",
          description = paste(
            "Per-pixel, per-VI-date: last_burn_date and fire_age_days.",
            "Gzip-compressed Parquet."
          ),
          type  = "application/octet-stream",
          roles = list("data")
        )
      )
    )
    mrb_file <- file.path(stac_dir, "fire_history_postfire_age.json")
    jsonlite::write_json(mrb_item, mrb_file, pretty = TRUE, auto_unbox = TRUE)
    all_items <- c(all_items,
                   list(list(file = mrb_file, date = Sys.Date(), source = "derived")))
  }

  # ── Append item links to collection and re-write ──────────────────────────
  item_links <- purrr::map(all_items, function(it) {
    label <- if (it$source == "derived") {
      "postfire age (derived)"
    } else {
      paste(toupper(it$source), "burned area", format(it$date, "%Y-%m"))
    }
    list(
      rel   = "item",
      href  = basename(it$file),
      type  = "application/json",
      title = label
    )
  })
  collection$links <- c(collection$links, item_links)
  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)

  if (verbose) {
    message(
      "Generated fire_history STAC: ",
      length(modis_items), " MODIS + ",
      length(viirs_items), " VIIRS items",
      if (!is.null(most_recent_burn_file) && nzchar(most_recent_burn_file))
        " + postfire_age" else ""
    )
  }

  collection_file
}

