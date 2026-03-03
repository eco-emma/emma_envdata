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
    pattern = "^dynamic_modis_vi_\\d{6}\\.gz\\.parquet$",
    full.names = FALSE
  )
  
  if (length(parquet_files) == 0) {
    if (verbose) warning("No MODIS VI parquet files found in ", parquet_dir)
    return(NA_character_)
  }
  
  # Extract year-month from filenames
  dates <- as.Date(paste0(gsub(".*_(\\d{6})\\..*", "\\1", parquet_files), "01"), "%Y%m%d")
  
  if (verbose) message("Generating STAC Collection for MODIS VI with ", length(parquet_files), " monthly files")
  
  # Create STAC Collection (part of parent catalog)
  collection <- list(
    stac_version = "1.0.0",
    stac_extensions = c(
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
        href = "../catalog.json",
        type = "application/json"
      ),
      list(
        rel = "parent",
        href = "../catalog.json",
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
        roles = c("processor"),
        url = "https://appeears.org/"
      ),
      list(
        name = "EMMA Lab",
        description = "Data processing and aggregation",
        roles = c("processor"),
        url = "https://adamwilsonlab.github.io/"
      )
    ),
    summaries = list(
      sci_doi = "10.5067/MODIS/MOD13A1.061|10.5067/MODIS/MYD13A1.061",
      platforms = c("Terra", "Aqua"),
      instruments = c("MODIS"),
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
  
  # Write collection.json
  collection_file <- file.path(stac_dir, "collection.json")
  jsonlite::write_json(collection, collection_file, pretty = TRUE, auto_unbox = TRUE)
  
  if (verbose) message("Created STAC Collection: ", collection_file)
  
  # Create individual Item files
  for (i in seq_along(parquet_files)) {
    pq_file <- parquet_files[i]
    pq_date <- dates[i]
    year_month <- format(pq_date, "%Y%m")
    
    # GitHub release URL
    gh_raw_url <- paste0(
      "https://github.com/", gh_repo, "/releases/download/", gh_release_tag, "/",
      pq_file
    )
    
    item <- list(
      stac_version = "1.0.0",
      stac_extensions = c(
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
      properties = list(
        `datetime` = paste0(format(pq_date, "%Y-%m-%d"), "T00:00:00Z"),
        start_datetime = paste0(format(pq_date, "%Y-%m-01"), "T00:00:00Z"),
        end_datetime = paste0(format(as.Date(paste0(format(pq_date + 31, "%Y-%m"), "-01")) - 1, "%Y-%m-%d"), "T23:59:59Z"),
        platforms = c("Terra", "Aqua"),
        instruments = c("MODIS"),
        gsd = 500,
        dataset = "modis_vi"
      ),
      links = list(
        list(
          rel = "collection",
          href = "collection.json",
          type = "application/json"
        ),
        list(
          rel = "root",
          href = "../catalog.json",
          type = "application/json"
        ),
        list(
          rel = "parent",
          href = "collection.json",
          type = "application/json"
        )
      ),
      assets = list(
        data = list(
          href = gh_raw_url,
          title = paste0("MODIS VI Parquet - ", year_month),
          description = "Enhanced Vegetation Index observations in parquet format",
          type = "application/octet-stream",
          roles = c("data")
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
    collection_file <- file.path(collection_path, "collection.json")
    
    if (file.exists(collection_file)) {
      # Relative path from catalog to collection
      rel_path <- paste0(dataset_name, "/collection.json")
      
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
