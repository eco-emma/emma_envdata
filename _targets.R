library(targets)
library(tarchetypes)
library(visNetwork)
library(future) #not sure why this is needed, but we get an error in some of the files without it

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

# Infrequent updates

  tar_age(
    alos,
    get_alos(domain = domain),
    age = as.difftime(26, units = "weeks")
  ),
  tar_age(
    climate_chelsa,
    get_climate_chelsa(domain = domain),
    age = as.difftime(26, units = "weeks")
  ),
  tar_age(
    clouds_wilson,
    get_clouds_wilson(domain = domain),
    age = as.difftime(26, units = "weeks")
  ),
  tar_age(
    elevation_nasadem,
    get_elevation_nasadem(domain = domain),
    age = as.difftime(26, units = "weeks")
  ),
  # tar_age(
  #   landcover_za,
  #   get_landcover_za(domain = domain),
  #   age = as.difftime(26, units = "weeks")
  # ),
  tar_age(
    precipitation_chelsa,
    get_precipitation_chelsa(domain = domain),
    age = as.difftime(26, units = "weeks")
  ),

# # Frequent updates

  tar_age(
    fire_modis,
    get_fire_modis(domain = domain,
                   max_layers = 50),
    age = as.difftime(7, units = "days")
  ),
  tar_age(
    kndvi_modis,
    get_kndvi_modis(domain = domain,
                    max_layers = 50),
    age = as.difftime(7, units = "days")
    #age = as.difftime(0, units = "hours")
  ),
  tar_age(
    ndvi_modis,
    get_ndvi_modis(domain = domain,
                   max_layers = 50),
    age = as.difftime(7, units = "days")
  ),
  tar_age(
    ndvi_dates_modis,
    get_ndvi_dates_modis(domain = domain,
                         max_layers = 50),
    age = as.difftime(7, units = "days")
    #age = as.difftime(0, units = "hours")
  ),
  # Frequent updates via releases
    tar_age(
      fire_modis_release,
      get_release_fire_modis(temp_directory = "data/temp/raw_data/fire_modis/",
                             tag = "raw_fire_modis",
                             domain = domain,
                             max_layers = 50,
                             sleep_time = 1),
      age = as.difftime(7, units = "days")
      #age = as.difftime(0, units = "hours")
    ),
    tar_age(
    kndvi_modis_release,
    get_release_kndvi_modis(temp_directory = "data/temp/raw_data/kndvi_modis/",
                           tag = "raw_kndvi_modis",
                           domain = domain,
                           max_layers = 50,
                           sleep_time = 1),
    age = as.difftime(7, units = "days")
    #age = as.difftime(0, units = "hours")
  ),
  tar_age(
    ndvi_modis_release,
    get_release_ndvi_modis(temp_directory = "data/temp/raw_data/ndvi_modis/",
                            tag = "raw_ndvi_modis",
                            domain = domain,
                            max_layers = 50,
                           sleep_time = 1),
    age = as.difftime(7, units = "days")
    #age = as.difftime(0, units = "hours")
  ),
  tar_age(
    ndvi_dates_modis_release,
    get_release_ndvi_dates_modis(temp_directory = "data/temp/raw_data/ndvi_dates_modis/",
                           tag = "raw_ndvi_dates_modis",
                           domain = domain,
                           max_layers = 50,
                           sleep_time = 1),
    #age = as.difftime(7, units = "days")
    age = as.difftime(0, units = "hours")
  ),

# Fixing projections

  tar_target(
    correct_ndvi_proj,
    process_fix_modis_projection(directory = "data/raw_data/ndvi_modis/",
                                 ... = ndvi_modis)
  ),
  tar_target(
    correct_ndvi_date_proj,
    process_fix_modis_projection(directory = "data/raw_data/ndvi_dates_modis/",
                               ... = ndvi_dates_modis)
  ),
  tar_target(
    correct_kndvi_proj,
    process_fix_modis_projection(directory = "data/raw_data/kndvi_modis/",
                               ... = kndvi_modis)
  ),
  tar_target(
    correct_fire_proj,
    process_fix_modis_projection(directory = "data/raw_data/fire_modis/",
                               ... = fire_modis)
  ),
# Fixing projection via releases
  tar_target(
    correct_fire_release_proj,
    process_fix_modis_release_projection(temp_directory = "data/temp/raw_data/fire_modis/",
                                         tag = "raw_fire_modis",
                                         max_layers = NULL,
                                         sleep_time = 2,
                                 ... = fire_modis_release)
  ),
  tar_target(
    correct_ndvi_release_proj,
    process_fix_modis_release_projection(temp_directory = "data/temp/raw_data/ndvi_modis/",
                                         tag = "raw_ndvi_modis",
                                         max_layers = NULL,
                                         sleep_time = 5,
                                         ... = ndvi_modis_release)
  ),
  tar_target(
    correct_ndvi_dates_release_proj,
    process_fix_modis_release_projection(temp_directory = "data/temp/raw_data/ndvi_dates_modis/",
                                         tag = "raw_ndvi_dates_modis",
                                         max_layers = NULL,
                                         sleep_time = 2,
                                         ... = ndvi_dates_modis_release)
  ),
  tar_target(
    correct_kndvi_release_proj,
    process_fix_modis_release_projection(temp_directory = "data/temp/raw_data/kndvi_modis/",
                                         tag = "raw_kndvi_modis",
                                         max_layers = NULL,
                                         sleep_time = 5,
                                         ... = kndvi_modis_release)
  ),

#
# # Processing

    tar_target(
      fire_doy_to_unix_date_release,
      process_release_fire_doy_to_unix_date(input_folder = "raw_fire_modis",
                                            output_folder = "processed_fire_dates",
                                            temp_directory = "data/temp/processed_data/fire_dates/",
                                            sleep_time = 5,
                                            ... = correct_fire_release_proj)
    ),

    tar_target(
      fire_doy_to_unix_date,
      process_fire_doy_to_unix_date(... = correct_fire_proj)
    ),
#   tar_target(
#     burn_date_to_last_burned_date,
#     process_burn_date_to_last_burned_date(... = fire_doy_to_unix_date)
#   ),
#   tar_target(
#     ndvi_relative_days_since_fire,
#     process_ndvi_relative_days_since_fire(... = burn_date_to_last_burned_date,
#                                           ... = correct_ndvi_date_proj)
#   ),
#   tar_target(
#     model_data,
#     get_model_data(remnant_distance),
#     format = "file"
#   ),
  tar_target(
    template,
    get_template_raster(... = correct_ndvi_proj)
  ),
  tar_target(
    remnants,
    domain_remnants(domain = domain,
                    remnants_shp = remnants_shp,
                    template = template,
                    file = "data/processed_data/remnants/remnants.tif"),
    format = "file"
  ),
  tar_target(
    remnant_distance,
    domain_distance(remnants,
                    file = "data/processed_data/remnant_distance/remnant_distance.tif"),
    format = "file"
  )
#,
#   tar_target(
#     projected_alos,
#     process_alos(template = template, ... = alos)
#   ),
#   tar_target(
#     projected_climate_chelsa,
#     process_climate_chelsa(template = template, ... = climate_chelsa)
#   ),
#   tar_target(
#     projected_clouds_wilson,
#     process_clouds_wilson(template = template, ... = clouds_wilson)
#   ),
#   tar_target(
#     projected_elevation_nasadem,
#     process_elevation_nasadem(template = template, ... = elevation_nasadem)
#   ),
#   tar_target(
#     projected_landcover_za,
#     process_landcover_za(template = template, ... = landcover_za)
#   ),
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

)
