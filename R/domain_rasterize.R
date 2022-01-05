# Rasterize Domain

#' @author Adam M. Wilson

#  Rasterize domain to common grid to define the raster domain

#' @param domain vector file of study domain
#' @param dx x resolution
#' @param dy y resolution

domain_rasterize <- function(domain,dx = 500, dy = 500){

  # generate raster version of domain
  domain_template=st_as_stars(st_bbox(domain), dx = dx, dy = dy)

  domain_raster <- domain %>%
    dplyr::select(biomeid_18) %>%
    st_rasterize(template = domain_template)

   domain_raster
  #writeRaster(domain_raster,file="data/domain.tif")


}




