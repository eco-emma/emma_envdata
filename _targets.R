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

list(
  tar_target(
    vegmap_shp, # 2018 National Vegetation Map http://bgis.sanbi.org/SpatialDataset/Detail/1674
    "data/VEGMAP2018_AEA_16082019Final/NVM2018_AEA_V22_7_16082019_final.shp",
    format = "file"
  ),
  tar_target(
    remnants_shp,
    "data/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp",
    format = "file"
  ),
  tar_target(
    za,
    national_boundary()
  ),
  tar_target(
    vegmap,
    get_vegmap(vegmap_shp)
  ),
  tar_target(
    domain,
    domain_define(vegmap=vegmap, za=za, buffer=20000)
  ),
  tar_target(
    remnants,
    domain_remnants(domain, remnants_shp=remnants_shp,za=za),
    format="file"
  ),
  tar_target(
    remnant_distance,
    domain_distance(remnants),
    format="file"
  )

)

