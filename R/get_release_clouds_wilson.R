# Clouds



#####################################################################################
# http://www.earthenv.org/cloud


library(xml2)
library(rvest)
library(raster)

#' @description This function will download the Wilson cloud layers (http://www.earthenv.org/cloud), skipping any that have been downloaded already.
#' @author Brian Maitner
#' @param directory The directory the cloud layers should be saved to, defaults to "data/raw_data/ndvi_modis/"
#' @param domain domain (sf polygon) used for masking
#' @param sleep_time Amount of time to pause between uploads
#' @note To save space, the function also crops and masks the layers per the stored domain.
get_release_clouds_wilson <- function(temp_directory = "data/temp/raw_data/clouds_wilson/",
                                      tag = "raw_static",
                                      domain,
                                      sleep_time = 180) {


  #  #Ensure directory is empty if it exists

    if(dir.exists(temp_directory)){
      unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
    }


  #Create directory if needed

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory,recursive = TRUE)
    }

  #Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

    if(getOption('timeout') < 10000){
      options(timeout = 10000)
    }


  #Get a list of the available files

    URL <- "http://www.earthenv.org/cloud"

    links <- html_attr(html_nodes(read_html(URL), "a"), "href")

    links <- links[grep(pattern = "MODCF", x = links)]

    links <- links[grep(pattern = "CloudForestPrediction",
                        x = links,
                        invert = TRUE)] #ignore cloud forest (out of domain)

  #Download each file (note: we might also consider updating this to ignore layers that are already present)

  for( i in 1:length(links)){

    layer_i <- links[i]

    # split out the filename from the location
      filename <- strsplit(x = layer_i,split = "/")[[1]][length(strsplit(x = layer_i,split = "/")[[1]])]

      robust_download_file(url = links[i],
                           destfile = file.path(temp_directory, filename),
                           max_attempts = 10,
                           sleep_time = 10)


    # Load in the downloaded file
      #raster_i <- terra::rast(file.path(temp_directory, filename)) doesn't work
      raster_i <- raster::raster(file.path(temp_directory, filename))

    # Transform domain
      domain_tf <- sf::st_transform(x = domain,
                                    crs = crs(raster_i))

    #Crop to extent
      raster_i <- raster::crop(x = raster_i,
                               y = raster::extent(domain_tf)
      )

    # Mask to domain
      raster_i <- raster::mask(x = raster_i,
                               mask = domain_tf)

    # Plot
      plot(terra::rast(raster_i),main = filename)

    # Save the cropped/masked raster
      writeRaster(x = terra::rast(raster_i), #this conversion to terra is odd.  But for some reason if you don't include it, the output layer contains only NA values
                  filename = file.path(temp_directory, filename),
                  overwrite = TRUE)

    # Push release

      pb_upload(file = file.path(temp_directory, filename),
                repo = "AdamWilsonLab/emma_envdata",
                tag = tag,
                name = filename,
                overwrite = TRUE)

    # Delete file

      file.remove(file.path(temp_directory, filename))

    # pause to keep github happy
      Sys.sleep(sleep_time)


  } #end of for i loop

    #Delete temp dir

    unlink(x = file.path(temp_directory), recursive = TRUE,force = TRUE)

  # End

    message("Finished with cloud data")
    return(invisible(NULL))

}




################################################################################
