#GCFR soil layers (Cramer et al. 2019) - https://doi.org/10.5061/dryad.37qc017

#' @author Brian Maitner

library(rvest)
library(rdryad)

#' @description This function will download GCFR soil layers, skipping any that have been downloaded already.
#' @author Brian Maitner
#' @param directory The directory the soil layers should be saved to, defaults to "data/raw_data/soil_gcfr/"
#' @param tag Tag for release, default is "raw_static"
#' @param domain domain (sf polygon) used for masking
#' @import rgee
get_release_soil_gcfr <- function(temp_directory = "data/temp/raw_data/soil_gcfr/",
                                  tag = "raw_static",
                                  domain) {

  # Set up directories if need be

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }


  # Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

    if(getOption('timeout') < 1000){
      options(timeout = 1000)
    }

  #Download the files from dryad

    locations <- dryad_download(dois = "10.5061/dryad.37qc017")

  # Move the files to a permanent location (rdryad doesn't give you an option)

    file.copy(from = locations[[1]],
              to = temp_directory,
              overwrite = TRUE)

  # Delete the old copies from the temporary location

    unlink(dirname(dirname(locations[[1]])),recursive = TRUE,force = TRUE)

  # Clean up

    rm(locations)

  #Crop and mask

  # Get file names

    files <- list.files(path = temp_directory,
                        pattern = ".tif",
                        full.names = T)


  # Iteratively crop and mask

  for( i in 1:length(files)){

    raster_i <- raster::raster(x = files[i])

    # Reproject domain if not done already
    if(i == 1){

      #Reproject domain to match raster
      domain <- sf::st_transform(x = domain,
                                 crs = raster::crs(raster_i))


      ext <- raster::extent(domain)

    }

    #Crop to extent
    raster_i <- raster::crop(x = raster_i,
                             y = ext)

    # do a mask

    raster_i <- terra::mask(x = raster_i,
                            mask = domain)

    # Save the cropped/masked raster
    raster::writeRaster(x = raster_i,
                        filename = files[i],
                        overwrite = TRUE)

  } # i files loop


  # Release
    pb_upload(repo = "AdamWilsonLab/emma_envdata",
              file = list.files(file.path(temp_directory),
                                recursive = TRUE,
                                full.names = TRUE),
              tag = tag)


  # Delete directory and contents

    unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)


  # End function

    message("Soil data finished")
    return(invisible(NULL))


} # end fx











