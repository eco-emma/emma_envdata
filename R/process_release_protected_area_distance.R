#Process domain

library(sf)
library(dplyr)
library(units)
library(terra)


#' @author Adam Wilson & Brian Maitner
#' @description This code produces a raster containing distances to protected areas
#' @param template_release path to raster file to use as a template for reprojection
process_release_protected_area_distance <- function(template_release,
                                            out_file="protected_area_distance.tif",
                                            temp_directory = "data/temp/protected_area",
                                            out_tag = "processed_static"
){

  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }

    # get template
      robust_pb_download(file = template_release$file,
                         dest = file.path(temp_directory),
                         repo = template_release$repo,
                         tag = template_release$tag,
                         overwrite = TRUE,
                         max_attempts = 10,
                         sleep_time = 10)

      template <- rast(file.path(temp_directory,template_release$file))

  # get protected area file

    robust_pb_download(file = "protected_areas.gpkg",
                       dest = file.path(temp_directory),
                       repo = "AdamWilsonLab/emma_report",
                       tag = "park_data",
                       overwrite = TRUE,
                       max_attempts = 10,
                       sleep_time = 10)

    pa <- st_read(file.path(temp_directory,"protected_areas.gpkg"))

  # reproject

    pa <-
    pa %>%
       st_transform(st_crs(template))

    pa_dist_rast <-
      pa %>%
      rasterize(template) %>%
      distance(target=NA)/1000

  terra::writeRaster(pa_dist_rast,
                     file = file.path(temp_directory,out_file),
                     overwrite = T)

  #release
  pb_upload(file = file.path(temp_directory,out_file),
            repo = template_release$repo,
            tag = out_tag)

  #get md
  file_md <- list(repo = template_release$repo,
                  tag = out_tag,
                  file = out_file)

  #cleanup
  unlink(x = temp_directory, recursive = TRUE, force = TRUE)

  #end

  return(file_md)

}
