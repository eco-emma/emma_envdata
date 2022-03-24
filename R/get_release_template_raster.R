library(tidyverse)
library(piggyback)

#' @author Brian Maitner
#' @description This function just grabs the first raster file in a directory
get_release_template_raster <- function(input_tag = "processed_fire_dates",
                                        output_tag = "processed_static",
                                        temp_directory = "data/temp/template",
                                        ...){

  # Set up directories if need be

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }

  # Get file
    files <- pb_list(repo = "AdamWilsonLab/emma_envdata",
              tag = input_tag) %>%
                filter(grepl(x = file_name, pattern = ".tif$"))

    robust_pb_download(file = files$file_name[1],
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = input_tag,
                       dest = temp_directory)

    template <- raster::raster(x = file.path(temp_directory,files$file_name[1]))

    template[1:ncell(template)] <- 1:ncell(template)


    raster::writeRaster(x = template,
                filename = file.path(temp_directory, "template.tif"),
                overwrite = TRUE)

  #Release

    pb_upload(repo = "AdamWilsonLab/emma_envdata",
              file = file.path(temp_directory, "template.tif"),
              tag = output_tag,
              overwrite = TRUE)

    template_md <- list(repo = "AdamWilsonLab/emma_envdata",
                        tag = output_tag,
                        file = "template.tif")

  #Empty old stuff

    unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)


  #Return the template raster
    return(template_md)

}


