message("Starting tar_make()")
print("Starting tar_make() - print")

library(targets)
library(tarchetypes)
library(visNetwork)
library(future) #not sure why this is needed, but we get an error in some of the files without it
library(googledrive)

#If running this locally, make sure to set up github credentials using gitcreds::gitcreds_set()

#devtools::install_github(repo = "bmaitner/rgee",
#                         ref = "noninteractive_auth")

# Ensure things are clean
  unlink(file.path("data/temp/"), recursive = TRUE, force = TRUE)
  unlink(file.path("data/raw_data/", recursive = TRUE, force = TRUE))
  message(paste("Objects:",ls(),collapse = "\n"))

# source all files in R folder
  lapply(list.files("R",pattern="[.]R",full.names = T), source)
  message(paste("Objects:",ls(),collapse = "\n")) # To make sure all packages are loaded


  options(tidyverse.quiet = TRUE)
  #options(clustermq.scheduler = "multicore")

  tar_option_set(packages = c("cmdstanr", "posterior", "bayesplot", "tidyverse",
                              "stringr","knitr","sf","stars","units",
                              "cubelyr","rgee"))

#set JSON token location (should be authorized for drive and earth engine)
  json_token <- "secrets/ee-wilsonlab-emma-ef416058504a.json"

# ee authentication
  if(T) {
    message("loading rgee")
    library(rgee)
    #Initializing with service account key

    service_account <- jsonlite::read_json(json_token)$client_email
    credentials <- ee$ServiceAccountCredentials(service_account, json_token)
    ee$Initialize(credentials = credentials)

    #Setting up needed objects for rgee

   message("Initializing rgee")

    ee_Initialize(drive = TRUE,
                  gcs = FALSE,
                  use_oob = FALSE,
                  drive_cred_path = json_token,
                  gcs_cred_path = json_token,
                  ee_cred_path = json_token)

  }



