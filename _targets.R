# ============================================================================
# EMMA Environmental Data Pipeline
# ============================================================================
# This pipeline assembles environmental datasets for the EMMA project using
# targets for workflow orchestration. 

message("Starting tar_make()")

# check what system we are on
  sys_info <- Sys.info(); message(paste("System info:",paste(names(sys_info), sys_info, sep="=", collapse = "; ")))
  # if nodename includes "ccr.buffalo.edu", set working directory to /gscratch/scrubbed/...
  if (grepl("ccr.buffalo.edu", sys_info[["nodename"]])) {
    setwd("~/project/projects/emma/emma_envdata")
    message(paste("Set working directory to:", getwd()))  
  }

library(targets)
# tar_make()

tar_source("R")  # source all R files; unlike devtools::load_all(), tar_source() makes functions available to crew workers
description_packages <- load_description_packages(verbose=TRUE)  # Load all packages from DESCRIPTION and get list


#If running this locally, make sure to set up github credentials using gitcreds::gitcreds_set()

  options(tidyverse.quiet = TRUE)

  # Ensure output directories exist early (before terra options)
  dir.create("data/temp/terra", recursive = TRUE, showWarnings = FALSE)
  dir.create("data/target_outputs", recursive = TRUE, showWarnings = FALSE)

  # GitHub release repository configuration - releases are used to store target objects and publish final data
  gh_repo_config <- list(
    repo = "AdamWilsonLab/emma_envdata",
    tag = "targets-cache",
    cache_dir = "_targets/cache" #this is local cache for speed
  )

  # Store config as environment variables for upload function to use
  Sys.setenv(
    TAR_GH_RELEASE_REPO = gh_repo_config$repo,
    TAR_GH_RELEASE_TAG = gh_repo_config$tag,
#    TAR_GH_RELEASE_FORMAT = gh_repo_config$format,
    TAR_GH_RELEASE_CACHE_DIR = gh_repo_config$cache_dir
  )

  # Download cached targets from GitHub release before tar_option_set() so the
  # restored store is visible before any cue or format options are applied.
  source('R/tar_release_storage.R')
 # tar_download_github_release(
 #   repo = gh_repo_config$repo,
 #   tag = gh_repo_config$tag,
 #   cache_dir = gh_repo_config$cache_dir,
 #   verbose = TRUE
 # )

  tar_option_set(
    #controller = if (Sys.getenv("GITHUB_ACTIONS") != "true") crew::crew_controller_local(workers = 16) else NULL,
    memory = "transient", 
    garbage_collection = TRUE,  # run gc() after each target to free memory
    packages = description_packages,  # Use all packages from DESCRIPTION file
    repository = "local",  # Store targets locally; upload to release after tar_make() completes
    cue = tar_cue(mode = "thorough"),  # Recompute if any inputs change
    format = "qs"  # targets uses qs2 under the hood for this format
  )

  terraOptions(tempdir = "data/temp/terra", memfrac = 0.8)

  # All SpatRaster targets use COG-backed GeoTIFF storage via geotargets
  geotargets::geotargets_option_set(gdal_raster_driver = "COG")

  # Set cleanup behavior based on execution environment
  # In GitHub Actions, we want to clean up temp files to avoid filling up disk space.  Locally, we may want to keep them for debugging or inspection.
  cleanup_mode <- Sys.getenv("GITHUB_ACTIONS") == "true"
  if (interactive()) {
    message("Cleanup mode: ", if (cleanup_mode) "ENABLED (GitHub Actions)" else "DISABLED (Local server)")
  }

# Ensure things are clean
#  unlink(file.path("data/temp/"), recursive = TRUE, force = TRUE)
#  unlink(file.path("data/raw_data/", recursive = TRUE, force = TRUE))
#  message(paste("Objects:",ls(),collapse = "\n"))

  # Set MODIS/VIIRS date range as variables
