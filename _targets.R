message("Starting tar_make()")
print("Starting tar_make() - print")

library(targets)
suppressMessages(library(qs))
library(tarchetypes)
library(geotargets)
library(visNetwork)
library(rdryad)
library(appeears)#,lib.loc=Sys.getenv("R_LIBS_USER"))
library(keyring)#,lib.loc=Sys.getenv("R_LIBS_USER"))
library(filelock)#,lib.loc=Sys.getenv("R_LIBS_USER"))
library(arrow)
library(sfarrow)

#if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes") 
#remotes::install_deps(dependencies = TRUE)

#library(future) #not sure why this is needed, but we get an error in some of the files without it


# check what system we are on
  sys_info <- Sys.info()
  message(paste("System info:",paste(names(sys_info), sys_info, sep="=", collapse = "; ")))
  # if nodename includes "ccr.buffalo.edu", set working directory to /gscratch/scrubbed/...
  if (grepl("ccr.buffalo.edu", sys_info[["nodename"]])) {
    setwd("~/project/projects/emma/emma_envdata")
    message(paste("Set working directory to:", getwd()))  
  }

# Determine run mode: "prime" (full processing on server) or "update" (incremental on GitHub Actions)
  run_mode <- if (tolower(Sys.getenv("GITHUB_ACTIONS")) == "true") {
    "update" # Run incremental updates on GitHub Actions
  } else {
    "prime"  # Default to prime meaning all targets are run
  }
  message(paste("Run mode:", run_mode))

#If running this locally, make sure to set up github credentials using gitcreds::gitcreds_set()


# source all files in R folder
  lapply(list.files("R",pattern="[.]R",full.names = T), function(x) {source(x)})
  # message(paste("Objects:",ls(),collapse = "\n")) # To make sure all packages are loaded


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
    format = "qs",
    cache_dir = "data/target_outputs/.tar_cache" #this is local cache for speed
  )

  # Store config as environment variables for upload function to use
  Sys.setenv(
    TAR_GH_RELEASE_REPO = gh_repo_config$repo,
    TAR_GH_RELEASE_TAG = gh_repo_config$tag,
    TAR_GH_RELEASE_FORMAT = gh_repo_config$format,
    TAR_GH_RELEASE_CACHE_DIR = gh_repo_config$cache_dir
  )

  # In "update" mode (GitHub Actions), pre-download targets from GitHub releases
  if (run_mode == "update") {
    message("[targets] Update mode: pre-downloading targets from GitHub releases")
    tryCatch({
      tar_download_github_release(which_targets = NULL, verbose = TRUE)
    }, error = function(e) {
      message("[targets] Warning: Could not pre-download targets: ", conditionMessage(e))
    })
  }

  tar_option_set(
    packages = c("tidyverse", "stringr","knitr","sf","stars","units","geotargets",
                 "appeears", "terra", "smoothr", "janitor", "sfarrow", "jsonlite",
                 "piggyback", "qs", "arrow"),
    repository = "local",  # Store locally; manual upload after tar_make() completes
    cue = tar_cue(mode = if (run_mode == "prime") "thorough" else "never") # Prime: recompute if needed; Update: never recompute unless manually invalidated
  )

  terraOptions(tempdir = "data/temp/terra", memfrac = 0.6)

## Authenticate with AppEEARS
# source("R/appeears_auth.R")

# Ensure things are clean
#  unlink(file.path("data/temp/"), recursive = TRUE, force = TRUE)
#  unlink(file.path("data/raw_data/", recursive = TRUE, force = TRUE))
#  message(paste("Objects:",ls(),collapse = "\n"))


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
    format = "file",
    repository = "local" #because it's just downloaded from release - don't need to upload again.
  ),

  tar_target(
    remnants_shp,
    "data/manual_download/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp",
    format="file",
    repository = "local"
  ),

  tar_target(
    capenature_fires_shp,
    "data/manual_download/All_fires_23_24_gw/All_fires_23_24_gw.shp",
    format="file",
    repository = "local"
  ),


  tar_target(
    country.parquet,
    get_country(),
    format = "file"
  ),

  tar_target(
    domain.parquet,
    domain_define(vegmap = vegmap_shp, country = country.parquet),
    format = "file"
  ),

  # Stable bounding box for downloads (50km buffer around domain)
  # Never re-downloads unless manually invalidated, even if analysis domain changes
  tar_target(
    domain_bbox.parquet,
    make_domain_bbox(domain.parquet, buffer_m = 50000, out_file = "data/target_outputs/domain_bbox.parquet"),
    format = "file",
    cue = tar_cue(mode = "never")
  ),

  # Domain raster with pixel IDs, remnants, and distance to remnants
  tar_target(
    domain_nc,
    domain_rasterize(
      domain = sfarrow::st_read_parquet(domain.parquet), 
      remnants_shp = remnants_shp,
      out_file = "data/target_outputs/domain.nc"
    ),
    format = "file"
     # tar_invalidate(domain_nc) # run this to force recompute, which will trigger redownloading all RS data from appeears

  ),

  # Vegetation map raster
  tar_target(
    vegmap_nc,
    data_vegmap(domain_raster = domain_nc,
                vegmap_shp = vegmap_shp,
                out_file = "data/target_outputs/vegmap.nc"),
    format = "file"),
