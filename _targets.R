library(targets)
library(tarchetypes)
library(visNetwork)
library(future) #not sure why this is needed, but we get an error in some of the files without it


# Ensure things are clean
  unlink(file.path("data/temp/"), recursive = TRUE, force = TRUE)
  unlink(file.path("data/raw_data/", recursive = TRUE, force = TRUE))
  message(paste("Objects:",ls(),collapse = "\n"))

# source all files in R folder
  lapply(list.files("R",pattern="[.]R",full.names = T), source)

options(tidyverse.quiet = TRUE)
options(clustermq.scheduler = "multicore")

tar_option_set(packages = c("cmdstanr", "posterior", "bayesplot", "tidyverse",
                            "stringr","knitr","sf","stars","units",
                            "cubelyr","rgee"))

# ee authentication
if(T) {
  library(rgee)
  ee$Initialize()
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
    country,
    national_boundary()
  ),

  tar_target(
    vegmap,
    get_vegmap(vegmap_shp)
  ),

  tar_target(
    domain,
    domain_define(vegmap = vegmap, country)
  ),


# Infrequent updates via releases

  tar_age(
    alos_release,
    get_release_alos(temp_directory = "data/temp/raw_data/alos/",
                     tag = "raw_static",
                     domain = domain),

    age = as.difftime(52, units = "weeks")
  ),

  tar_age(
    climate_chelsa_release,
    get_release_climate_chelsa(temp_directory = "data/temp/raw_data/climate_chelsa/",
                               tag = "raw_static",
                               domain = domain),

    age = as.difftime(54, units = "weeks")
  ),

  tar_age(
    clouds_wilson_release,
    get_release_clouds_wilson(temp_directory = "data/temp/raw_data/clouds_wilson/",
                              tag = "raw_static",
                              domain),
    age = as.difftime(56, units = "weeks")
  ),

  tar_age(
    elevation_nasadem_release,
    get_release_elevation_nasadem(temp_directory = "data/temp/raw_data/elevation_nasadem/",
                                  tag = "raw_static",
                                  domain),
    age = as.difftime(58, units = "weeks")
  ),

  tar_age(
    landcover_za_release,
    get_release_landcover_za(temp_directory = "data/temp/raw_data/landcover_za/",
                             tag = "raw_static",
                             domain = domain),
    age = as.difftime(60, units = "weeks")
  ),

  tar_age(
    precipitation_chelsa_release,
    get_release_precipitation_chelsa(temp_directory = "data/temp/raw_data/precipitation_chelsa/",
                                     tag = "raw_static",
                                     domain = domain),
    age = as.difftime(62, units = "weeks")
  ),

  tar_age(
    soil_gcfr_release,
    get_release_soil_gcfr(temp_directory = "data/temp/raw_data/soil_gcfr/",
                          tag = "raw_static",
                          domain),
    age = as.difftime(64, units = "weeks")
  ),


# # Frequent updates via releases

    tar_age(
      fire_modis_release,
      get_release_fire_modis(temp_directory = "data/temp/raw_data/fire_modis/",
                             tag = "raw_fire_modis",
                             domain = domain,
                             max_layers = 25,
                             sleep_time = 5),
      #age = as.difftime(7, units = "days")
      age = as.difftime(0, units = "hours")
    ),

    tar_age(
    kndvi_modis_release,
    get_release_kndvi_modis(temp_directory = "data/temp/raw_data/kndvi_modis/",
                           tag = "raw_kndvi_modis",
                           domain = domain,
                           max_layers = 25,
                           sleep_time = 5),
    #age = as.difftime(7, units = "days")
    age = as.difftime(0, units = "hours")
  ),

  tar_age(
    ndvi_modis_release,
    get_release_ndvi_modis(temp_directory = "data/temp/raw_data/ndvi_modis/",
                            tag = "raw_ndvi_modis",
                            domain = domain,
                            max_layers = 25,
                           sleep_time = 5),
    #age = as.difftime(7, units = "days")
    age = as.difftime(0, units = "hours")
  ),

  tar_age(
    ndvi_dates_modis_release,
    get_release_ndvi_dates_modis(temp_directory = "data/temp/raw_data/ndvi_dates_modis/",
                           tag = "raw_ndvi_dates_modis",
                           domain = domain,
                           max_layers = 25,
                           sleep_time = 10),
    #age = as.difftime(7, units = "days")
    age = as.difftime(0, units = "hours")
  ),

