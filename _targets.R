library(targets)
library(tarchetypes)
library(visNetwork)

# source all files in R folder
lapply(list.files("R",pattern="[.]R",full.names = T), source)

options(tidyverse.quiet = TRUE)
options(clustermq.scheduler = "multicore")

tar_option_set(packages = c("cmdstanr", "posterior", "bayesplot", "tidyverse",
                            "stringr","knitr","sf","stars","units",
                            "cubelyr"))

# ee authentication
if(F) {
  library(rgee)
  ee$Initialize()
}


list(
  tar_target(
    vegmap_shp, # 2018 National Vegetation Map http://bgis.sanbi.org/SpatialDataset/Detail/1674
    "raw_data/VEGMAP2018_AEA_16082019Final/NVM2018_AEA_V22_7_16082019_final.shp",
    format = "file"
  ),
  tar_target(
    remnants_shp,
    "raw_data/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp",
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

  #Infrequent downloads

  tar_target(
    alos,
    get_alos(domain = domain)
  ),
  tar_target(
    climate_chelsa,
    get_climate_chelsa(domain = domain)
  ),
  tar_target(
    clouds_wilson,
    get_clouds_wilson(domain = domain)
  ),
  tar_target(
    elevation_nasadem,
    get_elevation_nasadem(domain = domain)
  ),
  tar_target(
    landcover_za,
    get_landcover_za(domain = domain)
  ),
  tar_target(
    precipitation_chelsa,
    get_precipitation_chelsa(domain = domain)
  ),

#Frequent updates
  tar_target(
    fire_modis,
    get_fire_modis(domain = domain)
  ),
  tar_target(
    kndvi_modis,
    get_kndvi_modis(domain = domain)
  ),
  tar_target(
    ndvi_dates_modis,
    get_ndvi_dates_modis(domain = domain)
  ),
  tar_target(
    ndvi_modis,
    get_ndvi_modis(domain = domain)
  ),
  tar_target(
    model_data,
    get_model_data(remnant_distance),
    format = "file"
  )

)

