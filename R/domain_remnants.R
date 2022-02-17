#Process domain

library(sf)
library(dplyr)
library(units)
library(terra)


#' @author Adam Wilson & Brian Maitner
#' @description This code cleans up the RLE Remnants file to yield a simpler polygon that we can use as a domain.
#' @param remnants_shp The file location of the remnants shapefile.  Defaults to "data/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp"
#' @param template path to raster file to use as a template for reprojection

domain_remnants <- function(domain, remnants_shp, template, file = "data/remnants.tif") {

  message("Starting remnants directory setup")

  #set up the directory structure if needed (ugly code, but it works)
    if(!dir.exists(strsplit(x = file,split = "/")[[1]][1:length(strsplit(x = file,split = "/")[[1]]) -1] %>%
                   paste(collapse = "/"))){

      strsplit(x = file,split = "/")[[1]][1:length(strsplit(x = file,split = "/")[[1]]) -1] %>%
        paste(collapse = "/") %>%
        dir.create(recursive = TRUE)

    }

  message("Starting definition of biomes to keep")
  # Define which biome(s) to keep
    biome_keep <- c("Fynbos")

    message("Loading template")
  # Load in a domain template in the MODIS projection
    ##domain_template=st_as_stars(st_bbox(domain), dx = 500, dy = 500)
    domain_template <- st_as_stars(rast(template))
    print(domain_template)

    message("reprojecting domain")
  # reproject domain to match the template
    domain <-domain %>%
      st_transform(crs = crs(rast(template)))


  # Load remnants file
  # remnants <- st_read(remnants_shp) %>%
  #   janitor::clean_names() %>%
  #   filter(biome %in% biome_keep ) %>% #filter to list above
  #   st_make_valid() %>%    #some polygons had errors - this fixes them
  #   st_combine() %>%
  #   st_cast(to = "POLYGON") %>%
  #   st_as_sf() %>%
  #   dplyr::mutate(area = units::set_units(st_area(.),km^2))
  #

    message("Loading remnants polygon")

  # Load remnants file
  remnants <- st_read(remnants_shp) %>%
    janitor::clean_names() %>%
    st_transform(crs = crs(domain)) %>%
    filter(biome %in% biome_keep ) %>% #filter to list above
    st_make_valid()


  message("Making domain raster")
  domain_raster <- domain %>%
    dplyr::select(domain) %>%
    st_rasterize(template = domain_template, values = NA_real_)

  print(domain_raster)

  message("Starting remnants raster")
  remnants_raster <- remnants %>%
    mutate(remnant=1) %>%
    vect() %>%
    rasterize(x = .,
              y = rast(domain_template),
              field = "remnant",
              touches = T,
              cover = T)

  print(remnants_raster)

  message("Starting write raster")
  writeRaster(remnants_raster, file = file, overwrite = T)

return(file)

}

domain_distance<- function(remnants, file="data/remnant_distance.tif"){

  #set up the directory structure if needed (ugly code, but it works)
  if(!dir.exists(strsplit(x = file,split = "/")[[1]][1:length(strsplit(x = file,split = "/")[[1]]) -1] %>%
                 paste(collapse = "/"))){

    strsplit(x = file,split = "/")[[1]][1:length(strsplit(x = file,split = "/")[[1]]) -1] %>%
      paste(collapse = "/") %>%
      dir.create(recursive = TRUE)

  }

  distance_raster <-
    rast(remnants) %>%
    terra::app(fun=function(x) ifelse(is.na(x),1,NA)) %>%
    terra::distance(grid=T)/1000


  writeRaster(distance_raster, file = file, overwrite = T)

  return(file)

}
