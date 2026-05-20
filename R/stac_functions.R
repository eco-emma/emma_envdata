#' @title Generate STAC Collection for VI dataset (MODIS + VIIRS NetCDF rasters)
#' @description Creates a STAC Collection and individual Item files for monthly VI
#'   NetCDF rasters from MODIS (Terra + Aqua) and, optionally, VIIRS (S-NPP + NOAA-20).
#'   Each STAC item covers one month and one sensor family; assets point to GitHub
#'   release URLs.
#' @author EMMA Team
#' @param nc_files Character vector of NC paths from \code{vi_modis_grid}.
#'   Named \code{vi_modis_YYYYMM_terra.nc} / \code{vi_modis_YYYYMM_aqua.nc}.
#' @param viirs_nc_files Optional character vector of NC paths from \code{vi_viirs_grid}.
#'   Named \code{vi_viirs_YYYYMM_snpp.nc} / \code{vi_viirs_YYYYMM_noaa20.nc}.
#'   Skip-marker files are filtered automatically.
#' @param stac_dir Output directory for this collection's STAC JSON files.
#' @param parent_catalog_path Path to parent catalog directory (for link context).
#' @param gh_repo GitHub repository in format "owner/repo".
#' @param gh_release_tag GitHub release tag for MODIS NC raster files.
#' @param gh_release_tag_viirs GitHub release tag for VIIRS NC raster files.
#' @param verbose Logical for progress messages.
#' @return Character path to the collection JSON file.
#' @keywords internal
generate_modis_vi_stac <- function(
  nc_files,
  viirs_nc_files       = NULL,
  stac_dir             = "data/stac/modis_vi",
  parent_catalog_path  = "data/stac",
  gh_repo              = "AdamWilsonLab/emma_envdata",
  gh_release_tag       = "vi_modis_dynamic_raster",
  gh_release_tag_viirs = "vi_viirs_dynamic_raster",
  verbose              = TRUE
) {

  dir.create(stac_dir, recursive = TRUE, showWarnings = FALSE)

  # Keep only valid NC files; discard .skip markers
  nc_files <- nc_files[grepl("\\.nc$", nc_files) & !grepl("\\.skip$", nc_files)]

  if (length(nc_files) == 0) {
    stop("No MODIS VI NC files found. Check that vi_modis_grid targets completed successfully.")
  }

  # Filter VIIRS files (may be NULL or empty)
  has_viirs <- !is.null(viirs_nc_files) && length(viirs_nc_files) > 0
  if (has_viirs) {
    viirs_nc_files <- viirs_nc_files[grepl("\\.nc$", viirs_nc_files) &
                                     !grepl("\\.skip$", viirs_nc_files)]
    has_viirs <- length(viirs_nc_files) > 0
  }

  bn       <- basename(nc_files)
  yyyymm   <- regmatches(bn, regexpr("\\d{6}", bn))
  sensor   <- ifelse(grepl("_terra_", bn), "terra", "aqua")
  months   <- sort(unique(yyyymm))
  dates    <- as.Date(paste0(months, "01"), "%Y%m%d")

  # Compute overall temporal extent including VIIRS if present
  all_dates <- dates
  if (has_viirs) {
    vbn      <- basename(viirs_nc_files)
    vyyyymm  <- regmatches(vbn, regexpr("\\d{6}", vbn))
    vdates   <- as.Date(paste0(sort(unique(vyyyymm)), "01"), "%Y%m%d")
    all_dates <- sort(unique(c(all_dates, vdates)))
  }

  collection_title <- if (has_viirs) {
    "MODIS + VIIRS VI Rasters (Terra, Aqua, S-NPP, NOAA-20 \u2014 16-day composites, 500m)"
  } else {
    "MODIS VI Rasters \u2014 Terra + Aqua (16-day composites, 500m)"
  }

  collection_desc <- if (has_viirs) {
    paste(
      "Domain-aligned 500m NetCDF rasters of Enhanced Vegetation Index (EVI) from MODIS and VIIRS.",
      "MODIS provides Terra (MOD13A1) and Aqua (MYD13A1) sensors from 2000-02 onward.",
      "VIIRS provides S-NPP (VNP13A1) from 2012-01 and NOAA-20 (VJ113A1) from 2018-01 onward.",
      "Each NC contains EVI (x100, QA-masked, integer) and composite day-of-year (doy) variables.",
      "Items are grouped by sensor family: MODIS items have terra/aqua assets; VIIRS items have snpp/noaa20 assets."
    )
  } else {
    paste(
      "Domain-aligned 500m NetCDF rasters of MODIS Enhanced Vegetation Index (EVI).",
      "Terra (MOD13A1) and Aqua (MYD13A1) sensors are provided as separate files per month.",
      "Each NC contains EVI (x100, QA-masked, integer) and composite day-of-year (doy) variables.",
      "The time dimension carries the 16-day composite period present in the monthly download."
    )
  }

  if (verbose) message(
    "Generating STAC Collection for VI (", length(months), " MODIS months",
    if (has_viirs) paste0(", ", length(sort(unique(vyyyymm))), " VIIRS months") else "",
    " | ", length(nc_files) + if (has_viirs) length(viirs_nc_files) else 0L, " NC files)"
  )

  collection <- list(
    stac_version = "1.0.0",
    stac_extensions = list(
      "https://stac-extensions.github.io/scientific/v1.0.0/schema.json"
    ),
    type = "Collection",
    id = "modis_vi",
    title = collection_title,
    description = collection_desc,
    license = "CC-BY-4.0",
    keywords = c("MODIS", "VIIRS", "EVI", "vegetation", "Terra", "Aqua",
                 "S-NPP", "NOAA-20", "500m", "16-day", "NetCDF"),
    extent = list(
      spatial = list(
        bbox = list(c(-180, -90, 180, 90))
      ),
      temporal = list(
        interval = list(c(
          paste0(format(min(all_dates), "%Y-%m-%d"), "T00:00:00Z"),
          paste0(format(max(all_dates), "%Y-%m-%d"), "T23:59:59Z")
        ))
      )
    ),
    links = list(
      list(rel = "root",    href = "catalog.json",           type = "application/json"),
      list(rel = "parent",  href = "catalog.json",           type = "application/json"),
      list(rel = "license", href = "https://creativecommons.org/licenses/by/4.0/", type = "text/html"),
      list(
        rel   = "about",
        href  = "https://lpdaac.usgs.gov/products/mod13a1v061/",
        title = "MOD13A1.061 Product Information",
        type  = "text/html"
      )
    ),
    providers = list(
      list(name = "USGS LP DAAC",   description = "Data source for MOD13A1 and MYD13A1",    roles = c("producer", "licensor"), url = "https://lpdaac.usgs.gov/"),
      list(name = "NASA AppEEARS",  description = "Data access and subsetting service",       roles = list("processor"),         url = "https://appeears.org/"),
      list(name = "EMMA Lab",       description = "Data processing and aggregation",          roles = list("processor"),         url = "https://adamwilsonlab.github.io/")
    ),
    summaries = list(
      sci_doi     = "10.5067/MODIS/MOD13A1.061|10.5067/MODIS/MYD13A1.061|10.5067/VIIRS/VNP13A1.002|10.5067/VIIRS/VJ113A1.002",
      platforms   = c("Terra", "Aqua", "Suomi NPP", "NOAA-20"),
      instruments = list("MODIS", "VIIRS"),
      gsd         = list(500),
      variables   = list(
        list(name = "EVI",  description = "EVI x100 (QA-masked, integer)", data_type = "int32"),
        list(name = "doy",  description = "Composite day of year per pixel", data_type = "int16")
      )
    )
  )

  collection_file <- file.path(stac_dir, "modis_vi_collection.json")
  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)

  if (verbose) message("Created STAC Collection: ", collection_file)

  # One STAC item per month; each item has up to two assets (terra + aqua)
  for (i in seq_along(months)) {
    ym        <- months[i]
    pq_date   <- dates[i]
    month_end <- as.Date(paste0(format(pq_date + 31, "%Y-%m"), "-01")) - 1

    # Collect NC files for this month
    month_ncs     <- nc_files[yyyymm == ym]
    month_sensors <- sensor[yyyymm == ym]

    assets <- list()
    for (j in seq_along(month_ncs)) {
      s       <- month_sensors[j]
      tag     <- if (s == "terra") "Terra (MOD13A1)" else "Aqua (MYD13A1)"
      gh_url  <- paste0("https://github.com/", gh_repo, "/releases/download/",
                        gh_release_tag, "/", basename(month_ncs[j]))
      assets[[s]] <- list(
        href        = gh_url,
        title       = paste0("MODIS VI — ", tag, " — ", ym),
        description = paste0(tag, " EVI (x100) + composite DOY, 500m domain-aligned grid"),
        type        = "application/x-netcdf",
        roles       = list("data")
      )
    }

    item <- list(
      stac_version = "1.0.0",
      stac_extensions = list(
        "https://stac-extensions.github.io/scientific/v1.0.0/schema.json"
      ),
      type        = "Feature",
      id          = paste0("modis_vi_", ym),
      description = paste("MODIS VI rasters (Terra + Aqua) for", format(pq_date, "%B %Y")),
      geometry = list(
        type = "Polygon",
        coordinates = list(list(
          c(-180, -90), c(180, -90), c(180, 90), c(-180, 90), c(-180, -90)
        ))
      ),
      bbox = c(-180, -90, 180, 90),
      properties = list(
        `datetime`     = paste0(format(pq_date, "%Y-%m-%d"), "T00:00:00Z"),
        start_datetime = paste0(format(pq_date, "%Y-%m-01"), "T00:00:00Z"),
        end_datetime   = paste0(format(month_end, "%Y-%m-%d"), "T23:59:59Z"),
        platforms      = c("Terra", "Aqua"),
        instruments    = list("MODIS"),
        gsd            = 500,
        dataset        = "modis_vi"
      ),
      links = list(
        list(rel = "collection", href = "modis_vi_collection.json", type = "application/json"),
        list(rel = "root",       href = "catalog.json",             type = "application/json"),
        list(rel = "parent",     href = "modis_vi_collection.json", type = "application/json")
      ),
      assets = assets
    )

    item_file <- file.path(stac_dir, paste0("modis_vi_", ym, ".json"))
    jsonlite::write_json(item, item_file, pretty = TRUE, auto_unbox = TRUE)

    collection$links[[length(collection$links) + 1]] <- list(
      rel   = "item",
      href  = paste0("modis_vi_", ym, ".json"),
      type  = "application/json",
      title = paste("MODIS VI", ym)
    )
  }

  # ── VIIRS items (one per month; snpp + noaa20 assets) ────────────────────
  if (has_viirs) {
    vsensor  <- ifelse(grepl("_snpp_", basename(viirs_nc_files)), "snpp", "noaa20")
    vmonths  <- sort(unique(vyyyymm))
    vdates_m <- as.Date(paste0(vmonths, "01"), "%Y%m%d")

    for (i in seq_along(vmonths)) {
      vym       <- vmonths[i]
      vpq_date  <- vdates_m[i]
      vmonth_end <- as.Date(paste0(format(vpq_date + 31, "%Y-%m"), "-01")) - 1

      vmonth_ncs     <- viirs_nc_files[vyyyymm == vym]
      vmonth_sensors <- vsensor[vyyyymm == vym]

      vassets <- list()
      for (j in seq_along(vmonth_ncs)) {
        s      <- vmonth_sensors[j]
        vtag   <- if (s == "snpp") "S-NPP (VNP13A1)" else "NOAA-20 (VJ113A1)"
        gh_url <- paste0("https://github.com/", gh_repo, "/releases/download/",
                         gh_release_tag_viirs, "/", basename(vmonth_ncs[j]))
        vassets[[s]] <- list(
          href        = gh_url,
          title       = paste0("VIIRS VI \u2014 ", vtag, " \u2014 ", vym),
          description = paste0(vtag, " EVI (x100) + composite DOY, 500m domain-aligned grid"),
          type        = "application/x-netcdf",
          roles       = list("data")
        )
      }

      vitem <- list(
        stac_version = "1.0.0",
        stac_extensions = list(
          "https://stac-extensions.github.io/scientific/v1.0.0/schema.json"
        ),
        type        = "Feature",
        id          = paste0("viirs_vi_", vym),
        description = paste("VIIRS VI rasters (S-NPP + NOAA-20) for", format(vpq_date, "%B %Y")),
        geometry = list(
          type = "Polygon",
          coordinates = list(list(
            c(-180, -90), c(180, -90), c(180, 90), c(-180, 90), c(-180, -90)
          ))
        ),
        bbox = c(-180, -90, 180, 90),
        properties = list(
          `datetime`     = paste0(format(vpq_date, "%Y-%m-%d"), "T00:00:00Z"),
          start_datetime = paste0(format(vpq_date, "%Y-%m-01"), "T00:00:00Z"),
          end_datetime   = paste0(format(vmonth_end, "%Y-%m-%d"), "T23:59:59Z"),
          platforms      = c("Suomi NPP", "NOAA-20"),
          instruments    = list("VIIRS"),
          gsd            = 500,
          dataset        = "viirs_vi"
        ),
        links = list(
          list(rel = "collection", href = "modis_vi_collection.json", type = "application/json"),
          list(rel = "root",       href = "catalog.json",             type = "application/json"),
          list(rel = "parent",     href = "modis_vi_collection.json", type = "application/json")
        ),
        assets = vassets
      )

      vitem_file <- file.path(stac_dir, paste0("viirs_vi_", vym, ".json"))
      jsonlite::write_json(vitem, vitem_file, pretty = TRUE, auto_unbox = TRUE)

      collection$links[[length(collection$links) + 1]] <- list(
        rel   = "item",
        href  = paste0("viirs_vi_", vym, ".json"),
        type  = "application/json",
        title = paste("VIIRS VI", vym)
      )
    }

    if (verbose) message("Generated ", length(vmonths), " VIIRS STAC items (S-NPP + NOAA-20 assets)")
  }

  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)

  if (verbose) message("Generated ", length(months), " MODIS STAC items (Terra + Aqua assets per month)")

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

      # Read collection title dynamically from the JSON file when available
      collection_title <- tryCatch({
        coll_data <- jsonlite::read_json(collection_file)
        if (!is.null(coll_data$title)) coll_data$title else dataset_name
      }, error = function(e) dataset_name)

      catalog$links[[length(catalog$links) + 1]] <- list(
        rel   = "child",
        href  = rel_path,
        type  = "application/json",
        title = collection_title
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


#' @title Generate unified burn STAC Collection (NetCDF rasters)
#' @description Creates a single STAC Collection combining MODIS MCD64A1 and VIIRS VNP64A1
#'   monthly burned area NetCDF items plus a derived most-recent-burn NC item.
#'   Items carry a \code{source} property ("modis", "viirs", or "derived") so consumers can filter
#'   by sensor.  VIIRS is preferred over MODIS in all downstream deduplication and
#'   fire-history products (higher spatial resolution: 375m vs 500m).
#'   Note temporal discontinuity: VIIRS data begin January 2012.
#' @param modis_nc_files Character vector of MODIS burn NC paths from \code{burn_modis_grid} target.
#'   Files named \code{burn_modis_YYYYMM.nc}; .skip markers are filtered automatically.
#' @param viirs_nc_files Character vector of VIIRS burn NC paths from \code{burn_viirs_grid} target.
#'   Files named \code{burn_viirs_YYYYMM.nc}; .skip markers are filtered automatically.
#' @param recentburn_file Single file path to \code{most_recent_burn.nc} (from \code{recentburn_grid} target).
#' @param stac_dir Output directory for burn STAC JSON files
#' @param gh_repo GitHub repository in format "owner/repo"
#' @param gh_release_tag_modis GitHub release tag hosting MODIS monthly NC rasters
#' @param gh_release_tag_viirs GitHub release tag hosting VIIRS monthly NC rasters
#' @param gh_release_tag_derived GitHub release tag hosting derived fire-history products
#' @param verbose Logical for progress messages
#' @return Character path to the burn collection.json
#' @keywords internal
generate_burn_stac <- function(
  modis_nc_files         = NULL,
  viirs_nc_files         = NULL,
  recentburn_file        = NULL,
  stac_dir               = "data/stac/burn",
  gh_repo                = "AdamWilsonLab/emma_envdata",
  gh_release_tag_modis   = "burn_dates_modis_raster",
  gh_release_tag_viirs   = "burn_dates_viirs_raster",
  gh_release_tag_derived = "firehistory_dynamic",
  verbose                = TRUE
) {
  dir.create(stac_dir, recursive = TRUE, showWarnings = FALSE)

  # Filter to valid NC files; drop .skip markers
  filter_nc <- function(files) {
    if (is.null(files) || length(files) == 0) return(character(0))
    files[grepl("\\.nc$", files) & !grepl("\\.skip$", files)]
  }
  modis_nc_files <- filter_nc(modis_nc_files)
  viirs_nc_files <- filter_nc(viirs_nc_files)

  # Extract YYYYMM dates from NC filenames
  parse_nc_dates <- function(files) {
    if (length(files) == 0) return(list(files = character(0), dates = as.Date(character(0))))
    ym    <- regmatches(basename(files), regexpr("\\d{6}", basename(files)))
    dates <- as.Date(paste0(ym, "01"), format = "%Y%m%d")
    list(files = files[!is.na(dates)], dates = dates[!is.na(dates)])
  }
  modis <- parse_nc_dates(modis_nc_files)
  viirs <- parse_nc_dates(viirs_nc_files)

  if (verbose) {
    message(
      "Generating burn STAC collection: ",
      length(modis$files), " MODIS + ",
      length(viirs$files), " VIIRS monthly items",
      if (!is.null(recentburn_file) && nzchar(recentburn_file) && grepl("\\.nc$", recentburn_file))
        " + recentburn item" else ""
    )
  }

  # ── Build STAC Collection ────────────────────────────────────────────────
  all_dates      <- c(modis$dates, viirs$dates)
  temporal_start <- if (length(all_dates) > 0) {
    paste0(format(min(all_dates), "%Y-%m-%d"), "T00:00:00Z")
  } else {
    "2000-11-01T00:00:00Z"
  }

  collection <- list(
    stac_version = "1.0.0",
    stac_extensions = list("https://stac-extensions.github.io/scientific/v1.0.0/schema.json"),
    type        = "Collection",
    id          = "burn",
    title       = "Burned Area — MODIS MCD64A1 + VIIRS VNP64A1 (NetCDF rasters)",
    description = paste(
      "Monthly burned area NetCDF rasters for ecosystem fire-history analysis.",
      "MODIS MCD64A1 (Terra, 500m, 2000-present) and VIIRS VNP64A1 (Suomi NPP, 375m",
      "resampled to 500m, 2012-present) are provided as separate domain-aligned files.",
      "Each NC contains a burn_doy variable (day-of-year of burn detection, QA=0 only).",
      "VIIRS is preferred over MODIS in all downstream deduplication and fire-history",
      "products because of its higher spatial resolution (375m vs 500m).",
      "Note temporal discontinuity: VIIRS data begin January 2012.",
      "Also includes most_recent_burn.nc: fire_age_days and last_burn_date snapshot per pixel."
    ),
    license = "proprietary",
    extent = list(
      spatial  = list(bbox = list(list(-180, -90, 180, 90))),
      temporal = list(interval = list(list(temporal_start, NULL)))
    ),
    links = list(
      list(rel = "root",    href = "catalog.json",         type = "application/json"),
      list(rel = "self",    href = "burn_collection.json", type = "application/json"),
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

  collection_file <- file.path(stac_dir, "burn_collection.json")
  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)

  # ── Helper: build and write one monthly burn NC item ─────────────────────
  make_monthly_item <- function(nc_file, nc_date, source, gh_release_tag) {
    sensor_meta <- list(
      modis = list(platforms = list("Terra"),     instruments = list("MODIS"), gsd = 500),
      viirs = list(platforms = list("Suomi NPP"), instruments = list("VIIRS"), gsd = 375)
    )
    smeta      <- sensor_meta[[source]]
    year_month <- format(nc_date, "%Y%m")
    month_end  <- as.Date(paste0(format(nc_date + 31, "%Y-%m"), "-01")) - 1
    item_id    <- paste0("burn_", source, "_", year_month)
    gh_url     <- paste0(
      "https://github.com/", gh_repo,
      "/releases/download/", gh_release_tag, "/",
      basename(nc_file)
    )

    item <- list(
      stac_version = "1.0.0",
      stac_extensions = list(
        "https://stac-extensions.github.io/scientific/v1.0.0/schema.json"
      ),
      type        = "Feature",
      id          = item_id,
      description = paste(toupper(source), "burned area raster for",
                          format(nc_date, "%B %Y")),
      geometry = list(
        type = "Polygon",
        coordinates = list(list(
          c(-180, -90), c(180, -90), c(180, 90), c(-180, 90), c(-180, -90)
        ))
      ),
      bbox = c(-180, -90, 180, 90),
      properties = list(
        datetime       = paste0(format(nc_date, "%Y-%m-%d"), "T00:00:00Z"),
        start_datetime = paste0(format(nc_date, "%Y-%m-01"), "T00:00:00Z"),
        end_datetime   = paste0(format(month_end, "%Y-%m-%d"), "T23:59:59Z"),
        platforms      = smeta$platforms,
        instruments    = smeta$instruments,
        gsd            = smeta$gsd,
        source         = source,
        dataset        = "burn"
      ),
      links = list(
        list(rel = "collection", href = "burn_collection.json", type = "application/json"),
        list(rel = "root",       href = "catalog.json",         type = "application/json"),
        list(rel = "parent",     href = "burn_collection.json", type = "application/json")
      ),
      assets = list(
        burn_doy = list(
          href        = gh_url,
          title       = paste0(toupper(source), " burn day-of-year — ", year_month),
          description = paste0("burn_doy variable: day of year of burn detection (QA=0), ",
                               smeta$platforms[[1]], " 500m domain-aligned grid"),
          type        = "application/x-netcdf",
          roles       = list("data")
        )
      )
    )

    item_file <- file.path(stac_dir, paste0(item_id, ".json"))
    jsonlite::write_json(item, item_file, pretty = TRUE, auto_unbox = TRUE)
    list(file = item_file, date = nc_date, source = source)
  }

  # ── Build all monthly items for both sensors ─────────────────────────────
  modis_items <- purrr::pmap(
    list(nc_file = modis$files, nc_date = modis$dates),
    ~ make_monthly_item(..1, ..2, source = "modis",
                        gh_release_tag = gh_release_tag_modis)
  )
  viirs_items <- purrr::pmap(
    list(nc_file = viirs$files, nc_date = viirs$dates),
    ~ make_monthly_item(..1, ..2, source = "viirs",
                        gh_release_tag = gh_release_tag_viirs)
  )
  all_items <- c(modis_items, viirs_items)

  # ── Derived most-recent-burn NC item ──────────────────────────────────────
  if (!is.null(recentburn_file) && nzchar(recentburn_file) && grepl("\\.nc$", recentburn_file)) {
    mrb_url <- paste0(
      "https://github.com/", gh_repo,
      "/releases/download/", gh_release_tag_derived, "/",
      basename(recentburn_file)
    )
    mrb_item <- list(
      stac_version = "1.0.0",
      type         = "Feature",
      id           = "burn_recentburn",
      description  = paste(
        "Fire age and last burn date snapshot (most recent state per pixel).",
        "Contains fire_age_days (days since last fire) and last_burn_date (days since 1970-01-01)",
        "as of the latest available observation date."
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
        dataset        = "burn"
      ),
      links = list(
        list(rel = "collection", href = "burn_collection.json", type = "application/json"),
        list(rel = "root",       href = "catalog.json",         type = "application/json"),
        list(rel = "parent",     href = "burn_collection.json", type = "application/json")
      ),
      assets = list(
        recentburn = list(
          href        = mrb_url,
          title       = "Most recent burn snapshot (NC)",
          description = paste(
            "fire_age_days and last_burn_date per pixel as of the latest available date.",
            "Domain-aligned 500m NetCDF."
          ),
          type  = "application/x-netcdf",
          roles = list("data")
        )
      )
    )
    mrb_file <- file.path(stac_dir, "burn_recentburn.json")
    jsonlite::write_json(mrb_item, mrb_file, pretty = TRUE, auto_unbox = TRUE)
    all_items <- c(all_items,
                   list(list(file = mrb_file, date = Sys.Date(), source = "derived")))
  }

  # ── Append item links to collection and re-write ──────────────────────────
  item_links <- purrr::map(all_items, function(it) {
    label <- if (it$source == "derived") {
      "most recent burn snapshot"
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
      "Generated burn STAC: ",
      length(modis_items), " MODIS + ",
      length(viirs_items), " VIIRS items",
      if (!is.null(recentburn_file) && nzchar(recentburn_file) && grepl("\\.nc$", recentburn_file))
        " + recentburn" else ""
    )
  }

  collection_file
}


# ============================================================================
# STAC for static environmental layers
# ============================================================================

#' @title Generate STAC Collection for static environmental layers
#'
#' @description Creates a STAC Collection and individual Item JSON files for the
#'   static (time-invariant) environmental layers used across the EMMA pipeline:
#'   domain grid, vegetation map, NASADEM elevation, CHELSA bioclimatic variables
#'   (BIO1-BIO19), Wilson/EarthEnv cloud frequency, SoilGrids v2 soil properties,
#'   and topographic diversity metrics.  All assets point to a single GitHub
#'   release tag (\code{"static_data"}).
#'
#' @param domain_nc       Path to \code{domain.nc}.
#' @param domain_parquet  Path to \code{domain.parquet}.
#' @param vegmap_nc       Path to \code{vegmap.nc}.
#' @param elevation_nc    Path returned by the \code{elevation} target (NASADEM NC).
#' @param climate_nc_files Character vector of paths returned by \code{climate_chelsa}
#'   (CHELSA BIO variable NCs, typically 19 files).
#' @param clouds_nc       Path returned by the \code{clouds_wilson} target.
#' @param soil_nc         Path returned by the \code{soil_soilgrids} target.
#' @param topo_nc         Path returned by the \code{topographic_diversity} target.
#' @param stac_dir        Output directory for STAC JSON files.
#' @param gh_repo         GitHub repo in "owner/repo" format.
#' @param gh_release_tag  GitHub release tag hosting the static NC files.
#' @param verbose         Logical. Print progress messages?
#'
#' @return Character path to \code{static_collection.json}.
#' @keywords internal
generate_static_layers_stac <- function(
    domain_nc        = "data/target_outputs/domain.nc",
    domain_parquet   = "data/target_outputs/domain.parquet",
    vegmap_nc        = "data/target_outputs/vegmap.nc",
    elevation_nc,
    climate_nc_files,
    clouds_nc,
    soil_nc,
    topo_nc,
    stac_dir         = "data/stac/static",
    gh_repo          = "AdamWilsonLab/emma_envdata",
    gh_release_tag   = "static_data",
    verbose          = TRUE) {

  dir.create(stac_dir, recursive = TRUE, showWarnings = FALSE)

  # Build a GitHub release download URL from a local file path
  gh_url <- function(f) {
    paste0("https://github.com/", gh_repo, "/releases/download/",
           gh_release_tag, "/", basename(f))
  }

  # Timeless datetime convention for static layers
  static_props <- list(
    datetime       = NULL,
    start_datetime = "1900-01-01T00:00:00Z",
    end_datetime   = paste0(format(Sys.Date(), "%Y-%m-%d"), "T23:59:59Z")
  )
  static_geom <- list(
    type = "Polygon",
    coordinates = list(list(
      c(-180, -90), c(180, -90), c(180, 90), c(-180, 90), c(-180, -90)
    ))
  )
  common_links <- function() list(
    list(rel = "collection", href = "static_collection.json", type = "application/json"),
    list(rel = "root",       href = "catalog.json",           type = "application/json"),
    list(rel = "parent",     href = "static_collection.json", type = "application/json")
  )

  # ── Collection ───────────────────────────────────────────────────────────
  collection <- list(
    stac_version = "1.0.0",
    stac_extensions = list(
      "https://stac-extensions.github.io/scientific/v1.0.0/schema.json"
    ),
    type    = "Collection",
    id      = "static",
    title   = "Static Environmental Layers (domain, vegetation, elevation, climate, clouds, soil, topography)",
    description = paste(
      "Time-invariant environmental layers for the EMMA study domain (Eastern Mediterranean & Maghreb).",
      "Includes: domain grid (pixel IDs + biome mask), vegetation map, NASADEM elevation (30m -> 500m),",
      "CHELSA BIO1-BIO19 bioclimatic variables (1981-2010), MODCF mean-annual cloud frequency",
      "(Wilson/EarthEnv), SoilGrids v2 soil properties (SOC, clay, sand, pH, BD; 0-30 cm),",
      "and topographic diversity metrics (slope, aspect, TRI, TPI).",
      "All layers are domain-aligned to the 500m EMMA grid."
    ),
    license  = "CC-BY-4.0",
    keywords = c("static", "domain", "elevation", "climate", "CHELSA", "soil",
                 "topography", "vegetation", "cloud", "NASADEM", "SoilGrids"),
    extent = list(
      spatial  = list(bbox = list(c(-180, -90, 180, 90))),
      temporal = list(interval = list(list("1900-01-01T00:00:00Z", NULL)))
    ),
    links = list(
      list(rel = "root",    href = "catalog.json",           type = "application/json"),
      list(rel = "parent",  href = "catalog.json",           type = "application/json"),
      list(rel = "license", href = "https://creativecommons.org/licenses/by/4.0/",
           type = "text/html")
    ),
    providers = list(
      list(name = "NASA LP DAAC", roles = c("producer", "licensor"), url = "https://lpdaac.usgs.gov/"),
      list(name = "CHELSA",       roles = c("producer", "licensor"), url = "https://chelsa-climate.org/"),
      list(name = "ISRIC",        roles = c("producer", "licensor"), url = "https://www.isric.org/"),
      list(name = "EarthEnv",     roles = c("producer", "licensor"), url = "https://www.earthenv.org/"),
      list(name = "EMMA Lab",     roles = list("processor"),         url = "https://adamwilsonlab.github.io/")
    )
  )

  collection_file <- file.path(stac_dir, "static_collection.json")
  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)

  items_written <- list()

  # Helper: write one item JSON and register it for the collection item-links
  write_item <- function(item, item_id) {
    item_file <- file.path(stac_dir, paste0(item_id, ".json"))
    jsonlite::write_json(item, item_file, pretty = TRUE, auto_unbox = TRUE)
    items_written[[length(items_written) + 1]] <<- list(file = item_file, id = item_id)
  }

  # ── 1. Domain grid ────────────────────────────────────────────────────────
  write_item(list(
    stac_version = "1.0.0", type = "Feature",
    id          = "static_domain",
    description = "EMMA domain grid: pixel IDs (pid) and biome/boundary mask at 500m resolution.",
    geometry    = static_geom, bbox = c(-180, -90, 180, 90),
    properties  = c(static_props, list(dataset = "static", layer = "domain")),
    links       = common_links(),
    assets = list(
      domain_nc = list(
        href = gh_url(domain_nc), title = "Domain grid (NC)",
        description = "Domain NetCDF: pid layer (integer pixel IDs) at 500m resolution.",
        type = "application/x-netcdf", roles = list("data")
      ),
      domain_parquet = list(
        href = gh_url(domain_parquet), title = "Domain grid (Parquet)",
        description = "Domain pixel table (pid, lon, lat, biome) in gzip-compressed Parquet.",
        type = "application/x-parquet", roles = list("data")
      )
    )
  ), "static_domain")

  # ── 2. Vegetation map ─────────────────────────────────────────────────────
  write_item(list(
    stac_version = "1.0.0", type = "Feature",
    id          = "static_vegmap",
    description = "Vegetation map classification rasterized to the 500m EMMA domain grid.",
    geometry    = static_geom, bbox = c(-180, -90, 180, 90),
    properties  = c(static_props, list(dataset = "static", layer = "vegmap")),
    links       = common_links(),
    assets = list(
      vegmap_nc = list(
        href = gh_url(vegmap_nc), title = "Vegetation map (NC)",
        description = "Vegetation class per pixel (integer codes), 500m domain-aligned grid.",
        type = "application/x-netcdf", roles = list("data")
      )
    )
  ), "static_vegmap")

  # ── 3. Elevation — NASADEM ────────────────────────────────────────────────
  write_item(list(
    stac_version = "1.0.0", type = "Feature",
    id          = "static_elevation",
    description = "NASADEM 30m digital elevation model resampled to the 500m EMMA domain grid.",
    geometry    = static_geom, bbox = c(-180, -90, 180, 90),
    properties  = c(static_props, list(
      dataset    = "static", layer = "elevation",
      platform   = "SRTM", instrument = "radar", gsd = 500,
      sci_doi    = "10.5067/MEaSUREs/NASADEM/NASADEM_HGT.001"
    )),
    links = c(common_links(), list(
      list(rel = "about", href = "https://lpdaac.usgs.gov/products/nasadem_hgtv001/",
           type = "text/html", title = "NASADEM_HGT v001 Product Page")
    )),
    assets = list(
      elevation_nc = list(
        href = gh_url(elevation_nc), title = "Elevation NC (NASADEM)",
        description = "Elevation in metres, 500m domain-aligned grid.",
        type = "application/x-netcdf", roles = list("data")
      )
    )
  ), "static_elevation")

  # ── 4. CHELSA bioclimatic variables (BIO1-BIO19) ─────────────────────────
  # One asset per BIO variable; key extracted from filename (e.g. "bio1")
  climate_assets <- list()
  for (nc in climate_nc_files) {
    m       <- regexpr("bio\\d+", basename(nc), ignore.case = TRUE)
    bio_key <- if (m > 0L) tolower(regmatches(basename(nc), m)) else tools::file_path_sans_ext(basename(nc))
    climate_assets[[bio_key]] <- list(
      href        = gh_url(nc),
      title       = paste0("CHELSA ", toupper(bio_key), " (1981-2010)"),
      description = paste0("CHELSA bioclimatic variable ", toupper(bio_key),
                           " (1981-2010 mean), 500m domain-aligned grid."),
      type        = "application/x-netcdf",
      roles       = list("data")
    )
  }
  write_item(list(
    stac_version = "1.0.0", type = "Feature",
    id          = "static_climate",
    description = paste(
      "CHELSA v2.1 bioclimatic variables BIO1-BIO19 (1981-2010 climatological mean)",
      "downscaled to the 500m EMMA domain grid."
    ),
    geometry   = static_geom, bbox = c(-180, -90, 180, 90),
    properties = c(static_props, list(
      dataset           = "static", layer = "climate",
      temporal_coverage = "1981-2010",
      sci_doi           = "10.1038/sdata.2017.122"
    )),
    links = c(common_links(), list(
      list(rel = "about", href = "https://chelsa-climate.org/",
           type = "text/html", title = "CHELSA Climate Website")
    )),
    assets = climate_assets
  ), "static_climate")

  # ── 5. Cloud frequency — Wilson / EarthEnv MODCF ─────────────────────────
  write_item(list(
    stac_version = "1.0.0", type = "Feature",
    id          = "static_clouds",
    description = paste(
      "MODCF mean annual cloud frequency and intra-annual seasonality",
      "(Wilson et al. 2016 / EarthEnv), resampled to the 500m domain grid."
    ),
    geometry   = static_geom, bbox = c(-180, -90, 180, 90),
    properties = c(static_props, list(
      dataset = "static", layer = "clouds",
      sci_doi = "10.1371/journal.pone.0172299"
    )),
    links = c(common_links(), list(
      list(rel = "about", href = "https://www.earthenv.org/cloud",
           type = "text/html", title = "EarthEnv Cloud Data")
    )),
    assets = list(
      clouds_nc = list(
        href = gh_url(clouds_nc), title = "Cloud frequency NC (MODCF / Wilson)",
        description = "Mean annual cloud fraction + seasonality index, 500m domain-aligned grid.",
        type = "application/x-netcdf", roles = list("data")
      )
    )
  ), "static_clouds")

  # ── 6. Soil properties — SoilGrids v2 ────────────────────────────────────
  write_item(list(
    stac_version = "1.0.0", type = "Feature",
    id          = "static_soil",
    description = paste(
      "SoilGrids v2 (ISRIC) soil properties averaged over 0-30 cm depth:",
      "SOC, clay, sand, pH, and bulk density. Resampled to the 500m domain grid."
    ),
    geometry   = static_geom, bbox = c(-180, -90, 180, 90),
    properties = c(static_props, list(
      dataset = "static", layer = "soil",
      sci_doi = "10.1371/journal.pone.0169748"
    )),
    links = c(common_links(), list(
      list(rel = "about", href = "https://www.isric.org/explore/soilgrids",
           type = "text/html", title = "SoilGrids v2 Product Page")
    )),
    assets = list(
      soil_nc = list(
        href = gh_url(soil_nc), title = "Soil properties NC (SoilGrids v2)",
        description = "SOC (g/kg), clay (%), sand (%), pH, bulk density (kg/dm3); 0-30 cm mean; 500m grid.",
        type = "application/x-netcdf", roles = list("data")
      )
    )
  ), "static_soil")

  # ── 7. Topographic diversity ──────────────────────────────────────────────
  write_item(list(
    stac_version = "1.0.0", type = "Feature",
    id          = "static_topography",
    description = paste(
      "Topographic diversity metrics derived from NASADEM elevation at 500m:",
      "slope, aspect, terrain ruggedness index (TRI), topographic position index (TPI)."
    ),
    geometry   = static_geom, bbox = c(-180, -90, 180, 90),
    properties = c(static_props, list(dataset = "static", layer = "topography", gsd = 500)),
    links      = common_links(),
    assets = list(
      topo_nc = list(
        href = gh_url(topo_nc), title = "Topographic diversity NC",
        description = "Slope (deg), aspect (deg), TRI, TPI; derived from NASADEM at 500m.",
        type = "application/x-netcdf", roles = list("data")
      )
    )
  ), "static_topography")

  # ── Append item links to collection and re-write ──────────────────────────
  item_links <- purrr::map(items_written, function(it) {
    list(rel = "item", href = basename(it$file), type = "application/json", title = it$id)
  })
  collection$links <- c(collection$links, item_links)
  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)

  if (verbose) message("Generated static layers STAC: ", length(items_written), " items in ", stac_dir)

  collection_file
}

