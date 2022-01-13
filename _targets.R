library(targets)
library(tarchetypes)
library(visNetwork)

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
  tar_target(
    remnants,
    domain_remnants(domain, remnants_shp = remnants_shp),
    format = "file"
  ),
  tar_target(
    remnant_distance,
    domain_distance(remnants),
    format = "file"
  ),

  #Infrequent updates

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
  tar_age(
    landcover_za,
    get_landcover_za(domain = domain),
    age = as.difftime(26, units = "weeks")
  ),
  tar_age(
    precipitation_chelsa,
    get_precipitation_chelsa(domain = domain),
    age = as.difftime(26, units = "weeks")
  ),

#Frequent updates
  tar_age(
    fire_modis,
    get_fire_modis(domain = domain),
    age = as.difftime(7, units = "days")
  ),
  # tar_age(
  #   kndvi_modis,
  #   get_kndvi_modis(domain = domain),
  #   age = as.difftime(7, units = "days")
  # ),
  tar_age(
    ndvi_modis,
    get_ndvi_modis(domain = domain),
    age = as.difftime(7, units = "days")
  ),
  tar_age(
    ndvi_dates_modis,
    get_ndvi_dates_modis(domain = domain),
    age = as.difftime(7, units = "days")
  ),


# Processing
  tar_target(
    fire_doy_to_unix_date,
    process_fire_doy_to_unix_date(fire_modis)
  ),
  tar_target(
    burn_date_to_last_burned_date,
    process_burn_date_to_last_burned_date(fire_doy_to_unix_date)
  ),
  tar_target(
    ndvi_relative_days_since_fire,
    process_ndvi_relative_days_since_fire(burn_date_to_last_burned_date,
                                          ndvi_dates_modis)
  ),
  tar_target(
    model_data,
    get_model_data(remnant_distance),
    format = "file"
  )

)

