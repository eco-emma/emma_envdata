# ============================================================================
# EMMA Environmental Data Pipeline
# ============================================================================
# This pipeline assembles environmental datasets for the EMMA project using
# targets for workflow orchestration. 

message("Starting tar_make()")

devtools::load_all() # load all functions in R
description_packages <- load_description_packages(verbose=TRUE)  # Load all packages from DESCRIPTION and get list

# check what system we are on
  sys_info <- Sys.info(); message(paste("System info:",paste(names(sys_info), sys_info, sep="=", collapse = "; ")))
  # if nodename includes "ccr.buffalo.edu", set working directory to /gscratch/scrubbed/...
  if (grepl("ccr.buffalo.edu", sys_info[["nodename"]])) {
    setwd("~/project/projects/emma/emma_envdata")
    message(paste("Set working directory to:", getwd()))  
  }

#If running this locally, make sure to set up github credentials using gitcreds::gitcreds_set()

  options(tidyverse.quiet = TRUE)

  # Ensure output directories exist early (before terra options)
  dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
  dir.create("data/temp", recursive = TRUE, showWarnings = FALSE)
  dir.create("data/temp/terra", recursive = TRUE, showWarnings = FALSE)
  dir.create("data/releases", recursive = TRUE, showWarnings = FALSE)
  dir.create("data/target_outputs", recursive = TRUE, showWarnings = FALSE)

  # GitHub release repository configuration - releases are used to store target objects and publish final data
  gh_repo_config <- list(
    repo = "AdamWilsonLab/emma_envdata",
    tag = "objects_current",
    cache_dir = "data/target_outputs/.tar_cache" #this is local cache for speed
  )

  # Store config as environment variables for upload function to use
  Sys.setenv(
    TAR_GH_RELEASE_REPO = gh_repo_config$repo,
    TAR_GH_RELEASE_TAG = gh_repo_config$tag,
#    TAR_GH_RELEASE_FORMAT = gh_repo_config$format,
    TAR_GH_RELEASE_CACHE_DIR = gh_repo_config$cache_dir
  )

  tar_option_set(
    memory="transient", 
    garbage_collection = TRUE, #run gc() after each target to free memory
    packages = description_packages,  # Use all packages from DESCRIPTION file
    repository = "local",  # Store locally; manual upload after tar_make() completes
    cue = tar_cue(mode = "thorough")  # Recompute if any inputs change
  )

  terraOptions(tempdir = "data/temp/terra", memfrac = 0.6)

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

  # Set MODIS date range as variables or targets (customize as needed)
  modis_start_date <- "2000-02-18"  # or tar_target(...)
  modis_start_date <- "2026-01-01"  # or tar_target(...)
  modis_end_date <- as.character(Sys.Date())



