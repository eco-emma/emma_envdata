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
    domain_define(vegmap=vegmap, country)
  ),
  tar_target(
    remnants,
    domain_remnants(domain, remnants_shp=remnants_shp),
    format = "file"
  ),
  tar_target(
    remnant_distance,
    domain_distance(remnants),
    format = "file"
  ),
  tar_target(
    alos,
    get_alos("data/raw_data/alos/"),
    format = "file"
  ),
  tar_target(
    chelsa,
    get_climate_chelsa(directory = "data/raw_data/climate_chelsa/"),
    format = "file"
  ),
  #   tar_target(
  #   ndvi,
  #   get_ndvi(directory = "data/raw_data/ndvi_modis/"),
  #   format = "file"
  # ),
  tar_target(
    model_data,
    get_model_data(remnant_distance),
    format = "file"
  )

)

