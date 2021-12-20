#Process domain

library(sf)
library(dplyr)
library(units)
library(terra)


#' @author Adam Wilson & Brian Maitner
#' @description This code cleans up the RLE Remnants file to yield a simpler polygon that we can use as a domain.
#' @param remnants_shp The file location of the remnants shapefile.  Defaults to "data/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp"
#' @param za Country polygon


domain_remnants <- function(domain, remnants_shp,za,file="data/remnants.tif") {

  # Define which biome(s) to keep
  biome_keep <- c("Fynbos")


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

   # Load remnants file
  remnants <- st_read(remnants_shp) %>%
    janitor::clean_names() %>%
    st_transform(crs = crs(domain)) %>%
    filter(biome %in% biome_keep ) %>% #filter to list above
    st_make_valid()

  domain_template=st_as_stars(st_bbox(domain), dx = 500, dy = 500)

  domain_raster <- domain %>%
    dplyr::select(domain) %>%
    st_rasterize(template = domain_template, values = NA_real_)

  remnants_raster <- remnants %>%
    mutate(remnant=1) %>%
    vect() %>%
    terra::rasterize(x=.,y=rast(domain_template),field="remnant",touches=T,cover=T)


  writeRaster(remnants_raster,file=file,overwrite=T)

return(file)

}

domain_distance<- function(remnants_raster, file="data/remnant_distance.tif"){

  distance_raster <-
    rast(remnants_raster) %>%
    terra::app(fun=function(x) ifelse(is.na(x),1,NA)) %>%
    terra::distance(x=., grid=T)


  writeRaster(distance_raster,file=file,overwrite=T)

  return(file)

}