# # Fixing projection via releases

  tar_target(
    correct_fire_release_proj,
    process_fix_modis_release_projection(temp_directory = "data/temp/raw_data/fire_modis/",
                                         tag = "raw_fire_modis",
                                         max_layers = NULL,
                                         sleep_time = 30,
                                 ... = fire_modis_release)
  ),

  tar_target(
    correct_ndvi_release_proj,
    process_fix_modis_release_projection(temp_directory = "data/temp/raw_data/ndvi_modis/",
                                         tag = "raw_ndvi_modis",
                                         max_layers = NULL,
                                         sleep_time = 30,
                                         ... = ndvi_modis_release)
  ),

  tar_target(
    correct_ndvi_dates_release_proj,
    process_fix_modis_release_projection(temp_directory = "data/temp/raw_data/ndvi_dates_modis/",
                                         tag = "raw_ndvi_dates_modis",
                                         max_layers = NULL,
                                         sleep_time = 30,
                                         ... = ndvi_dates_modis_release)
  ),

  tar_target(
    correct_kndvi_release_proj,
    process_fix_modis_release_projection(temp_directory = "data/temp/raw_data/kndvi_modis/",
                                         tag = "raw_kndvi_modis",
                                         max_layers = NULL,
                                         sleep_time = 30,
                                         ... = kndvi_modis_release)
  ),


# # Processing via release

  tar_target(
    fire_doy_to_unix_date_release,
    process_release_fire_doy_to_unix_date(input_tag = "raw_fire_modis",
                                          output_tag = "processed_fire_dates",
                                          temp_directory = "data/temp/processed_data/fire_dates/",
                                          sleep_time = 20,
                                          ... = correct_fire_release_proj)
    ),

  tar_target(
    burn_date_to_last_burned_date_release,
    process_release_burn_date_to_last_burned_date(input_tag = "processed_fire_dates",
                                                  output_tag = "processed_most_recent_burn_dates",
                                                  temp_directory_input = "data/temp/processed_data/fire_dates/",
                                                  temp_directory_output = "data/temp/processed_data/most_recent_burn_dates/",
                                                  sleep_time = 30,
                                                  ... = fire_doy_to_unix_date_release)
  ),


  tar_target(
    ndvi_relative_days_since_fire_release,
    process_release_ndvi_relative_days_since_fire(temp_input_ndvi_date_folder = "data/temp/raw_data/ndvi_dates_modis/",
                                                  temp_input_fire_date_folder = "data/temp/processed_data/most_recent_burn_dates/",
                                                  temp_fire_output_folder = "data/temp/processed_data/ndvi_relative_time_since_fire/",
                                                  input_fire_dates_tag = "processed_most_recent_burn_dates",
                                                  input_modis_dates_tag = "raw_ndvi_dates_modis",
                                                  output_tag = "processed_ndvi_relative_days_since_fire",
                                                  sleep_time = 60,
                                                  ... = burn_date_to_last_burned_date_release,
                                                  ... = correct_ndvi_dates_release_proj)
    ),

  tar_target(
    template_release,
    get_release_template_raster(input_tag = "processed_fire_dates",
                        output_tag = "raw_static",
                        temp_directory = "data/temp/template",
                        ... = correct_fire_release_proj)
  ),


#
#
#   ##
#
# #   tar_target(
# #     model_data,
# #     get_model_data(remnant_distance),
# #     format = "file"
# #   ),
#
#




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
                            out_file="remnant_distance.tif",
                            temp_directory = "data/temp/remnants",
                            out_tag = "processed_static")
    ),

  tar_target(
    projected_alos_release,
    process_release_alos(input_tag = "raw_static",
                         output_tag = "processed_static",
                         temp_directory = "data/temp/raw_data/alos/",
                         template_release = template_release,
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
                                         sleep_time = 30,
                                         ... = precipitation_chelsa_release)

  ),