list(


  #Prep needed files

  tar_target(
    vegmap_shp, # 2018 National Vegetation Map http://bgis.sanbi.org/SpatialDataset/Detail/1674
    "data/manual_download/VEGMAP2018_AEA_16082019Final/NVM2018_AEA_V22_7_16082019_final.shp",
    format = "file"
  ),

  tar_target(
    remnants_shp,
    "data/manual_download/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp",
    format = "file"
  ),

  tar_target(
    sanbi_fires_shp,
    st_read("data/manual_download/All_Fires/All_Fires_20_21_gw.shp")
  ),


  tar_target(
    country,
    national_boundary()
  )
,

  tar_target(
    vegmap,
    get_vegmap(vegmap_shp)
  ),

  tar_target(
    domain,
    domain_define(vegmap = vegmap, country)
  )
,


# # # Infrequent updates via releases

  tar_target(
      alos_release,
      get_release_alos(temp_directory = "data/temp/raw_data/alos/",
                       tag = "raw_static",
                       domain = domain,
                       json_token)
      )
,

    tar_target(
      climate_chelsa_release,
      get_release_climate_chelsa(temp_directory = "data/temp/raw_data/climate_chelsa/",
                                 tag = "raw_static",
                                 domain = domain)
      )
,

  tar_target(
    clouds_wilson_release,
    get_release_clouds_wilson(temp_directory = "data/temp/raw_data/clouds_wilson/",
                              tag = "raw_static",
                              domain,
                              sleep_time = 180)
    ),

  tar_target(
    elevation_nasadem_release,
    get_release_elevation_nasadem(temp_directory = "data/temp/raw_data/elevation_nasadem/",
                                  tag = "raw_static",
                                  domain)
    )
,

  #Temporarily commented out, seems to be an issue with URL for landcover data at present
  # tar_target(
  #   landcover_za_release,
  #   get_release_landcover_za(temp_directory = "data/temp/raw_data/landcover_za/",
  #                            tag = "raw_static",
  #                            domain = domain)
  #   ),
  #
  tar_target(
    precipitation_chelsa_release,
    get_release_precipitation_chelsa(temp_directory = "data/temp/raw_data/precipitation_chelsa/",
                                     tag = "raw_static",
                                     domain = domain)
    ),

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
# # # # Frequent updates via releases

      tar_age(
        fire_modis_release,
        get_release_fire_modis(temp_directory = "data/temp/raw_data/fire_modis/",
                               tag = "raw_fire_modis",
                               domain = domain,
                               max_layers = 5,
                               sleep_time = 5,
                               json_token = json_token,
                               verbose = FALSE),
        #age = as.difftime(7, units = "days")
        #age = as.difftime(1, units = "days")
        age = as.difftime(0, units = "hours")
      ),

      tar_age(
        kndvi_modis_release,
        get_release_kndvi_modis(temp_directory = "data/temp/raw_data/kndvi_modis/",
                               tag = "raw_kndvi_modis",
                               domain = domain,
                               max_layers = 5,
                               sleep_time = 5,
                               json_token = json_token,
                               verbose = TRUE),
        age = as.difftime(7, units = "days")
        #age = as.difftime(1, units = "days")
        #age = as.difftime(0, units = "hours")
    ),

    tar_age(
      ndvi_modis_release,
      get_release_ndvi_modis(temp_directory = "data/temp/raw_data/ndvi_modis/",
                              tag = "raw_ndvi_modis",
                              domain = domain,
                              max_layers = 12,
                             sleep_time = 5,
                             json_token = json_token),
      #age = as.difftime(7, units = "days")
      #age = as.difftime(1, units = "days")
      age = as.difftime(0, units = "hours")
    ),

    tar_age(
      ndvi_viirs_release,
      get_release_ndvi_viirs(temp_directory = "data/temp/raw_data/ndvi_viirs/",
                             tag = "raw_ndvi_viirs",
                             domain,
                             max_layers = 3,
                             sleep_time = 30,
                             json_token = json_token),
      age = as.difftime(7, units = "days")
      #age = as.difftime(1, units = "days")
      #age = as.difftime(0, units = "hours")
    ),


    tar_age(
      ndvi_dates_modis_release,
      get_release_ndvi_dates_modis(temp_directory = "data/temp/raw_data/ndvi_dates_modis/",
                             repo_tag = "raw_ndvi_dates_modis",
                             domain = domain,
                             max_layers = 5,
                             sleep_time = 10,
                             json_token = json_token),
      #age = as.difftime(7, units = "days")
      #age = as.difftime(1, units = "days")
      age = as.difftime(0, units = "hours")
    ),

    tar_age(
      ndvi_dates_viirs_release,
      get_release_ndvi_dates_viirs(temp_directory = "data/temp/raw_data/ndvi_dates_viirs/",
                                   tag = "raw_ndvi_dates_viirs",
                                   domain = domain,
                                   max_layers = 3,
                                   sleep_time = 30,
                                   json_token = json_token),
      age = as.difftime(7, units = "days")
      #age = as.difftime(1, units = "days")
      #age = as.difftime(0, units = "hours")
    ),



    tar_age(mean_ndvi_release,
            get_release_mean_ndvi_modis(temp_directory = "data/temp/raw_data/mean_ndvi_modis/",
                                       tag = "current",
                                       domain = domain,
                                       sleep_time = 1,
                                       json_token = json_token),
            #age = as.difftime(7, units = "days")
            #age = as.difftime(1, units = "days")
            age = as.difftime(0, units = "hours")
            ),

# #   # tar_age(
# #   #   ndwi_modis_release,
# #   #   get_release_ndwi_modis(temp_directory = "data/temp/raw_data/NDWI_MODIS/",
# #   #                          tag = "current",
# #   #                          domain,
# #   #                          drive_cred_path = json_token),
# #   #   age = as.difftime(7, units = "days")
# #   #   #age = as.difftime(1, units = "days")
# #   #   #age = as.difftime(0, units = "hours")
# #   # ),
# #
# #
# #
# # # # # Fixing projection via releases


      tar_target(
        correct_fire_release_proj_and_extent,
        process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/fire_modis/",
                                                        input_tag = "raw_fire_modis",
                                                        output_tag = "clean_fire_modis",
                                                        max_layers = NULL,
                                                        sleep_time = 30,
                                                        verbose = TRUE,
                                                        ... = fire_modis_release)
        ),

    tar_target(
      correct_ndvi_release_proj_and_extent,
      process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/ndvi_modis/",
                                                      input_tag = "raw_ndvi_modis",
                                                      output_tag = "clean_ndvi_modis",
                                                      max_layers = NULL,
                                                      sleep_time = 30,
                                                      verbose = TRUE,
                                                      ... = ndvi_modis_release)
      ),

  tar_target(
    correct_ndvi_dates_release_proj_and_extent,
    process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/ndvi_dates_modis/",
                                                    input_tag = "raw_ndvi_dates_modis",
                                                    output_tag = "clean_ndvi_dates_modis",
                                                    max_layers = NULL,
                                                    sleep_time = 30,
                                                    verbose = TRUE,
                                                    ... = ndvi_dates_modis_release)
  ),


  tar_target(
    correct_ndvi_viirs_release_proj_and_extent,
    process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/ndvi_viirs/",
                                                    input_tag = "raw_ndvi_viirs",
                                                    output_tag = "clean_ndvi_viirs",
                                                    max_layers = 30,
                                                    sleep_time = 30,
                                                    verbose = TRUE,
                                                    ... = ndvi_viirs_release)
  ),


    tar_target(
      correct_ndvi_dates_viirs_release_proj_and_extent,
      process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/ndvi_dates_viirs/",
                                                      input_tag = "raw_ndvi_dates_viirs",
                                                      output_tag = "clean_ndvi_dates_viirs",
                                                      max_layers = 30,
                                                      sleep_time = 30,
                                                      verbose = TRUE,
                                                      ... = ndvi_dates_viirs_release)
    ),

    tar_target(
      correct_kndvi_release_proj_and_extent,
      process_fix_modis_release_projection_and_extent(temp_directory = "data/temp/raw_data/kndvi_modis/",
                                                      input_tag = "raw_kndvi_modis",
                                                      output_tag = "clean_kndvi_modis",
                                                      max_layers = 30,
                                                      sleep_time = 45,
                                                      verbose = TRUE,
                                                      ... = kndvi_modis_release)
    ),

