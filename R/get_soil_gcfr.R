#GCFR soil layers (Cramer et al. 2019) - https://doi.org/10.5061/dryad.37qc017

#' @author Brian Maitner

library(rvest)
library(rdryad)

#' @description This function will download GCFR soil layers, skipping any that have been downloaded already.
#' @author Brian Maitner
#' @param directory The directory the soil layers should be saved to, defaults to "data/raw_data/soil_gcfr/"
#' @import rgee
get_soil_gcfr <- function(directory = "data/raw_data/soil_gcfr/", domain) {

  # Set up directories if need be

    if(!dir.exists(directory)){
      dir.create(directory, recursive = TRUE)
    }

  #If files are present, skip
    if(length(list.files(path = directory,
                         pattern = ".tif",
                         full.names = T)) == 7){

      message("Soil data already present, skipping")
      return(invisible(NULL))
    }

  # Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

    if(getOption('timeout') < 1000){
      options(timeout = 1000)
    }

  #Download the files from dryad

    locations <- dryad_download(dois = "10.5061/dryad.37qc017")

  # Move the files to a permanent location (rdryad doesn't give you an option)

    file.copy(from = locations[[1]],
              to = directory,
              overwrite = TRUE)

  # Delete the old copies from the temporary location

    unlink(dirname(dirname(locations[[1]])),recursive = TRUE,force = TRUE)

  # Clean up

    rm(locations)

  #Crop and mask

    # Get file names

      files <- list.files(path = directory,
                          pattern = ".tif",
                          full.names = T)


    # Load in domain


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


  # End function
    message("Soil data finished")
    return(invisible(NULL))


} # end fx