tar_target(
  projected_soil_gcfr_release,
  process_release_soil_gcfr(input_tag = "raw_static",
                            output_tag = "processed_static",
                            temp_directory = "data/temp/raw_data/soil_gcfr/",
                            template_release,
                            sleep_time = 30,
                            ... = soil_gcfr_release)

),

# # # Prep model data
  tar_target(
    stable_data_release,
    process_release_stable_data(temp_directory = "data/temp/processed_data/static/",
                                input_tag = "processed_static",
                                output_tag = "current",
                                ... = projected_precipitation_chelsa_release,
                                ... = projected_landcover_za_release,
                                ... = projected_elevation_nasadem_release,
                                ... = projected_clouds_wilson_release,
                                ... = projected_climate_chelsa_release,
                                ... = projected_alos_release,
                                ... = remnant_distance_release,
                                ... = projected_soil_gcfr_release)
    ),

  tar_target(
    ndvi_to_parquet_release,
    process_release_dynamic_data_to_parquet(temp_directory = "data/temp/raw_data/ndvi_modis/",
                                    input_tag = "raw_ndvi_modis",
                                    output_tag = "current",
                                    variable_name = "ndvi",
                                    sleep_time = 30,
                                    ... = correct_ndvi_release_proj)
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
)

)





################################################################################
################################################################################
################################################################################


# Archived Bits Below #
# Infrequent updates

# tar_age(
#   alos,
#   get_alos(domain = domain),
#   age = as.difftime(26, units = "weeks")
# ),
#
# tar_age(
#   climate_chelsa,
#   get_climate_chelsa(domain = domain),
#   age = as.difftime(26, units = "weeks")
# ),
#
# tar_age(
#   clouds_wilson,
#   get_clouds_wilson(domain = domain),
#   age = as.difftime(26, units = "weeks")
# ),
#
# tar_age(
#   elevation_nasadem,
#   get_elevation_nasadem(domain = domain),
#   age = as.difftime(26, units = "weeks")
# ),
#
#   tar_age(
#     landcover_za,
#     get_landcover_za(domain = domain),
#     age = as.difftime(26, units = "weeks")
#   ),

# tar_age(
#   precipitation_chelsa,
#   get_precipitation_chelsa(domain = domain),
#   age = as.difftime(26, units = "weeks")
# ),
#
#   tar_age(
#     soil_gcfr,
#     get_soil_gcfr(domain = domain),
#     age = as.difftime(26, units = "weeks")
#   ),

# # Frequent updates
#
# tar_age(
#   fire_modis,
#   get_fire_modis(domain = domain,
#                  max_layers = 50),
#   age = as.difftime(7, units = "days")
# ),
# tar_age(
#   kndvi_modis,
#   get_kndvi_modis(domain = domain,
#                   max_layers = 50),
#   age = as.difftime(7, units = "days")
#   #age = as.difftime(0, units = "hours")
# ),
# tar_age(
#   ndvi_modis,
#   get_ndvi_modis(domain = domain,
#                  max_layers = 50),
#   age = as.difftime(7, units = "days")
# ),
# tar_age(
#   ndvi_dates_modis,
#   get_ndvi_dates_modis(domain = domain,
#                        max_layers = 50),
#   age = as.difftime(7, units = "days")
#   #age = as.difftime(0, units = "hours")
# ),
## Fixing projections
#
# tar_target(
#   correct_ndvi_proj,
#   process_fix_modis_projection(directory = "data/raw_data/ndvi_modis/",
#                                ... = ndvi_modis)
# ),
# tar_target(
#   correct_ndvi_date_proj,
#   process_fix_modis_projection(directory = "data/raw_data/ndvi_dates_modis/",
#                                ... = ndvi_dates_modis)
# ),
# tar_target(
#   correct_kndvi_proj,
#   process_fix_modis_projection(directory = "data/raw_data/kndvi_modis/",
#                                ... = kndvi_modis)
# ),
# tar_target(
#   correct_fire_proj,
#   process_fix_modis_projection(directory = "data/raw_data/fire_modis/",
#                                ... = fire_modis)
# ),
## Processing

