# Rasterize Domain

#' @author Adam M. Wilson

#  Rasterize domain to common grid to define the raster domain

#' @param vegmap is the path to the subsetted 2018 national vegetation map
#' @param remnants is the path to the most recent remnants shapefile
#' @param buffer size of domain buffer (in m)

domain_rasterize <- function(domain){

  # generate raster version of domain
  domain_template=st_as_stars(st_bbox(domain), dx = 500, dy = 500)

  domain_raster <- domain %>%
    dplyr::select(biomeid_18) %>%
    st_rasterize(template = domain_template)

  writeRaster(domain_raster,file="data/domain.tif")


}