list(
  tar_target(
    vegmap_shp,
    download_vegmap_release(
      repo = "AdamWilsonLab/emma_envdata",
      tag = "vegmap2024",
      file = "NVM2024final_Shapefile.zip",
      local_dir = "data/manual_download/NVM2024",
      shapefile_name = "NVM2024Final_IEM5_12_07012025.shp"
    ),
    format = "file"
  ),

  tar_target(
    remnants_shp,
    "data/manual_download/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp",
    format="file"
  ),

  tar_target(
    capenature_fires_shp,
    "data/manual_download/All_fires_23_24_gw/All_fires_23_24_gw.shp",
    format="file"
  ),

# Get country boundary
  tar_target( 
    country.parquet,
    get_country(),
    format = "file"
  ),

# Create domain file based on country boundary and vegmap
  tar_target( 
    domain_boundary.parquet,
    domain_define(vegmap_shp = vegmap_shp, country = country.parquet),
    format = "file"
  ),

# Stable bounding box for downloads (50km buffer around domain)
  tar_target(   
    domain_bbox.parquet,
    make_domain_bbox(domain_boundary.parquet, buffer_m = 50000, out_file = "data/target_outputs/domain_bbox.parquet"),
    format = "file",
    cue = tar_cue(mode = "never")   # Never re-downloads unless manually invalidated, even if analysis domain changes
  ),

# Domain raster with pixel IDs, remnants, and distance to remnants. This defines the model grid that is used for everything!
  tar_target(   
    domain_nc,
    domain_rasterize(
      domain = sfarrow::st_read_parquet(domain_boundary.parquet), 
      remnants_shp = remnants_shp,
      out_file = "data/target_outputs/domain.nc"
    ),
    format = "file",
     cue = tar_cue(mode = "never") # Never rerun unless manually invalidated because this will trigger complete reprocessing of rs data
     # tar_invalidate(domain_nc) # run this to force recompute, which will trigger redownloading all RS data from appeears

  ),

  # Convert domain raster to geoparquet for spatial reference with coordinates and pid
  tar_target(
    domain_geoparquet,
    domain_to_geoparquet(
      domain_raster_file = domain_nc,
      out_file = "data/target_outputs/domain.parquet",
      verbose = TRUE
    ),
    format = "file"
  ),

# Rasterize the vegetation map
   tar_target( 
    vegmap_nc,
    data_vegmap(domain_raster = domain_nc,
                vegmap_shp = vegmap_shp,
                out_file = "data/target_outputs/vegmap.nc"),
    format = "file"),


      # tar_target(
      #   protected_area_distance_release,
      #   process_release_protected_area_distance(template_release,
      #                                           out_file = "protected_area_distance.tif",
      #                                           temp_directory = "data/temp/protected_area",
      #                                           out_tag = "processed_static")
      # ),

#  tar_target(
#      alos_release,
#      get_release_alos(temp_directory = "data/temp/raw_data/alos/",
#                       tag = "raw_static",
#                       domain = domain,
#                       json_token)
#      )
#,

# Climate CHELSA bioclimatic variables (BIO1-BIO19)
    tar_target( 
      climate_chelsa,
      get_climate_chelsa(
        domain = sfarrow::st_read_parquet(domain_boundary.parquet),
        cleanup = cleanup_mode,
        verbose = TRUE),
      format = "file"
    ),

  # tar_terra_rast(
  #   clouds_wilson_release,
  #   get_release_clouds_wilson(temp_directory = "data/temp/raw_data/clouds_wilson/",
  #                             tag = "raw_static",
  #                             domain,
  #                             sleep_time = 180)
  #   ),

  ##################### AppEEARS Static Data Processing #########################
  # Sequential targets for AppEEARS elevation: submit task, then poll for results
  # Allows independent timeouts and retries for long-running API calls
  tar_target(
    elevation_task_id,
    submit_elevation_task(
      domain_vector = sfarrow::st_read_parquet(domain_boundary.parquet),
      verbose = TRUE
    )
  ),

  tar_target(
    elevation,
    download_elevation_results(
      task_id = elevation_task_id,
      domain_vector = sfarrow::st_read_parquet(domain_boundary.parquet),
      domain_raster = domain_nc,
      out_file = "data/target_outputs/elevation_nasadem.nc",
      temp_directory = "data/temp/raw_data/elevation_nasadem/",
      verbose = TRUE
    ),
    format = "file"
  ),

  # Generate human-readable manifest of all targets for release documentation
#   tar_target(
#     release_manifest,
#     generate_release_manifest(),
#     format = "file"
#   )
# #,

  #Temporarily commented out, seems to be an issue with URL for landcover data at present
  # tar_target(
  #   landcover_za_release,
  #   get_release_landcover_za(temp_directory = "data/temp/raw_data/landcover_za/",
  #                            tag = "raw_static",
  #                            domain = domain)
  #   ),
  #
  # tar_target(
  #   precipitation_chelsa_release,
  #   get_release_precipitation_chelsa(temp_directory = "data/temp/raw_data/precipitation_chelsa/",
  #                                    tag = "raw_static",
  #                                    domain = domain)
  #   )#,

#   ## commented out soil_gcfr_release at present due to API/rdryad issues.
#   ## Emailed dryad folks on 2024/01/04, it seems the API update broke RDryad
#   ## and RDryad updates are waiting for funding and transition from RDryad to
#   ## the "deposits" R package
#
#   # tar_target(
#   #   soil_gcfr_release,
#   #   get_release_soil_gcfr(temp_directory = "data/temp/raw_data/soil_gcfr/",
#   #                         tag = "raw_static",
#   #                         domain)
#   # ),
#

##################### AppEEARS Dynamic Data Processing #########################

#       tar_age(
#         fire_modis_release,
#         get_release_fire_modis_appeears(temp_directory = "data/temp/raw_data/fire_modis/",
#                                tag = "raw_fire_modis_nc",
#                                domain = domain,
#                                max_layers = 5,
#                                sleep_time = 5,
#                                verbose = TRUE),
#         age = as.difftime(7, units = "days")
#         #age = as.difftime(1, units = "days")
#         #age = as.difftime(0, units = "hours"),
#  cue = tar_cue(mode = if (run_mode == "update") "always" else "thorough")
#       ),

  # ============================================================================
  # MODIS VI Download Pipeline (Dynamically Branched)
  # ============================================================================

  # Identify which monthly periods need to be downloaded
  tar_target(
    modis_vi_to_download,
    {
      output_dir <- "data/target_outputs/modis_vi"
      
      # Check which monthly periods have already been downloaded
      # identify_missing_vi() checks for existing NetCDF files
      missing <- identify_missing_vi(
        output_dir = output_dir,
        dataset = "modis_vi",
        start_date = modis_start_date,
        end_date = modis_end_date
      )
      
      # Always include the current month to ensure up-to-date data
      today <- Sys.Date()
      current_month_start <- as.Date(paste0(format(today, "%Y-%m"), "-01"))
      current_month_end <- as.Date(paste0(format(today + 31, "%Y-%m"), "-01")) - 1
      current_month_str <- format(current_month_start, "%Y-%m")
      
      # Check if current month is already in missing
      current_in_missing <- any(missing$date_str == current_month_str)
      
      if (!current_in_missing) {
        current_row <- data.frame(
          month_start = current_month_start,
          month_end = current_month_end,
          date_str = current_month_str
        )
        missing <- rbind(missing, current_row)
      }
      
      if (nrow(missing) == 0) {
        message("All monthly periods from ", modis_start_date, " to ", modis_end_date, " already downloaded")
        # Return empty data frame with correct structure
        data.frame(
          month_start = as.Date(character(0)),
          month_end = as.Date(character(0)),
          date_str = character(0)
        )
      } else {
        message("Found ", nrow(missing), " missing monthly periods to download (current month always included)")
        missing
      }
    }
  ),

  # Dynamically submit monthly AppEEARS tasks
  tar_target(
    modis_vi_task_ids,
    {
      # Within this branch, modis_vi_to_download is auto-sliced to one row
      submit_modis_vi(
        domain_vector = sfarrow::st_read_parquet(domain_boundary.parquet),
        month_start = modis_vi_to_download$month_start,
        month_end = modis_vi_to_download$month_end
      )
    },
    pattern = map(modis_vi_to_download),
  ),

  # Download NetCDF files from AppEEARS (I/O only)
  tar_target(
    modis_vi_netcdf,
    {
      download_modis_vi_netcdf(
        task_id = modis_vi_task_ids,
        month_start = modis_vi_to_download$month_start,
        temp_directory = "data/temp/raw_data/modis_vi_netcdf/",
        cleanup = cleanup_mode,
        verbose = TRUE
      )
    },
    pattern = map(modis_vi_task_ids, modis_vi_to_download),
    format = "file",
  ),

  # Process NetCDF to parquet format
  tar_target(
    modis_vi_parquet,
    {
      netcdf_to_parquet(
        netcdf_directory = modis_vi_netcdf,
        domain_raster = domain_nc,
        month_start = modis_vi_to_download$month_start,
        out_dir = "data/target_outputs/modis_vi/",
        cleanup = cleanup_mode,
        verbose = TRUE
      )
    },
    pattern = map(modis_vi_netcdf, modis_vi_to_download),
    format = "file"
  ),

  # Generate STAC Collection for MODIS VI dataset
  tar_target(
    modis_vi_stac,
    generate_modis_vi_stac(
      parquet_files = modis_vi_parquet,  # Automatically aggregated from branched target
      parquet_dir = "data/target_outputs/modis_vi",
      stac_dir = "data/stac/modis_vi",
      parent_catalog_path = "data/stac",
      gh_repo = "AdamWilsonLab/emma_envdata",
      gh_release_tag = "data_modis_vi_current",
      verbose = TRUE
    ),
    format = "file"
  ),

  # Generate parent STAC Catalog linking all datasets (MODIS VI, VIIRS VI, burned area, age, etc.)
  tar_target(
    emma_stac_catalog,
    {
      generate_emma_stac_catalog(
        stac_base_dir = "data/stac",
        dataset_collections = list(
          modis_vi = "data/stac/modis_vi"
          # Additional datasets will be added here as they become available:
          # viirs_vi = "data/stac/viirs_vi",
          # burned_area = "data/stac/burned_area",
          # age = "data/stac/age"
        ),
        gh_repo = "AdamWilsonLab/emma_envdata",
        verbose = TRUE
      )
    },
    format = "file",
    deployment = "main"
  ),


 # revise modis for viirs



# # # # Processing via release

#     tar_target(
#       fire_doy_to_unix_date_release,
#       process_release_fire_doy_to_unix_date(input_tag = "clean_fire_modis",
#                                             output_tag = "processed_fire_dates",
#                                             temp_directory = "data/temp/processed_data/fire_dates/",
#                                             sleep_time = 20,
#                                             template_release = template_release,
#                                             ... = correct_fire_release_proj_and_extent)
#       ),

#     tar_target(
#       burn_date_to_last_burned_date_release,
#       process_release_burn_date_to_last_burned_date(input_tag = "processed_fire_dates",
#                                                     output_tag = "processed_most_recent_burn_dates",
#                                                     temp_directory_input = "data/temp/processed_data/fire_dates/",
#                                                     temp_directory_output = "data/temp/processed_data/most_recent_burn_dates/",
#                                                     sleep_time = 180,
#                                                     sanbi_sf = sanbi_fires_shp,
#                                                     expiration_date = NULL,
#                                                     ... = fire_doy_to_unix_date_release)
#     ),


#     tar_target(
#       ndvi_relative_days_since_fire_release,
#       process_release_ndvi_relative_days_since_fire(temp_input_ndvi_date_folder = "data/temp/raw_data/ndvi_dates_modis/",
#                                                     temp_input_fire_date_folder = "data/temp/processed_data/most_recent_burn_dates/",
#                                                     temp_fire_output_folder = "data/temp/processed_data/ndvi_relative_time_since_fire/",
#                                                     input_fire_dates_tag = "processed_most_recent_burn_dates",
#                                                     input_modis_dates_tag = "clean_ndvi_dates_modis",
#                                                     output_tag = "processed_ndvi_relative_days_since_fire",
#                                                     sleep_time = 60,
#                                                     ... = burn_date_to_last_burned_date_release,
#                                                     ... = correct_ndvi_dates_release_proj_and_extent)
#       ),

#       tar_target(
#         template_release,
#         get_release_template_raster(input_tag = "clean_ndvi_modis",
#                             output_tag = "raw_static",
#                             temp_directory = "data/temp/template",
#                             ... = correct_ndvi_release_proj_and_extent)
#       ),



#       tar_target(
#         projected_alos_release,
#         process_release_alos(input_tag = "raw_static",
#                              output_tag = "processed_static",
#                              temp_directory = "data/temp/raw_data/alos/",
#                              template_release = template_release,
#                              sleep_time = 60,
#                              ... = alos_release)
#       ),

#       tar_target(
#         projected_climate_chelsa_release,
#         process_release_climate_chelsa(input_tag = "raw_static",
#                                        output_tag = "processed_static",
#                                        temp_directory = "data/temp/raw_data/climate_chelsa/",
#                                        template_release = template_release,
#                                        ... = climate_chelsa_release)
#         ),

#       tar_target(
#         projected_clouds_wilson_release,
#         process_release_clouds_wilson(input_tag = "raw_static",
#                                       output_tag = "processed_static",
#                                       temp_directory = "data/temp/raw_data/clouds_wilson/",
#                                       template_release = template_release,
#                                       sleep_time = 180,
#                                       ... = clouds_wilson_release)
#       ), # 3-2

#       tar_target(
#         projected_elevation_nasadem_release,
#         process_release_elevation_nasadem(input_tag = "raw_static",
#                                           output_tag = "processed_static",
#                                           temp_directory = "data/temp/raw_data/elevation_nasadem/",
#                                           template_release = template_release,
#                                           sleep_time = 0,
#                                           ... = elevation_nasadem_release)
#       ),

#       tar_target(
#         projected_landcover_za_release,
#         process_release_landcover_za(input_tag = "raw_static",
#                                      output_tag = "processed_static",
#                                      temp_directory = "data/temp/raw_data/landcover_za/",
#                                      template_release,
#                                      sleep_time = 60,
#                                      ... = landcover_za_release)
#       )
#       ,

#       tar_target(
#         projected_precipitation_chelsa_release,
#         process_release_precipitation_chelsa(input_tag = "raw_static",
#                                              output_tag = "processed_static",
#                                              temp_directory = "data/temp/raw_data/precipitation_chelsa/",
#                                              template_release,
#                                              sleep_time = 60,
#                                              ... = precipitation_chelsa_release)

#       ),

#       tar_target(
#         projected_soil_gcfr_release,
#         process_release_soil_gcfr(input_tag = "raw_static",
#                                   output_tag = "processed_static",
#                                   temp_directory = "data/temp/raw_data/soil_gcfr/",
#                                   template_release,
#                                   sleep_time = 60,
#                                   ... = soil_gcfr_release)

#       ),

#       tar_target(
#         vegmap_modis_proj,
#         process_release_biome_raster(template_release = template_release,
#                                      vegmap_shp = vegmap_shp,
#                                      domain = domain,
#                                      temp_directory = "data/temp/raw_data/vegmap_raster/",
#                                      sleep_time = 10)

#       ),




# # # # # # Prep model data

#     tar_target(
#       stable_data_release,

#     tar_target(
#       fire_dates_to_parquet_release,
#       process_release_dynamic_data_to_parquet(temp_directory = "data/temp/processed_data/ndvi_relative_time_since_fire/",
#                                       input_tag = "processed_ndvi_relative_days_since_fire",
#                                       output_tag = "current",
#                                       variable_name = "time_since_fire",
#                                       sleep_time = 30,
#                                       ... = ndvi_relative_days_since_fire_release)
#     ),

#     tar_target(
#       most_recent_fire_dates_to_parquet_release,
#       process_release_dynamic_data_to_parquet(temp_directory = "data/temp/processed_data/most_recent_burn_dates/",
#                                       input_tag = "processed_most_recent_burn_dates",
#                                       output_tag = "current",
#                                       variable_name = "most_recent_burn_dates",
#                                       sleep_time = 30,
#                                       ... = burn_date_to_last_burned_date_release)
#     )

  ##################### GitHub Release Uploads #########################
  
  # Upload static data files (domain, elevation, climate, etc.)
  # tar_target(
  #   upload_static_data,
  #   {
  #     upload_to_github_release(
  #       files = c(
  #         domain_boundary.parquet,
  #         elevation,
  #         climate_chelsa,
  #         vegmap_nc
  #       ),
  #       repo = "AdamWilsonLab/emma_envdata",
  #       release_tag = "static_current",
  #       release_name = "Static Data - Current",
  #       verbose = TRUE
  #     )
  #   },
  #   deployment = "main"
  # ),

  # Upload dynamic MODIS VI data files
  tar_target(
    upload_modis_vi_data,
    {
     
      # Get all parquet files from disk
      parquet_files <- list.files(
        "data/target_outputs/modis_vi",
        pattern = "\\.parquet$",
        full.names = TRUE
      )
      
      upload_to_github_release(
        files = parquet_files,
        repo = gh_repo_config$repo,
        release_tag = "dynamic_modis_vi",
        release_name = "Dynamic MODIS Vegetation Index",
        verbose = TRUE,
        modis_vi_parquet #include to force dependency on the parquet files being created before upload     
      )
    },
    deployment = "main"
  ),

  # Upload STAC metadata catalog
  tar_target(
    upload_stac_catalog,
    {
      # Ensure STAC targets are complete before proceeding
      stac_parent <- emma_stac_catalog
      stac_modis_items <- modis_vi_stac
      
      stac_files <- c(
        file.path("data/stac", "catalog.json"),
        list.files("data/stac/modis_vi", pattern = "\\.json$", full.names = TRUE)
      )
      
      upload_to_github_release(
        files = stac_files,
        repo = gh_repo_config$repo,
        release_tag = "stac",
        release_name = "STAC Catalog - Current",
        verbose = TRUE
        )
    },
    deployment = "main"
  )

)