# # # # Processing via release

    tar_target(
      fire_doy_to_unix_date_release,
      process_release_fire_doy_to_unix_date(input_tag = "clean_fire_modis",
                                            output_tag = "processed_fire_dates",
                                            temp_directory = "data/temp/processed_data/fire_dates/",
                                            sleep_time = 20,
                                            template_release = template_release,
                                            ... = correct_fire_release_proj_and_extent)
      ),

    tar_target(
      burn_date_to_last_burned_date_release,
      process_release_burn_date_to_last_burned_date(input_tag = "processed_fire_dates",
                                                    output_tag = "processed_most_recent_burn_dates",
                                                    temp_directory_input = "data/temp/processed_data/fire_dates/",
                                                    temp_directory_output = "data/temp/processed_data/most_recent_burn_dates/",
                                                    sleep_time = 180,
                                                    sanbi_sf = sanbi_fires_shp,
                                                    expiration_date = NULL,
                                                    ... = fire_doy_to_unix_date_release)
    ),


    tar_target(
      ndvi_relative_days_since_fire_release,
      process_release_ndvi_relative_days_since_fire(temp_input_ndvi_date_folder = "data/temp/raw_data/ndvi_dates_modis/",
                                                    temp_input_fire_date_folder = "data/temp/processed_data/most_recent_burn_dates/",
                                                    temp_fire_output_folder = "data/temp/processed_data/ndvi_relative_time_since_fire/",
                                                    input_fire_dates_tag = "processed_most_recent_burn_dates",
                                                    input_modis_dates_tag = "clean_ndvi_dates_modis",
                                                    output_tag = "processed_ndvi_relative_days_since_fire",
                                                    sleep_time = 60,
                                                    ... = burn_date_to_last_burned_date_release,
                                                    ... = correct_ndvi_dates_release_proj_and_extent)
      ),

      tar_target(
        template_release,
        get_release_template_raster(input_tag = "clean_ndvi_modis",
                            output_tag = "raw_static",
                            temp_directory = "data/temp/template",
                            ... = correct_ndvi_release_proj_and_extent)
      ),

      tar_target(
        remnants_release,
        domain_remnants_release(domain = domain,
                                remnants_shp = remnants_shp,
                                template_release,
                                temp_directory = "data/temp/remnants",
                                out_file = "remnants.tif",
                                out_tag = "processed_static")
      ),

      tar_target(
        remnant_distance_release,
        domain_distance_release(remnants_release = remnants_release,
                                out_file = "remnant_distance.tif",
                                temp_directory = "data/temp/remnants",
                                out_tag = "processed_static")
        ),

      tar_target(
        protected_area_distance_release,
        process_release_protected_area_distance(template_release,
                                                out_file = "protected_area_distance.tif",
                                                temp_directory = "data/temp/protected_area",
                                                out_tag = "processed_static")
      ),

      tar_target(
        projected_alos_release,
        process_release_alos(input_tag = "raw_static",
                             output_tag = "processed_static",
                             temp_directory = "data/temp/raw_data/alos/",
                             template_release = template_release,
                             sleep_time = 60,
                             ... = alos_release)
      ),

      tar_target(
        projected_climate_chelsa_release,
        process_release_climate_chelsa(input_tag = "raw_static",
                                       output_tag = "processed_static",
                                       temp_directory = "data/temp/raw_data/climate_chelsa/",
                                       template_release = template_release,
                                       ... = climate_chelsa_release)
        ),

      tar_target(
        projected_clouds_wilson_release,
        process_release_clouds_wilson(input_tag = "raw_static",
                                      output_tag = "processed_static",
                                      temp_directory = "data/temp/raw_data/clouds_wilson/",
                                      template_release = template_release,
                                      sleep_time = 180,
                                      ... = clouds_wilson_release)
      ),

      tar_target(
        projected_elevation_nasadem_release,
        process_release_elevation_nasadem(input_tag = "raw_static",
                                          output_tag = "processed_static",
                                          temp_directory = "data/temp/raw_data/elevation_nasadem/",
                                          template_release = template_release,
                                          sleep_time = 0,
                                          ... = elevation_nasadem_release)
      ),

      tar_target(
        projected_landcover_za_release,
        process_release_landcover_za(input_tag = "raw_static",
                                     output_tag = "processed_static",
                                     temp_directory = "data/temp/raw_data/landcover_za/",
                                     template_release,
                                     sleep_time = 60,
                                     ... = landcover_za_release)
      )
      ,

      tar_target(
        projected_precipitation_chelsa_release,
        process_release_precipitation_chelsa(input_tag = "raw_static",
                                             output_tag = "processed_static",
                                             temp_directory = "data/temp/raw_data/precipitation_chelsa/",
                                             template_release,
                                             sleep_time = 60,
                                             ... = precipitation_chelsa_release)

      ),

      tar_target(
        projected_soil_gcfr_release,
        process_release_soil_gcfr(input_tag = "raw_static",
                                  output_tag = "processed_static",
                                  temp_directory = "data/temp/raw_data/soil_gcfr/",
                                  template_release,
                                  sleep_time = 60,
                                  ... = soil_gcfr_release)

      ),

      tar_target(
        vegmap_modis_proj,
        process_release_biome_raster(template_release = template_release,
                                     vegmap_shp = vegmap_shp,
                                     domain = domain,
                                     temp_directory = "data/temp/raw_data/vegmap_raster/",
                                     sleep_time = 10)

      )