# tar_target(
#   fire_doy_to_unix_date,
#   process_fire_doy_to_unix_date(... = correct_fire_proj)
# ),
#
# tar_target(
#   burn_date_to_last_burned_date,
#   process_burn_date_to_last_burned_date(... = fire_doy_to_unix_date)
# ),
# tar_target(
#   ndvi_relative_days_since_fire,
#   process_ndvi_relative_days_since_fire(... = burn_date_to_last_burned_date,
#                                         ... = correct_ndvi_date_proj)
# ),
#
# tar_target(
#   template,
#   get_template_raster(... = correct_ndvi_proj)
# ),


# tar_target(
#     projected_alos,
#     process_alos(template = template,
#                  ... = alos)
#   ),

#
#   tar_target(
#     remnants,
#     domain_remnants(domain = domain,
#                     remnants_shp = remnants_shp,
#                     template = template,
#                     file = "data/processed_data/remnants/remnants.tif"),
#     format = "file"
#   ),
#
#   tar_target(
#     remnant_distance,
#     domain_distance(remnants,
#                     file = "data/processed_data/remnant_distance/remnant_distance.tif"),
#     format = "file"
#   ),
#
#   tar_target(
#     projected_climate_chelsa,
#     process_climate_chelsa(template = template, ... = climate_chelsa)
#   ),
#
#
#   tar_target(
#     projected_clouds_wilson,
#     process_clouds_wilson(template = template, ... = clouds_wilson)
#   ),
#
#   tar_target(
#     projected_elevation_nasadem,
#     process_elevation_nasadem(template = template, ... = elevation_nasadem)
#   ),
#
#   tar_target(
#     projected_landcover_za,
#     process_landcover_za(template = template, ... = landcover_za)
#   ),
#
#   tar_target(
#     projected_precipitation_chelsa,
#     process_precipitation_chelsa(template = template, ... = precipitaton_chelsa)
#
#   ),
#
# # # Prep model data
#   tar_target(
#     stable_data,
#     process_stable_data(output_dir = "data/processed_data/model_data/",
#                         precip_dir = "data/processed_data/precipitation_chelsa/",
#                         landcover_dir = "data/processed_data/landcover_za/",
#                         elevation_dir = "data/processed_data/elevation_nasadem/",
#                         cloud_dir = "data/processed_data/clouds_wilson/",
#                         climate_dir = "data/processed_data/climate_chelsa/",
#                         alos_dir = "data/processed_data/alos/",
#                         remnant_distace_dir = "data/processed_data/remnant_distance/",
#                         ... = projected_precipitation_chelsa,
#                         ... = projected_landcover_za,
#                         ... = projected_elevation_nasadem,
#                         ... = projected_clouds_wilson,
#                         ... = projected_climate_chelsa,
#                         ... = projected_alos,
#                         ... = remnant_distance),
#     format = "file"
#   ),
#   tar_target(
#     ndvi_to_parquet,
#     process_dynamic_data_to_parquet(input_dir = "data/raw_data/ndvi_modis/",
#                                     output_dir = "data/processed_data/model_data/dynamic_parquet/ndvi/",
#                                     variable_name = "ndvi",
#                                     ... = correct_ndvi_proj)
#     ),
#   tar_target(
#     fire_dates_to_parquet,
#     process_dynamic_data_to_parquet(input_dir = "data/processed_data/ndvi_relative_time_since_fire/",
#                                     output_dir = "data/processed_data/model_data/dynamic_parquet/time_since_fire/",
#                                     variable_name = "time_since_fire",
#                                     ... = ndvi_relative_days_since_fire)
#   ),

#   tar_target(
#     most_recent_fire_dates_to_parquet,
#     process_dynamic_data_to_parquet(input_dir = "data/processed_data/most_recent_burn_dates/",
#                                     output_dir = "data/processed_data/model_data/dynamic_parquet/most_recent_burn_dates/",
#                                     variable_name = "most_recent_burn_date",
#                                     ... = burn_date_to_last_burned_date)
#     ),

#   #Release Data
#   tar_target(
#     release_data_to_github,
#     release_data(data_directory = "data/processed_data/model_data/",
#                  tag = "current",
#                  ... = stable_data,
#                  ... = most_recent_fire_dates_to_parquet,
#                  ... = fire_dates_to_parquet,
#                  ... = ndvi_to_parquet)
# )
