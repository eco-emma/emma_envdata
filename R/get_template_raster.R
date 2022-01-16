
#' @author Brian Maitner
#' @description This function just grabs the first raster file in a directory
get_template_raster <- function(directory = "data/raw_data/ndvi_modis/", ...){


  terra::rast(x = list.files(path = directory,
                             pattern = ".tif",
                             full.names = TRUE)[1])




}
