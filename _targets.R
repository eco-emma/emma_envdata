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
# tar_glimpse()
r_source_files <- list.files(
  "R",
  pattern = "^[^.].*\\.R$",
  full.names = TRUE
)
r_source_files <- r_source_files[
  !basename(r_source_files) %in% c(
    "backfill_stac_release.R",
    "ci_appeears_update.R"
  )
]
tar_source(r_source_files)
description_packages <- load_description_packages(verbose=TRUE)  # Load all packages from DESCRIPTION and get list


#If running this locally, make sure to set up github credentials using gitcreds::gitcreds_set()

  options(tidyverse.quiet = TRUE)

  # Ensure output directories exist early (before terra options)
  dir.create("data/temp/terra", recursive = TRUE, showWarnings = FALSE)
  dir.create("data/target_outputs", recursive = TRUE, showWarnings = FALSE)

  # GitHub release repository configuration — targets-cache stores the pipeline state
  gh_repo_config <- list(
    repo = "eco-emma/emma_envdata",
    tag = "targets-cache",
    cache_dir = "_targets/user/cache" #this is local cache for speed
  )

  # ── Single source of truth for GitHub release tag names ──────────────────
  # Update tag strings here only; every upload target and STAC generator reads
  # from this list so renaming one tag cannot silently break another.
  release_tags <- list(
    static             = "static_data",
    vi_modis_terra     = "vi_modis_terra_raster",
    vi_modis_aqua      = "vi_modis_aqua_raster",
    vi_viirs_raster    = "vi_viirs_raster",
    vi_modis_parquet   = "vi_modis_parquet",
    vi_viirs_parquet   = "vi_viirs_parquet",
    burn_modis_raster  = "burn_modis_raster",
    burn_viirs_raster  = "burn_viirs_raster",
    burn_modis_parquet = "burn_modis_parquet",
    burn_viirs_parquet = "burn_viirs_parquet",
    fireage            = "fireage",
    stac               = "stac",
    stac_vi            = "stac-vi",
    stac_burn          = "stac-burn",
    stac_static        = "stac-static",
    cache              = "targets-cache",
    readme_assets      = "readme-assets"
  )

  # Store config as environment variables for upload function to use
  Sys.setenv(
    TAR_GH_RELEASE_REPO = gh_repo_config$repo,
    TAR_GH_RELEASE_TAG = gh_repo_config$tag,
#    TAR_GH_RELEASE_FORMAT = gh_repo_config$format,
    TAR_GH_RELEASE_CACHE_DIR = gh_repo_config$cache_dir
  )

  # Download cached targets meta once per Actions job before tar_option_set()
  # so the restored store is visible. Re-running this on every
  # tar_outdated()/tar_make() parse overwrites freshly built pending meta with
  # the CCR snapshot (false-green in run 38016708889).
  if (Sys.getenv("GITHUB_ACTIONS") == "true" &&
      !identical(Sys.getenv("TAR_GH_META_RESTORED"), "true")) {
    source("R/tar_release_storage.R")
    tar_download_github_release(
      repo = gh_repo_config$repo,
      tag = gh_repo_config$tag,
      cache_dir = gh_repo_config$cache_dir,
      meta_only = TRUE,
      verbose = TRUE
    )
    meta_path <- "_targets/meta/meta"
    if (!file.exists(meta_path) || file.size(meta_path) == 0) {
      stop(
        "Refusing to backfill history on GitHub Actions: ",
        "targets-cache meta was not restored. Prime on CCR with ",
        "tar_upload_github_release(), then re-enable the weekly workflow.",
        call. = FALSE
      )
    }
    Sys.setenv(TAR_GH_META_RESTORED = "true")
  }

  tar_option_set(
    #controller = if (Sys.getenv("GITHUB_ACTIONS") != "true") crew::crew_controller_local(workers = 16) else NULL,
    memory = "transient", 
    garbage_collection = TRUE,  # run gc() after each target to free memory
    packages = description_packages,  # Use all packages from DESCRIPTION file
    repository = "local",  # Store targets locally; upload to release after tar_make() completes
    cue = tar_cue(mode = "thorough"),  # Recompute if any inputs change
    format = "rds"  # rds is universally portable across R versions and platforms
  )

  terraOptions(tempdir = "data/temp/terra", memfrac = 0.8)

  # All SpatRaster targets use COG-backed GeoTIFF storage via geotargets
  geotargets::geotargets_option_set(gdal_raster_driver = "COG", gdal_vector_driver = "GPKG")

  # Set cleanup behavior based on execution environment
  # In GitHub Actions, we want to clean up temp files to avoid filling up disk space.  Locally, we may want to keep them for debugging or inspection.
  cleanup_mode <- Sys.getenv("GITHUB_ACTIONS") == "true"
  if (interactive()) {
    message("Cleanup mode: ", if (cleanup_mode) "ENABLED (GitHub Actions)" else "DISABLED (Local server)")
  }
  vegmap_raster_path <- "data/target_outputs/vegmap.tif"