,




# # # # Prep model data

    tar_target(
      stable_data_release,
      process_release_stable_data(temp_directory = "data/temp/processed_data/static/",
                                  input_tag = "processed_static",
                                  output_tag = "current",
                                  sleep_time = 120,
                                  ... = projected_precipitation_chelsa_release,
                                  ... = projected_landcover_za_release,
                                  ... = projected_elevation_nasadem_release,
                                  ... = projected_clouds_wilson_release,
                                  ... = projected_climate_chelsa_release,
                                  ... = projected_alos_release,
                                  ... = remnant_distance_release,
                                  ... = protected_area_distance_release,
                                  ... = projected_soil_gcfr_release)
      ),

    tar_target(
      ndvi_to_parquet_release,
      process_release_dynamic_data_to_parquet(temp_directory = "data/temp/raw_data/ndvi_modis/",
                                      input_tag = "clean_ndvi_modis",
                                      output_tag = "current",
                                      variable_name = "ndvi",
                                      sleep_time = 30,
                                      ... = correct_ndvi_release_proj_and_extent)
      ),

    tar_target(
      fire_dates_to_parquet_release,
      process_release_dynamic_data_to_parquet(temp_directory = "data/temp/processed_data/ndvi_relative_time_since_fire/",
                                      input_tag = "processed_ndvi_relative_days_since_fire",
                                      output_tag = "current",
                                      variable_name = "time_since_fire",
                                      sleep_time = 30,
                                      ... = ndvi_relative_days_since_fire_release)
    ),

    tar_target(
      most_recent_fire_dates_to_parquet_release,
      process_release_dynamic_data_to_parquet(temp_directory = "data/temp/processed_data/most_recent_burn_dates/",
                                      input_tag = "processed_most_recent_burn_dates",
                                      output_tag = "current",
                                      variable_name = "most_recent_burn_dates",
                                      sleep_time = 30,
                                      ... = burn_date_to_last_burned_date_release)
    ),

# periodically clean up google drive folder

  tar_age(
    remove_ee_backup,
    clean_up(),
    #age = as.difftime(7, units = "days")
    age = as.difftime(0, units = "hours")
  )


)





################################################################################