#  modis_start_date <- "2000-02-18"  # MODIS Terra first available data
#  viirs_start_date <- "2012-01-01"  # VIIRS first available data
#  burn_start_date  <- "2000-11-01"  # MCD64A1 first available data
#  modis_end_date   <- as.character(Sys.Date())

  modis_start_date <- "2026-03-01"  # MODIS Terra first available data
  viirs_start_date <- "2026-03-01"  # VIIRS first available data
  burn_start_date  <- "2026-03-01"  # MCD64A1 first available data
  # Lag ~14 days past month end so both 16-day MODIS composites are published
  # on AppEEARS before the month enters the pipeline (avoids partial data).
  modis_end_date   <- as.character(as.Date(format(Sys.Date() - 14, "%Y-%m-01")) - 1)



list(
  ##################### Input Shapefiles/Vectors (sf objects stored in qs) #########################
  
  tar_target(
    vegmap,
    get_vegmap(
      repo = "AdamWilsonLab/emma_envdata",
      tag = "vegmap2024",
      file = "NVM2024final_Shapefile.zip",
      local_dir = "data/manual_download/NVM2024",
      shapefile_name = "NVM2024Final_IEM5_12_07012025.shp"
    ),
    cue = tar_cue(mode = "never")  # Manual download: only run locally, never on CI
  ),

  tar_target(
    remnants,
    get_remnants(
      repo      = "AdamWilsonLab/emma_envdata",
      tag       = "manual-data",
      local_dir = "data/manual_download/RLE_2021_Remnants"
    ),
    cue = tar_cue(mode = "never")  # Manual download: only run locally, never on CI
  ),

  tar_target(
    capenature_fires,
    sf::st_read("data/manual_download/All_fires_23_24_gw/All_fires_23_24_gw.shp"),
    cue = tar_cue(mode = "never")  # Manual download: only run locally, never on CI
  ),

# Get country boundary
  tar_target( 
    country,
    get_country(),
    cue = tar_cue(mode = "never")  # Manual download: only run locally, never on CI
  ),

  # Create domain file based on country boundary and vegmap
  tar_target( 
    domain_boundary,
    domain_define(vegmap = vegmap, country = country),
  ),

# Domain raster with pixel IDs, remnants, and distance to remnants. This defines the model grid that is used for everything!
  geotargets::tar_terra_rast(
    domain.tif,
    domain_rasterize(
      domain_boundary = domain_boundary,
      remnants = remnants
    ),
    cue = tar_cue(mode = "never")  # Manual download: only run locally, never on CI
    #   targets::tar_invalidate(domain.tif) #run this to force regeneration of domain grid (e.g. if remnant layer is updated) which will restart everything below
  ),

  # Export domain raster to GeoParquet format for easy distribution 
  tar_target(
    domain_geoparquet,
    domain_to_geoparquet(
      domain_raster_file = domain.tif,
      out_file = "data/target_outputs/domain.parquet",
      verbose = TRUE
    ),
    cue = tar_cue(mode = "never"),  # Manual download: only run locally, never on CI,
    format = "file"
  ),

# Rasterize the vegetation map
  geotargets::tar_terra_rast(
    vegmap.tif,
    process_vegmap(
      domain_raster = domain.tif,
      vegmap_shp    = vegmap
    ),
    cue = tar_cue(mode = "never")  # Manual download: only run locally, never on CI
  ),

# Climate CHELSA bioclimatic variables (BIO1-BIO19)
    tar_target( 
      climate_chelsa,
      get_climate_chelsa(
        domain = domain_boundary,
        cleanup = cleanup_mode,
        verbose = TRUE),
    cue = tar_cue(mode = "never"),  # Manual download: only run locally, never on CI
      format = "file"
    ),

  # Cloud cover: Wilson MODCF mean annual and seasonality (EarthEnv, ~1km → 500m domain grid)
  geotargets::tar_terra_rast(
    clouds.tif,
    get_clouds_wilson(
      domain         = domain_boundary,
      domain_raster  = domain.tif,
      temp_directory = "data/temp/appeears/clouds_wilson/",
      cleanup        = cleanup_mode,
      verbose        = TRUE
    ),
    cue = tar_cue(mode = "never")  # Manual download: only run locally, never on CI
  ),

  ##################### AppEEARS Static Data Processing #########################
  # Sequential targets for AppEEARS elevation: submit task, then poll for results
  # Allows independent timeouts and retries for long-running API calls
  tar_target(
    elevation_task_id,
    submit_elevation_task(
      domain_vector = domain_boundary,
      verbose = TRUE
    )
  ),

  geotargets::tar_terra_rast(
    elevation.tif,
    download_elevation_results(
      task_id        = elevation_task_id,
      domain_vector  = domain_boundary,
      domain_raster  = domain.tif,
      temp_directory = "data/temp/appeears/elevation_nasadem/",
      cleanup = cleanup_mode,
      verbose        = TRUE
    ),
    cue = tar_cue(mode = "never")
  ),

  # Generate manifest of all targets from live pipeline store (via tar_meta)
  tar_target(
    release_manifest,
    generate_release_manifest(),
    format = "file"
  ),

  # Soil properties: SoilGrids v2 (ISRIC REST API)
  # Properties: SOC, clay, sand, pH, bulk density averaged over 0-30cm depth
  geotargets::tar_terra_rast(
    soils.tif,
    get_soilgrid(
      domain_raster  = domain.tif,
      temp_directory = "data/temp/appeears/soilgrid/",
      cleanup        = cleanup_mode,
      verbose        = TRUE
    ),
    cue = tar_cue(mode = "never")  # Static data: only run locally, never on CI
  ),

  # Topographic diversity metrics derived from the NASADEM elevation.tif
  # Metrics: slope, aspect, TRI, TPI, topographic diversity index
  geotargets::tar_terra_rast(
    geodiversity.tif,
    process_topographic_diversity(
      elevation_file = elevation.tif,
      domain_raster  = domain.tif,
      focal_radius   = 1L,
      verbose        = TRUE
    ),
    cue = tar_cue(mode = "never")  # Derived from elevation.tif: only run locally, never on CI
  ),

  # Combine all static layers into a single geoparquet: one row per 500m pixel,
  # attributes for all static covariates (remnants, elevation.tif, climate, clouds,
  # soil, topography, vegmap). Output used for model fitting and distribution.
  tar_target(
    static_geoparquet,
    combine_static_layers_to_geoparquet(
      domain_parquet   = domain_geoparquet,
      domain_raster  = domain.tif,
      elevation      = elevation.tif,
      climate_files  = climate_chelsa,
      clouds         = clouds.tif,
      soil           = soils.tif,
      topo           = geodiversity.tif,
      vegmap         = vegmap.tif,
      out_file         = "data/target_outputs/static_covariates.parquet",
      verbose          = TRUE
    ),
    format = "file",
    cue = tar_cue(mode = "never")  # Static data: only run locally, never on CI
  ),

  # ============================================================================
  # MODIS VI Download Pipeline (Dynamically Branched)
  # ============================================================================

  # All months in [modis_start_date, modis_end_date]. The date range is stable
  # across server and CI runs (no Sys.Date() in the hash), so branch mappings
  # only change when a new complete month is added by modis_end_date advancing.
  tar_target(
    vi_modis_pending,
    generate_composite_sequence(start_date = modis_start_date, end_date = modis_end_date)
  ),

  # Dynamically submit 16-day composite AppEEARS tasks
  tar_target(
    vi_modis_task_ids,
    {
      # Within this branch, vi_modis_pending is auto-sliced to one row
      submit_modis_vi(
        domain_vector  = domain_boundary,
        composite_date = vi_modis_pending$composite_date,
        composite_end  = vi_modis_pending$composite_end,
        out_dir        = "data/target_outputs/modis_vi/",
        gh_release_tag = "vi_modis_dynamic_raster"
      )
    },
    pattern = map(vi_modis_pending)
  ),

  # Download GeoTIFF files from AppEEARS (I/O only).
  # AppEEARS tasks can queue for hours or days; error = "continue" lets the
  # pipeline finish with available data and retries this branch on the next
  # tar_make() against the same cached task ID.
  tar_target(
    vi_modis_geotiff,
    {
      download_modis_vi_geotiff(
        task_id        = vi_modis_task_ids,
        composite_date = vi_modis_pending$composite_date,
        composite_end  = vi_modis_pending$composite_end,
        domain_vector  = domain_boundary,
        temp_directory = "data/temp/appeears/modis_vi/",
        cleanup        = cleanup_mode,
        verbose        = TRUE
      )
    },
    pattern = map(vi_modis_task_ids, vi_modis_pending),
    error   = "continue"
  ),

  # Project raw AppEEARS downloads to domain-aligned COGs (one per sensor per composite).
  # Returns c(terra_tif, aqua_tif) tracked as files by targets.
  tar_target(
    vi_modis_grid,
    vi_modis_geotiff_to_grid(
      geotiff_directory = vi_modis_geotiff,
      domain_raster     = domain.tif,
      composite_date    = vi_modis_pending$composite_date,
      out_dir           = "data/target_outputs/modis_vi/",
      cleanup           = cleanup_mode,
      verbose           = TRUE
    ),
    pattern = map(vi_modis_geotiff, vi_modis_pending),
    format  = "file"
  ),

  # Convert sensor grid COGs to parquet (one parquet per composite)
  tar_target(
    vi_modis_parquet,
    vi_modis_geotiff_to_parquet(
      tif_files      = vi_modis_grid,
      domain_raster  = domain.tif,
      composite_date = vi_modis_pending$composite_date,
      out_dir        = "data/target_outputs/modis_vi/",
      verbose        = TRUE
    ),
    pattern = map(vi_modis_grid, vi_modis_pending),
    format  = "file"
  ),

  # ============================================================================
  # VIIRS VI Pipeline (VNP13A1 S-NPP + VJ113A1 NOAA-20, dynamically branched)
  # ============================================================================

  tar_target(
    vi_viirs_pending,
    generate_composite_sequence(start_date = viirs_start_date, end_date = modis_end_date)
  ),

  tar_target(
    vi_viirs_task_ids,
    submit_viirs_vi(
      domain_vector  = domain_boundary,
      composite_date = vi_viirs_pending$composite_date,
      composite_end  = vi_viirs_pending$composite_end,
      out_dir        = "data/target_outputs/viirs_vi/",
      gh_release_tag = "vi_viirs_dynamic_raster"
    ),
    pattern = map(vi_viirs_pending)
  ),

  tar_target(
    vi_viirs_geotiff,
    download_viirs_vi_geotiff(
      task_id        = vi_viirs_task_ids,
      composite_date = vi_viirs_pending$composite_date,
      composite_end  = vi_viirs_pending$composite_end,
      domain_vector  = domain_boundary,
      temp_directory = "data/temp/appeears/viirs_vi/",
      cleanup        = cleanup_mode,
      verbose        = TRUE
    ),
    pattern = map(vi_viirs_task_ids, vi_viirs_pending),
    error   = "continue"
  ),

  tar_target(
    vi_viirs_grid,
    vi_viirs_geotiff_to_grid(
      geotiff_directory = vi_viirs_geotiff,
      domain_raster     = domain.tif,
      composite_date    = vi_viirs_pending$composite_date,
      out_dir           = "data/target_outputs/viirs_vi/",
      cleanup           = cleanup_mode,
      verbose           = TRUE
    ),
    pattern = map(vi_viirs_geotiff, vi_viirs_pending),
    format  = "file"
  ),

  tar_target(
    vi_viirs_parquet,
    vi_viirs_geotiff_to_parquet(
      tif_files      = vi_viirs_grid,
      domain_raster  = domain.tif,
      composite_date = vi_viirs_pending$composite_date,
      out_dir        = "data/target_outputs/viirs_vi/",
      verbose        = TRUE
    ),
    pattern = map(vi_viirs_grid, vi_viirs_pending),
    format  = "file"
  ),

  # Generate unified STAC Collection for all VI sensors (MODIS + VIIRS)
  tar_target(
    vi_stac,
    generate_modis_vi_stac(
      tif_files            = vi_modis_grid,
      viirs_tif_files      = vi_viirs_grid,
      stac_dir             = "data/stac/vi",
      parent_catalog_path  = "data/stac",
      gh_repo              = "AdamWilsonLab/emma_envdata",
      gh_release_tag       = "vi_modis_dynamic_raster",
      gh_release_tag_viirs = "vi_viirs_dynamic_raster",
      verbose              = TRUE
    ),
    format     = "file",
    deployment = "main"
  ),

  # ============================================================================
  # MODIS Burned Area Pipeline (MCD64A1, dynamically branched by month)
  # ============================================================================

  tar_target(
    burn_modis_pending,
    generate_monthly_sequence(start_date = burn_start_date, end_date = modis_end_date)
  ),

  # Submit one AppEEARS task per missing month (branched)
  tar_target(
    burn_modis_task_ids,
    submit_burn_date_modis_task(
      domain_vector  = domain_boundary,
      month_start    = burn_modis_pending$month_start,
      month_end      = burn_modis_pending$month_end,
      out_dir        = "data/target_outputs/burndates/",
      gh_release_tag = "burn_dates_modis_raster",
      verbose        = TRUE
    ),
    pattern = map(burn_modis_pending)
  ),

  # Download GeoTIFF results from AppEEARS (I/O only)
  tar_target(
    burn_modis_geotiff,
    download_burn_date_modis_geotiff(
      task_id        = burn_modis_task_ids,
      month_start    = burn_modis_pending$month_start,
      month_end      = burn_modis_pending$month_end,
      domain_vector  = domain_boundary,
      temp_directory = "data/temp/appeears/burn_dates_modis/",
      cleanup        = cleanup_mode,
      verbose        = TRUE
    ),
    pattern = map(burn_modis_task_ids, burn_modis_pending),
    error   = "continue"
  ),

  # Project raw downloads to domain-aligned grid COG (burn_modis_YYYYMM.tif)
  tar_target(
    burn_modis_grid,
    burn_modis_geotiff_to_grid(
      geotiff_directory = burn_modis_geotiff,
      domain_raster     = domain.tif,
      month_start       = burn_modis_pending$month_start,
      out_dir           = "data/target_outputs/burndates/",
      cleanup           = cleanup_mode,
      verbose           = TRUE
    ),
    pattern = map(burn_modis_geotiff, burn_modis_pending),
    format  = "file"
  ),

  # Convert grid COG to parquet
  tar_target(
    burn_modis_parquet,
    burn_date_modis_geotiff_to_parquet(
      tif_file      = burn_modis_grid,
      domain_raster = domain.tif,
      month_start   = burn_modis_pending$month_start,
      out_dir       = "data/target_outputs/burndates/",
      verbose       = TRUE
    ),
    pattern = map(burn_modis_grid, burn_modis_pending),
    format  = "file"
  ),

  # ============================================================================
  # VIIRS Burned Area Pipeline (VNP64A1, dynamically branched by month)
  # Coverage: 2012-01-01 to present
  # ============================================================================

  tar_target(
    burn_viirs_pending,
    generate_monthly_sequence(start_date = viirs_start_date, end_date = modis_end_date)
  ),

  tar_target(
    burn_viirs_task_ids,
    submit_burn_date_viirs_task(
      domain_vector  = domain_boundary,
      month_start    = burn_viirs_pending$month_start,
      month_end      = burn_viirs_pending$month_end,
      out_dir        = "data/target_outputs/burndates/",
      gh_release_tag = "burn_dates_viirs_raster",
      verbose        = TRUE
    ),
    pattern = map(burn_viirs_pending)
  ),

  tar_target(
    burn_viirs_geotiff,
    download_burn_date_viirs_geotiff(
      task_id        = burn_viirs_task_ids,
      month_start    = burn_viirs_pending$month_start,
      month_end      = burn_viirs_pending$month_end,
      domain_vector  = domain_boundary,
      temp_directory = "data/temp/appeears/burn_dates_viirs/",
      cleanup        = cleanup_mode,
      verbose        = TRUE
    ),
    pattern = map(burn_viirs_task_ids, burn_viirs_pending),
    error   = "continue"
  ),

  # Project raw downloads to domain-aligned grid COG (burn_viirs_YYYYMM.tif)
  tar_target(
    burn_viirs_grid,
    burn_viirs_geotiff_to_grid(
      geotiff_directory = burn_viirs_geotiff,
      domain_raster     = domain.tif,
      month_start       = burn_viirs_pending$month_start,
      out_dir           = "data/target_outputs/burndates/",
      cleanup           = cleanup_mode,
      verbose           = TRUE
    ),
    pattern = map(burn_viirs_geotiff, burn_viirs_pending),
    format  = "file"
  ),

  tar_target(
    burn_viirs_parquet,
    burn_date_viirs_geotiff_to_parquet(
      tif_file      = burn_viirs_grid,
      domain_raster = domain.tif,
      month_start   = burn_viirs_pending$month_start,
      out_dir       = "data/target_outputs/burndates/",
      verbose       = TRUE
    ),
    pattern = map(burn_viirs_grid, burn_viirs_pending),
    format  = "file"
  ),

  # ============================================================================
  # Derived fire covariates (aggregated; depend on all monthly parquets above)
  # ============================================================================

  # Merge MODIS + VIIRS burn records into a single deduplicated fire event table
  tar_target(
    burn_events_merged,
    {
      # Explicit dependencies ensure all monthly parquets are complete before merging
      force(burn_modis_parquet)
      force(burn_viirs_parquet)
      merge_burn_dates(
        burn_dir = "data/target_outputs/burndates/",
        verbose  = TRUE
      )
    }
  ),

  # Compute most-recent-burn and fire age at every MODIS VI observation date
  tar_target(
    most_recent_burn,
    {
      # Query at the same dates as MODIS VI observations so fire age aligns exactly
      vi_dates <- vi_load_observation_dates(
        modis_vi_dir = "data/target_outputs/modis_vi",
        verbose      = TRUE
      )
      compute_most_recent_burn(
        burn_events = burn_events_merged,
        query_dates = vi_dates,
        out_file    = "data/target_outputs/most_recent_burn.parquet",
        verbose     = TRUE
      )
    },
    format = "file"
  ),

  # Rasterize most_recent_burn parquet → domain-aligned COG snapshot (tar_terra_rast)
  geotargets::tar_terra_rast(
    recentburn.tif,
    most_recent_burn_to_grid(
      parquet_file  = most_recent_burn,
      domain_raster = domain.tif,
      verbose       = TRUE
    ),
    datatype = "INT4S"
  ),

  # Unified STAC Collection for burned area (MODIS + VIIRS COG rasters + recentburn COG).
  # Re-runs whenever any grid or the recentburn.tif snapshot changes.
  tar_target(
    burn_stac,
    generate_burn_stac(
      modis_tif_files        = burn_modis_grid,
      viirs_tif_files        = burn_viirs_grid,
      recentburn_file        = terra::sources(recentburn.tif)[[1]],
      stac_dir               = "data/stac/burn",
      gh_repo                = "AdamWilsonLab/emma_envdata",
      gh_release_tag_modis   = "burn_dates_modis_raster",
      gh_release_tag_viirs   = "burn_dates_viirs_raster",
      gh_release_tag_derived = "firehistory_dynamic",
      verbose                = TRUE
    ),
    format     = "file",
    deployment = "main"
  ),

  # Generate STAC Collection for static environmental layers (elevation.tif, climate, soil, etc.)
  tar_target(
    static_stac,
    generate_static_layers_stac(
      domain_file      = terra::sources(domain.tif)[[1]],
      domain_parquet   = domain_geoparquet,
      vegmap_file      = terra::sources(vegmap.tif)[[1]],
      elevation        = terra::sources(elevation.tif)[[1]],
      climate_files    = climate_chelsa,
      clouds           = terra::sources(clouds.tif)[[1]],
      soil             = terra::sources(soils.tif)[[1]],
      topo             = terra::sources(geodiversity.tif)[[1]],
      stac_dir         = "data/stac/static",
      gh_repo          = "AdamWilsonLab/emma_envdata",
      gh_release_tag   = "static_data",
      verbose          = TRUE
    ),
    format     = "file",
    deployment = "main"
  ),

  ##################### GitHub Release Uploads #########################
  # All upload targets use deployment = "main" so they only run on the main branch,
  # not on every feature-branch push.

  # Upload all static NetCDF files (domain, elevation.tif, climate, clouds, soil, topography)
  tar_target(
    upload_static,
    upload_to_github_release(
      files = c(
        terra::sources(domain.tif)[[1]],
        "data/target_outputs/domain.parquet",
        terra::sources(vegmap.tif)[[1]],
        terra::sources(elevation.tif)[[1]],
        climate_chelsa,
        terra::sources(clouds.tif)[[1]],
        terra::sources(soils.tif)[[1]],
        terra::sources(geodiversity.tif)[[1]]
      ),
      repo         = gh_repo_config$repo,
      release_tag  = "static_data",
      release_name = "Static Environmental Data",
      overwrite    = TRUE,
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Upload dynamic MODIS VI parquet files
  # Pass vi_modis_parquet directly — targets aggregates the branched vector automatically,
  # so this target re-runs whenever a new month is added.
  tar_target(
    upload_vi_modis,
    upload_to_github_release(
      files        = vi_modis_parquet[!is.na(vi_modis_parquet) & !grepl("\\.skip$", vi_modis_parquet)],
      repo         = gh_repo_config$repo,
      release_tag  = "vi_modis_dynamic",
      release_name = "Dynamic MODIS Vegetation Index",
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Upload MODIS burned area parquets
  tar_target(
    upload_burn_modis,
    upload_to_github_release(
      files        = burn_modis_parquet[!grepl("\\.skip$", burn_modis_parquet)],
      repo         = gh_repo_config$repo,
      release_tag  = "burndate_modis_dynamic",
      release_name = "Dynamic MODIS Burned Area (MCD64A1)",
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Upload VIIRS burned area parquets
  tar_target(
    upload_burn_viirs_data,
    upload_to_github_release(
      files        = burn_viirs_parquet[!grepl("\\.skip$", burn_viirs_parquet)],
      repo         = gh_repo_config$repo,
      release_tag  = "burndate_viirs_dynamic",
      release_name = "Dynamic VIIRS Burned Area (VNP64A1)",
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Upload MODIS VI sensor raster grids (Terra + Aqua NC files)
  tar_target(
    upload_vi_modis_grid,
    upload_to_github_release(
      files        = vi_modis_grid[!grepl("\\.skip$", vi_modis_grid)],
      repo         = gh_repo_config$repo,
      release_tag  = "vi_modis_dynamic_raster",
      release_name = "Dynamic MODIS VI Rasters (Terra + Aqua, 16-day composites)",
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Upload VIIRS VI sensor raster grids (S-NPP + NOAA-20 NC files)
  tar_target(
    upload_vi_viirs_grid,
    upload_to_github_release(
      files        = vi_viirs_grid[!grepl("\\.skip$", vi_viirs_grid)],
      repo         = gh_repo_config$repo,
      release_tag  = "vi_viirs_dynamic_raster",
      release_name = "Dynamic VIIRS VI Rasters (S-NPP + NOAA-20, 16-day composites)",
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Upload MODIS burned area raster grids
  tar_target(
    upload_burn_modis_grid,
    upload_to_github_release(
      files        = burn_modis_grid[!grepl("\\.skip$", burn_modis_grid)],
      repo         = gh_repo_config$repo,
      release_tag  = "burn_dates_modis_raster",
      release_name = "Dynamic MODIS Burned Area Rasters (MCD64A1)",
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Upload VIIRS burned area raster grids
  tar_target(
    upload_burn_viirs_grid,
    upload_to_github_release(
      files        = burn_viirs_grid[!grepl("\\.skip$", burn_viirs_grid)],
      repo         = gh_repo_config$repo,
      release_tag  = "burn_dates_viirs_raster",
      release_name = "Dynamic VIIRS Burned Area Rasters (VNP64A1)",
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Upload derived fire history COG (most recent burn snapshot raster)
  tar_target(
    upload_fire_history,
    upload_to_github_release(
      files        = terra::sources(recentburn.tif)[[1]],
      repo         = gh_repo_config$repo,
      release_tag  = "firehistory_dynamic",
      release_name = "Fire History (most recent burn, postfire age)",
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Generate parent STAC Catalog linking all datasets.
  # force() calls create explicit targets dependencies so the catalog is never
  # written before the collection JSONs exist.
  # Note: deployment="main" means "run in the main R process (not a crew worker)",
  # NOT "only run on the main git branch".
  tar_target(
    emma_stac_catalog,
    {
      force(vi_stac)      # wait for vi_collection.json to be written
      force(burn_stac)    # wait for burn_collection.json to be written
      force(static_stac)  # wait for static_collection.json to be written
      generate_emma_stac_catalog(
        stac_base_dir       = "data/stac",
        dataset_collections = list(
          vi     = "data/stac/vi",  # key "vi" → vi_collection.json
          burn   = "data/stac/burn",      # key "burn" → burn_collection.json
          static = "data/stac/static"     # key "static" → static_collection.json
          # fire_history removed: recentburn item lives inside the burn collection
        ),
        gh_repo = "AdamWilsonLab/emma_envdata",
        verbose = TRUE
      )
    },
    format     = "file",
    deployment = "main"
  ),

  # Upload STAC catalog + all collection JSON files
  tar_target(
    upload_stac_catalog,
    {
      stac_files <- c(
        file.path("data/stac", "catalog.json"),
        list.files("data/stac", pattern = "\\.json$", full.names = TRUE, recursive = TRUE)
      ) |> unique()

      upload_to_github_release(
        files        = stac_files,
        repo         = gh_repo_config$repo,
        release_tag  = "stac",
        release_name = "STAC Catalog — Current",
        verbose      = TRUE,
        overwrite    = TRUE,  # always re-upload STAC JSONs — content changes with every new month
        emma_stac_catalog,  # explicit dependency — catalog must be written first
        vi_stac,
        burn_stac,
        static_stac
      )
    },
    deployment = "main"
  ),

# ============================================================================
# POST-PRIME: Upload completed targets cache to GitHub release
# ============================================================================
# Run this block manually after completing a full `tar_make()` on a local server
# to push the cache to the `targets-cache` GitHub release. Subsequent GitHub
# Actions runs will then restore from this release instead of recomputing from scratch.
#
# When to run:
#   1. After first-time setup (full historical download)
#   2. After changing the domain grid (tar_invalidate(domain.tif) was called)
#   3. After adding a new multi-year dataset
#
# Usage: select this block and run it, or source() with chdir = TRUE.
# Do NOT include this in a tar_make() call — it lives outside the list(...) above.

if (FALSE) {
  source("R/tar_release_storage.R")
  tar_upload_github_release(
    repo      = "AdamWilsonLab/emma_envdata",
    tag       = "targets-cache",
    cache_dir = "_targets/cache",
    verbose   = TRUE
  )
}

# NOTE: _targets.R must return the pipeline list as its final expression.
# The if(FALSE) block above must stay BEFORE this closing ).
)