# Ensure things are clean
#  unlink(file.path("data/temp/"), recursive = TRUE, force = TRUE)
#  unlink(file.path("data/raw_data/", recursive = TRUE, force = TRUE))
#  message(paste("Objects:",ls(),collapse = "\n"))

  # Set MODIS/VIIRS date range as variables
#  modis_start_date <- "2000-02-18"  # MODIS Terra first available data
#  viirs_start_date <- "2012-01-01"  # VIIRS first available data
#  burn_start_date  <- "2000-11-01"  # MCD64A1 first available data
#  modis_end_date   <- as.character(Sys.Date())

  modis_start_date <- "2000-01-01"  # MODIS Terra first available data
  viirs_start_date <- "2012-01-01"  # VIIRS first available data
  burn_start_date  <- "2000-01-01"  # MCD64A1 first available data
  
  # Lag ~14 days past month end so both 16-day MODIS composites are published
  # on AppEEARS before the month enters the pipeline (avoids partial data).
  modis_end_date   <- as.character(as.Date(format(Sys.Date() - 14, "%Y-%m-01")) - 1)



list(  
  tar_target(
    vegmap,
    get_vegmap(
      repo = gh_repo_config$repo,
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
      repo      = gh_repo_config$repo,
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

  # ── Static: rasterize CapeNature polygons to burned-pixel parquet ────────────
  # cue="never": manual data, only rerun locally when the shapefile is updated.
  # Add new date corrections to data/manual_download/capenature_date_fixes.csv
  # and re-run this target locally to apply them.
  tar_target(
    capenature_burn_events,
    process_capenature_to_parquet(
      capenature_fires = capenature_fires,
      domain_raster    = domain.tif,
      date_fixes_csv   = "data/manual_download/capenature_date_fixes.csv",
      out_file         = "data/target_outputs/burndates/capenature_burns.parquet",
      verbose          = TRUE
    ),
    format = "file",
    cue    = tar_cue(mode = "never")  # Static manual data: only rerun locally
  ),

# Get country boundary
  tar_target( 
    country,
    get_country(),
    cue = tar_cue(mode = "never")  # Manual download: only run locally, never on CI
  ),

  # Create domain file based on country boundary and vegmap
  geotargets::tar_terra_vect(
    domain_boundary.gpkg,
    domain_define(vegmap = vegmap, country = country),
    cue = tar_cue(mode = "never")  # Manual update: this affects all RS downloads to be careful if modified!
  ),

# Domain raster with pixel IDs, remnants, and distance to remnants. This defines the model grid that is used for everything!
  geotargets::tar_terra_rast(
    domain.tif,
    domain_rasterize(
      domain_boundary = domain_boundary.gpkg,
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
        domain = domain_boundary.gpkg,
        cleanup = cleanup_mode,
        verbose = TRUE),
    cue = tar_cue(mode = "never"),  # Manual download: only run locally, never on CI
      format = "file"
    ),

  # Cloud cover: Wilson MODCF mean annual and seasonality (EarthEnv, ~1km → 500m domain grid)
  geotargets::tar_terra_rast(
    clouds.tif,
    get_clouds_wilson(
      domain         = domain_boundary.gpkg,
      domain_raster  = domain.tif,
      temp_directory = "data/temp/appeears/clouds_wilson/",
      cleanup        = cleanup_mode,
      verbose        = TRUE
    ),
    cue = tar_cue(mode = "never")  # Manual download: only run locally, never on CI
  ),

  ##################### AppEEARS Static Data Processing #########################
  # Two-target elevation pipeline:
  #   1. elevation_task_id — checks for existing data and returns a sentinel or
  #      submits a new AppEEARS task.
  #      Sentinels:
  #        "cached"      → elevation.tif already in _targets/objects (skip all)
  #        "cached_temp" → raw AppEEARS GeoTIFFs in data/temp/appeears/elevation_nasadem/
  #                        (skip download, reprocess only)
  #        <task_id>     → new AppEEARS task submitted; poll + download + process
  #   2. elevation.tif — processes/downloads based on the sentinel/task ID above.
  # elevation_task_id: submit an AppEEARS elevation task (or return a sentinel
  # signalling that data are already cached).  error="continue" lets the rest
  # of the pipeline proceed if the AppEEARS daily request limit is hit; the
  # errored target is retried automatically on the next tar_make().
  tar_target(
    elevation_task_id,
    submit_elevation_task(
      domain_vector  = domain_boundary.gpkg,
      targets_store  = "_targets/objects",
      temp_directory = "data/temp/appeears/elevation_nasadem/",
      verbose        = TRUE
    ),
    error = "continue"
  ),

  geotargets::tar_terra_rast(
    elevation.tif,
    download_elevation_results(
      task_id        = elevation_task_id,
      domain_vector  = domain_boundary.gpkg,
      domain_raster  = domain.tif,
      temp_directory = "data/temp/appeears/elevation_nasadem/",
      cleanup        = cleanup_mode,
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
    {
      composites <- generate_composite_sequence(
        start_date = modis_start_date,
        end_date   = modis_end_date
      )
      terra_pending <- filter_pending_composites(
        composites     = composites,
        gh_release_tag = release_tags$vi_modis_terra,
        prefixes       = "vi_modis_terra_",
        verbose        = TRUE
      )
      aqua_pending <- filter_pending_composites(
        composites     = composites,
        gh_release_tag = release_tags$vi_modis_aqua,
        prefixes       = "vi_modis_aqua_",
        verbose        = TRUE
      )
      dplyr::bind_rows(terra_pending, aqua_pending) |>
        dplyr::distinct(composite_date, .keep_all = TRUE)
    }
  ),

  # Dynamically submit 16-day composite AppEEARS tasks.
  # error="continue": if AppEEARS returns "rate limit exceeded" for a branch,
  # that branch stop()s and is marked errored; the rest of the pipeline
  # proceeds, and errored branches are retried automatically on the next
  # tar_make() (targets retries errored branches by default in thorough mode).
  tar_target(
    vi_modis_task_ids,
    {
      # Within this branch, vi_modis_pending is auto-sliced to one row
      submit_modis_vi(
        domain_vector  = domain_boundary.gpkg,
        composite_date = vi_modis_pending$composite_date,
        composite_end  = vi_modis_pending$composite_end,
        out_dir               = "data/target_outputs/modis_vi/",
        gh_release_tag_terra  = release_tags$vi_modis_terra,
        gh_release_tag_aqua   = release_tags$vi_modis_aqua
      )
    },
    pattern = map(vi_modis_pending),
    error   = "continue"
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
        domain_vector  = domain_boundary.gpkg,
        temp_directory        = "data/temp/appeears/modis_vi/",
        gh_release_tag_terra  = release_tags$vi_modis_terra,
        gh_release_tag_aqua   = release_tags$vi_modis_aqua,
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
      out_dir               = "data/target_outputs/modis_vi/",
      gh_release_tag_terra  = release_tags$vi_modis_terra,
      gh_release_tag_aqua   = release_tags$vi_modis_aqua,
      cleanup           = cleanup_mode,
      verbose           = TRUE
    ),
    pattern = map(vi_modis_geotiff, vi_modis_pending)
    # format = "rds" (default): stored object is the path string, not the file
    # content hash. This lets CI skip branches whose paths are in the restored
    # targets cache without needing the actual COG files on disk.
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
    pattern = map(vi_modis_grid, vi_modis_pending)
    # format = "rds" (default): same rationale as vi_modis_grid above.
  ),

  # ============================================================================
  # VIIRS VI Pipeline (VNP13A1 S-NPP + VJ113A1 NOAA-20, dynamically branched)
  # ============================================================================

  tar_target(
    vi_viirs_pending,
    {
      composites <- generate_composite_sequence(
        start_date = viirs_start_date,
        end_date   = modis_end_date
      )
      filter_pending_composites(
        composites     = composites,
        gh_release_tag = release_tags$vi_viirs_raster,
        prefixes       = c("vi_viirs_snpp_", "vi_viirs_noaa20_"),
        verbose        = TRUE
      )
    }
  ),

  tar_target(
    vi_viirs_task_ids,
    submit_viirs_vi(
      domain_vector  = domain_boundary.gpkg,
      composite_date = vi_viirs_pending$composite_date,
      composite_end  = vi_viirs_pending$composite_end,
      out_dir        = "data/target_outputs/viirs_vi/",
      gh_release_tag = release_tags$vi_viirs_raster
    ),
    pattern = map(vi_viirs_pending),
    error   = "continue"  # rate-limit errors retry on next tar_make()
  ),

  tar_target(
    vi_viirs_geotiff,
    download_viirs_vi_geotiff(
      task_id        = vi_viirs_task_ids,
      composite_date = vi_viirs_pending$composite_date,
      composite_end  = vi_viirs_pending$composite_end,
      domain_vector  = domain_boundary.gpkg,
      temp_directory = "data/temp/appeears/viirs_vi/",
      gh_release_tag = release_tags$vi_viirs_raster,
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
      gh_release_tag    = release_tags$vi_viirs_raster,
      cleanup           = cleanup_mode,
      verbose           = TRUE
    ),
    pattern = map(vi_viirs_geotiff, vi_viirs_pending)
    # format = "rds" (default): same rationale as vi_modis_grid.
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
    pattern = map(vi_viirs_grid, vi_viirs_pending)
    # format = "rds" (default): same rationale as vi_modis_grid.
  ),

  # Generate unified STAC Collection for all VI sensors (MODIS + VIIRS)
  tar_target(
    vi_stac,
    generate_modis_vi_stac(
      tif_files                       = vi_modis_grid,
      viirs_tif_files                 = vi_viirs_grid,
      stac_dir                        = "data/stac/vi",
      parent_catalog_path             = "data/stac",
      gh_repo                         = gh_repo_config$repo,
      gh_release_tag_modis_terra      = release_tags$vi_modis_terra,
      gh_release_tag_modis_aqua       = release_tags$vi_modis_aqua,
      gh_release_tag_viirs            = release_tags$vi_viirs_raster,
      gh_stac_release_tag             = release_tags$stac_vi,
      gh_stac_item_release_prefix     = release_tags$stac_vi,
      gh_root_stac_release_tag        = release_tags$stac,
      gh_release_tag_vi_modis_parquet = release_tags$vi_modis_parquet,
      gh_release_tag_vi_viirs_parquet = release_tags$vi_viirs_parquet,
      gh_release_tag_fireage          = release_tags$fireage,
      verbose                         = TRUE
    ),
    format     = "file",
    deployment = "main"
  ),

  # ============================================================================
  # MODIS Burned Area Pipeline (MCD64A1, dynamically branched by month)
  # ============================================================================

  tar_target(
    burn_modis_pending,
    {
      months <- generate_monthly_sequence(
        start_date = burn_start_date,
        end_date = modis_end_date
      )
      filter_pending_months(
        months,
        gh_release_tag = release_tags$burn_modis_raster,
        prefix = "burn_modis_"
      )
    }
  ),

  # Submit one AppEEARS task per missing month (branched)
  tar_target(
    burn_modis_task_ids,
    submit_burn_date_modis_task(
      domain_vector  = domain_boundary.gpkg,
      month_start    = burn_modis_pending$month_start,
      month_end      = burn_modis_pending$month_end,
      out_dir        = "data/target_outputs/burndates/",
      gh_release_tag = release_tags$burn_modis_raster,
      verbose        = TRUE
    ),
    pattern = map(burn_modis_pending),
    error   = "continue"  # rate-limit errors retry on next tar_make()
  ),

  # Download GeoTIFF results from AppEEARS (I/O only)
  tar_target(
    burn_modis_geotiff,
    download_burn_date_modis_geotiff(
      task_id        = burn_modis_task_ids,
      month_start    = burn_modis_pending$month_start,
      month_end      = burn_modis_pending$month_end,
      domain_vector  = domain_boundary.gpkg,
      temp_directory = "data/temp/appeears/burn_dates_modis/",
      gh_release_tag = release_tags$burn_modis_raster,
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
    pattern = map(burn_modis_geotiff, burn_modis_pending)
    # format = "rds" (default): same rationale as vi_modis_grid.
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
    pattern = map(burn_modis_grid, burn_modis_pending)
    # format = "rds" (default): same rationale as vi_modis_grid.
  ),

  # ============================================================================
  # VIIRS Burned Area Pipeline (VNP64A1, dynamically branched by month)
  # Coverage: 2012-01-01 to present
  # ============================================================================

  tar_target(
    burn_viirs_pending,
    {
      months <- generate_monthly_sequence(
        start_date = viirs_start_date,
        end_date = modis_end_date
      )
      filter_pending_months(
        months,
        gh_release_tag = release_tags$burn_viirs_raster,
        prefix = "burn_viirs_"
      )
    }
  ),

  tar_target(
    burn_viirs_task_ids,
    submit_burn_date_viirs_task(
      domain_vector  = domain_boundary.gpkg,
      month_start    = burn_viirs_pending$month_start,
      month_end      = burn_viirs_pending$month_end,
      out_dir        = "data/target_outputs/burndates/",
      gh_release_tag = release_tags$burn_viirs_raster,
      verbose        = TRUE
    ),
    pattern = map(burn_viirs_pending),
    error   = "continue"  # rate-limit errors retry on next tar_make()
  ),

  tar_target(
    burn_viirs_geotiff,
    download_burn_date_viirs_geotiff(
      task_id        = burn_viirs_task_ids,
      month_start    = burn_viirs_pending$month_start,
      month_end      = burn_viirs_pending$month_end,
      domain_vector  = domain_boundary.gpkg,
      temp_directory = "data/temp/appeears/burn_dates_viirs/",
      gh_release_tag = release_tags$burn_viirs_raster,
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
    pattern = map(burn_viirs_geotiff, burn_viirs_pending)
    # format = "rds" (default): same rationale as vi_modis_grid.
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
    pattern = map(burn_viirs_grid, burn_viirs_pending)
    # format = "rds" (default): same rationale as vi_modis_grid.
  ),

  # ============================================================================
  # Derived fire covariates (aggregated; depend on all monthly parquets above)
  # ============================================================================

  # ── Merge MODIS + VIIRS + CapeNature into deduplicated fire event table ──────
  # 6-month per-pixel clustering collapses multi-sensor detections of the same
  # fire. Priority: CapeNature > VIIRS > MODIS.
  tar_target(
    burn_events_merged,
    {
      # Explicit deps ensure all monthly parquets complete before merging
      force(burn_modis_parquet)
      force(burn_viirs_parquet)
      force(capenature_burn_events)          # CapeNature ground-truth events
      merge_burn_dates(
        burn_dir           = "data/target_outputs/burndates/",
        capenature_parquet = capenature_burn_events,
        verbose            = TRUE
      )
    },
    format = "rds"
  ),

  # ── Incremental per-pixel fire state (append-only, idempotent) ───────────────
  # Reads the running state parquet, finds new months in burn_events_merged,
  # and updates the state. No-op when already current.
  tar_target(
    most_recent_burn,
    compute_fire_state(
      burn_events = burn_events_merged,
      state_file  = "data/target_outputs/most_recent_burn_state.parquet",
      verbose     = TRUE
    )
    # format = "rds" (default): state parquet path stored as RDS; CI skips without the file on disk.
  ),

  # ── Fire age at every VI observation date (MODIS + VIIRS) ────────────────────
  # Joins the per-pixel fire state to each VI parquet.  Idempotent: already-
  # written fireage parquets are skipped on subsequent runs.
  tar_target(
    fireage_parquets,
    {
      force(vi_modis_parquet)   # wait for all VI parquets
      force(vi_viirs_parquet)
      compute_fireage_for_vi(
        modis_vi_dir = "data/target_outputs/modis_vi",
        viirs_vi_dir = "data/target_outputs/viirs_vi",
        state_file   = most_recent_burn,
        out_dir      = "data/target_outputs/fireage/",
        verbose      = TRUE
      )
    }
    # format = "rds" (default): fireage parquet paths stored as RDS; CI skips without files on disk.
  ),

  # ── Snapshot raster (latest state_month only) ─────────────────────────────────
  geotargets::tar_terra_rast(
    fireage_current.tif,
    most_recent_burn_to_grid(
      state_file    = most_recent_burn,
      domain_raster = domain.tif,
      verbose       = TRUE
    ),
    datatype = "INT4S"
  ),

  # Unified STAC Collection for burned area (MODIS + VIIRS COG rasters + fireage_current COG).
  # Re-runs whenever any grid or the fireage_current.tif snapshot changes.
  tar_target(
    burn_stac,
    generate_burn_stac(
      modis_tif_files              = burn_modis_grid,
      viirs_tif_files              = burn_viirs_grid,
      recentburn_file              = terra::sources(fireage_current.tif)[[1]],
      stac_dir                     = "data/stac/burn",
      gh_repo                      = gh_repo_config$repo,
      gh_release_tag_modis         = release_tags$burn_modis_raster,
      gh_release_tag_viirs         = release_tags$burn_viirs_raster,
      gh_release_tag_derived       = release_tags$fireage,
      gh_release_tag_modis_parquet = release_tags$burn_modis_parquet,
      gh_release_tag_viirs_parquet = release_tags$burn_viirs_parquet,
      gh_stac_release_tag          = release_tags$stac_burn,
      gh_root_stac_release_tag     = release_tags$stac,
      verbose                      = TRUE
    ),
    format     = "file",
    deployment = "main"
  ),

  # Generate STAC Collection for static environmental layers (elevation.tif, climate, soil, etc.)
  tar_target(
    static_stac,
    generate_static_layers_stac(
      domain_file               = terra::sources(domain.tif)[[1]],
      domain_parquet            = domain_geoparquet,
      vegmap_file               = vegmap_raster_path,
      elevation                 = terra::sources(elevation.tif)[[1]],
      climate_files             = climate_chelsa,
      clouds                    = terra::sources(clouds.tif)[[1]],
      soil                      = terra::sources(soils.tif)[[1]],
      topo                      = terra::sources(geodiversity.tif)[[1]],
      stac_dir                  = "data/stac/static",
      gh_repo                   = gh_repo_config$repo,
      gh_release_tag            = release_tags$static,
      gh_stac_release_tag       = release_tags$stac_static,
      gh_root_stac_release_tag  = release_tags$stac,
      static_covariates_parquet = static_geoparquet,
      verbose                   = TRUE
    ),
    format     = "file",
    deployment = "main"
  ),

  ##################### GitHub Release Uploads #########################
  # deployment = "main" means: run in the main R process, not a distributed
  # crew worker. It is NOT a git-branch gate. To restrict uploads to the main
  # git branch, add: if (Sys.getenv("GITHUB_REF") != "refs/heads/main") return(invisible(NULL))

  # Upload all static NetCDF files (domain, elevation.tif, climate, clouds, soil, topography)
  tar_target(
    upload_static,
    upload_to_github_release(
      files = c(
        terra::sources(domain.tif)[[1]],
        "data/target_outputs/domain.parquet",
        "data/target_outputs/static_covariates.parquet",
        vegmap_raster_path,
        terra::sources(elevation.tif)[[1]],
        climate_chelsa,
        terra::sources(clouds.tif)[[1]],
        terra::sources(soils.tif)[[1]],
        terra::sources(geodiversity.tif)[[1]]
      ),
      repo         = gh_repo_config$repo,
      release_tag  = release_tags$static,
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
      release_tag  = release_tags$vi_modis_parquet,
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
      release_tag  = release_tags$burn_modis_parquet,
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
      release_tag  = release_tags$burn_viirs_parquet,
      release_name = "Dynamic VIIRS Burned Area (VNP64A1)",
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Separate releases keep each MODIS sensor below GitHub's 1,000-asset limit.
  tar_target(
    upload_vi_modis_terra_grid,
    upload_to_github_release(
      files        = vi_modis_grid[
        grepl("vi_modis_terra_.*\\.tif$", vi_modis_grid)
      ],
      repo         = gh_repo_config$repo,
      release_tag  = release_tags$vi_modis_terra,
      release_name = "Dynamic MODIS Terra VI Rasters (16-day composites)",
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  tar_target(
    upload_vi_modis_aqua_grid,
    upload_to_github_release(
      files        = vi_modis_grid[
        grepl("vi_modis_aqua_.*\\.tif$", vi_modis_grid)
      ],
      repo         = gh_repo_config$repo,
      release_tag  = release_tags$vi_modis_aqua,
      release_name = "Dynamic MODIS Aqua VI Rasters (16-day composites)",
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
      release_tag  = release_tags$vi_viirs_raster,
      release_name = "Dynamic VIIRS VI Rasters (S-NPP + NOAA-20, 16-day composites)",
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Upload MODIS burned area raster grids
  # overwrite = TRUE: grid COGs are regenerated when the burn pipeline changes
  # (e.g. domain update); stale same-named release assets must be replaced.
  tar_target(
    upload_burn_modis_grid,
    upload_to_github_release(
      files        = burn_modis_grid[!grepl("\\.skip$", burn_modis_grid)],
      repo         = gh_repo_config$repo,
      release_tag  = release_tags$burn_modis_raster,
      release_name = "Dynamic MODIS Burned Area Rasters (MCD64A1)",
      overwrite    = TRUE,
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Upload VIIRS burned area raster grids
  # overwrite = TRUE: same rationale as burn_modis_grid above.
  tar_target(
    upload_burn_viirs_grid,
    upload_to_github_release(
      files        = burn_viirs_grid[!grepl("\\.skip$", burn_viirs_grid)],
      repo         = gh_repo_config$repo,
      release_tag  = release_tags$burn_viirs_raster,
      release_name = "Dynamic VIIRS Burned Area Rasters (VNP64A1)",
      overwrite    = TRUE,
      verbose      = TRUE
    ),
    deployment = "main"
  ),

  # Upload fireage COG snapshot + fireage parquets (one per VI composite, MODIS + VIIRS)
  # overwrite = TRUE: fireage_current.tif content changes every run as new months are added.
  tar_target(
    upload_fireage,
    upload_to_github_release(
      files        = c(
        terra::sources(fireage_current.tif)[[1]],
        fireage_parquets[!grepl("\\.skip$", fireage_parquets)]
      ),
      repo         = gh_repo_config$repo,
      release_tag  = release_tags$fireage,
      release_name = "Fire Age (snapshot raster + per-VI-date parquets)",
      overwrite    = TRUE,
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
        dataset_release_tags = c(
          vi = release_tags$stac_vi,
          burn = release_tags$stac_burn,
          static = release_tags$stac_static
        ),
        root_release_tag = release_tags$stac,
        gh_repo = gh_repo_config$repo,
        verbose = TRUE
      )
    },
    format     = "file",
    deployment = "main"
  ),

  # Each collection is published separately to stay below GitHub's 1,000-asset
  # limit. The root catalog contains absolute links to these releases.
  tar_target(
    upload_stac_vi,
    {
      vi_collection_file <- vi_stac[
        basename(vi_stac) == "vi_collection.json"
      ]
      vi_item_files <- vi_stac[
        grepl("^vi_[0-9]{8}\\.json$", basename(vi_stac))
      ]
      vi_item_years <- substr(basename(vi_item_files), 4L, 7L)
      vi_item_decades <- paste0(substr(vi_item_years, 1L, 3L), "0s")

      upload_to_github_release(
        files = vi_collection_file,
        repo = gh_repo_config$repo,
        release_tag = release_tags$stac_vi,
        release_name = "STAC - Vegetation Indices",
        verbose = TRUE,
        overwrite = TRUE
      )

      purrr::iwalk(
        split(vi_item_files, vi_item_decades),
        function(files, decade) {
          upload_to_github_release(
            files = files,
            repo = gh_repo_config$repo,
            release_tag = paste0(release_tags$stac_vi, "-", decade),
            release_name = paste("STAC - Vegetation Indices", decade),
            verbose = TRUE,
            overwrite = TRUE
          )
        }
      )
    },
    deployment = "main"
  ),

  tar_target(
    upload_stac_burn,
    upload_to_github_release(
      files = burn_stac,
      repo = gh_repo_config$repo,
      release_tag = release_tags$stac_burn,
      release_name = "STAC - Burned Area",
      verbose = TRUE,
      overwrite = TRUE
    ),
    deployment = "main"
  ),

  tar_target(
    upload_stac_static,
    upload_to_github_release(
      files = static_stac,
      repo = gh_repo_config$repo,
      release_tag = release_tags$stac_static,
      release_name = "STAC - Static Environmental Layers",
      verbose = TRUE,
      overwrite = TRUE
    ),
    deployment = "main"
  ),

  tar_target(
    upload_stac_catalog,
    {
      force(upload_stac_vi)
      force(upload_stac_burn)
      force(upload_stac_static)
      upload_to_github_release(
        files = emma_stac_catalog,
        repo = gh_repo_config$repo,
        release_tag = release_tags$stac,
        release_name = "STAC Catalog - Current",
        verbose = TRUE,
        overwrite = TRUE
      )
    },
    deployment = "main"
  ),

  # Walk the local STAC catalog tree and HEAD-check every asset HREF.
  # Issues a warning (does NOT fail) when broken links are found; writes a
  # machine-readable JSON report to data/stac/validation_report.json.
  tar_target(
    validate_stac,
    validate_stac_links(
      catalog_json = "data/stac/catalog.json",
      report_file  = "data/stac/validation_report.json",
      verbose      = TRUE
    ),
    format     = "file",
    deployment = "main"
  ),

  # ============================================================================
  # README Generation (Quarto Dashboard)
  # ============================================================================
  # Renders README.qmd to README.md with comprehensive data summary dashboard.
  # tar_load() calls inside the .qmd ensure this runs after all upstream targets.
  tarchetypes::tar_quarto(
    readme,
    path = "README.qmd",
    quiet = FALSE,
    deployment = "main"
  ),

  # ============================================================================
  # Upload README figure PNGs to GitHub release (readme-assets)
  # ============================================================================
  # Runs after the readme target renders all figures to data/target_outputs/readme_img/.
  # Uploads PNGs to the "readme-assets" release so README.md can reference them
  # via stable URLs without committing binary files to the repository.
  tar_target(
    upload_readme_assets,
    {
      force(readme)  # ensure readme renders (and generates PNGs) before uploading
      png_files <- list.files(
        "data/target_outputs/readme_img",
        pattern = "\\.png$",
        full.names = TRUE
      )
      if (length(png_files) > 0) {
        upload_to_github_release(
          files        = png_files,
          repo         = gh_repo_config$repo,
          release_tag  = release_tags$readme_assets,
          release_name = "README Figure Assets",
          overwrite    = TRUE,
          verbose      = TRUE
        )
      } else {
        message("No PNG files found in readme_img dir; skipping upload.")
        character(0)
      }
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
    repo      = gh_repo_config$repo,
    tag       = "targets-cache",
    cache_dir = "_targets/user/cache",
    verbose   = TRUE
  )
}

# NOTE: _targets.R must return the pipeline list as its final expression.
# The if(FALSE) block above must stay BEFORE this closing ).
)