# # # # Infrequent updates via releases


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

    tar_target(
      climate_chelsa,
      get_climate_chelsa(
        domain = sfarrow::st_read_parquet(domain.parquet),
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

  # Sequential targets for AppEEARS elevation: submit task, then poll for results
  # Allows independent timeouts and retries for long-running API calls
  tar_target(
    elevation_task_id,
    submit_elevation_task(
      domain_vector = sfarrow::st_read_parquet(domain.parquet),
      verbose = TRUE
    )
  ),

  tar_target(
    elevation,
    download_elevation_results(
      task_id = elevation_task_id,
      domain_vector = sfarrow::st_read_parquet(domain.parquet),
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
# # # # # Frequent updates via releases

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

  # Sequential targets for AppEEARS MODIS NDVI/EVI: submit task, then poll for results
  # Allows independent timeouts and retries for long-running API calls
  tar_target(
    modis_vi_task_id,
    submit_modis_vi_task(
      domain_vector = sfarrow::st_read_parquet(domain.parquet),
      mode = run_mode
    )
  ),

  tar_target(
    modis_vi,
    download_modis_vi_results(
      task_id = modis_vi_task_id,
      domain_vector = sfarrow::st_read_parquet(domain.parquet),
      domain_raster = domain_nc,
      mode = run_mode
    ),
    format = "file"
  )

#     tar_age(
#       ndvi_viirs_release,
#       get_release_ndvi_viirs_appeears(temp_directory = "data/temp/raw_data/ndvi_viirs/",
#                                        tag = "raw_ndvi_viirs_nc",
#                                        domain,
#                                        max_layers = 3,
#                                        sleep_time = 1),
#       age = as.difftime(7, units = "days")
#       #age = as.difftime(1, units = "days")
#       #age = as.difftime(0, units = "hours")
#     ),

# # # # # # # Fixing projection via releases


#     tar_target(
#         correct_fire_release_proj_and_extent,
#         process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/fire_modis/",
#                                                         input_tag = "raw_fire_modis",
#                                                         output_tag = "clean_fire_modis",
#                                                         max_layers = NULL,
#                                                         sleep_time = 30,
#                                                         verbose = TRUE,
#                                                         ... = fire_modis_release)
#         ),

#     tar_target(
#       correct_ndvi_release_proj_and_extent,
#       process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/ndvi_modis/",
#                                                       input_tag = "raw_ndvi_modis",
#                                                       output_tag = "clean_ndvi_modis",
#                                                       max_layers = NULL,
#                                                       sleep_time = 30,
#                                                       verbose = TRUE,
#                                                       ... = ndvi_modis_release)
#       ),

#   tar_target(
#     correct_ndvi_dates_release_proj_and_extent,
#     process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/ndvi_dates_modis/",
#                                                     input_tag = "raw_ndvi_dates_modis",
#                                                     output_tag = "clean_ndvi_dates_modis",
#                                                     max_layers = NULL,
#                                                     sleep_time = 30,
#                                                     verbose = TRUE,
#                                                     ... = ndvi_dates_modis_release)
#   ),


#   tar_target(
#     correct_ndvi_viirs_release_proj_and_extent,
#     process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/ndvi_viirs/",
#                                                     input_tag = "raw_ndvi_viirs",
#                                                     output_tag = "clean_ndvi_viirs",
#                                                     max_layers = 30,
#                                                     sleep_time = 30,
#                                                     verbose = TRUE,
#                                                     ... = ndvi_viirs_release)
#   ),


#     tar_target(
#       correct_ndvi_dates_viirs_release_proj_and_extent,
#       process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/ndvi_dates_viirs/",
#                                                       input_tag = "raw_ndvi_dates_viirs",
#                                                       output_tag = "clean_ndvi_dates_viirs",
#                                                       max_layers = 30,
#                                                       sleep_time = 30,
#                                                       verbose = TRUE,
#                                                       ... = ndvi_dates_viirs_release)
#     ),

#     tar_target(
#       correct_kndvi_release_proj_and_extent,
#       process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/kndvi_modis/",
#                                                       input_tag = "raw_kndvi_modis",
#                                                       output_tag = "clean_kndvi_modis",
#                                                       max_layers = 30,
#                                                       sleep_time = 45,
#                                                       verbose = TRUE,
#                                                       ... = kndvi_modis_release)
#     ), # second chunk

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
#       process_release_stable_data(temp_directory = "data/temp/processed_data/static/",
#                                   input_tag = "processed_static",
#                                   output_tag = "current",
#                                   sleep_time = 120,
#                                   ... = projected_precipitation_chelsa_release,
#                                   ... = projected_landcover_za_release,
#                                   ... = projected_elevation_nasadem_release,
#                                   ... = projected_clouds_wilson_release,
#                                   ... = projected_climate_chelsa_release,
#                                   ... = projected_alos_release,
#                                   ... = remnant_distance_release,
#                                   ... = protected_area_distance_release,
#                                   ... = projected_soil_gcfr_release)
#       ),

#     tar_target(
#       ndvi_to_parquet_release,
#       process_release_dynamic_data_to_parquet(temp_directory = "data/temp/raw_data/ndvi_modis/",
#                                       input_tag = "clean_ndvi_modis",
#                                       output_tag = "current",
#                                       variable_name = "ndvi",
#                                       sleep_time = 30,
#                                       ... = correct_ndvi_release_proj_and_extent)
#       ),

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

)

