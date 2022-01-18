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
#' @note To save space, the function also crops and masks the layers per the stored domain.
get_clouds_wilson <- function(directory = "data/raw_data/clouds_wilson/", domain) {

  #Create directory if needed

    if(!dir.exists(directory)){
      dir.create(directory)
    }

  #Skip the whole thing if we already have all 20 layers we want

    if( length(list.files(directory, pattern = ".tif")) >= 20){

      message("Cloud data already present, skipping")
      return(invisible(NULL))

    }

  #Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

    if(getOption('timeout') < 1000){
      options(timeout = 1000)
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

      #If file is present, skip it
        if(file.exists(paste(directory,filename,sep = ""))){

          message(paste(filename, "already present, skipping"))

          next

        }

      # download the full file
        download.file(url = links[i],
                      destfile = paste(directory,filename,sep = ""))

      # Load in the downloaded file
        raster_i <- raster(paste(directory,filename,sep = ""))

      # Transform domain
        domain_tf <- sf::st_transform(x = domain,
                                      crs = crs(raster_i))

      #Crop to extent
        raster_i <- raster::crop(x = raster_i,
                            y = raster::extent(domain_tf)
                            )

      # Mask to domain
        raster_i <- mask(x = raster_i,
                         mask = domain_tf)

    # Save the cropped/masked raster
      writeRaster(x = raster_i,
                  filename = paste(directory, filename, sep = ""),
                  overwrite = TRUE)

    } #end of for i loop

  message("Finished with cloud data")
  return(invisible(NULL))

}




################################################################################
