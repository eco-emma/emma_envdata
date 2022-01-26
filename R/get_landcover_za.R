# land cover from https://egis.environment.gov.za/sa_national_land_cover_datasets

#' @author Brian Maitner

#' @description This function will download South Africa national landcover layers, skipping any that have been downloaded already.
#' @author Brian Maitner
#' @param directory The directory the soil layers should be saved to, defaults to "data/raw_data/landcover_za/"
#' @param domain domain (sf polygon) used for masking
get_landcover_za <- function(directory = "data/raw_data/landcover_za/", domain) {

  #make a directory if one doesn't exist yet

    if(!dir.exists(directory)){
      dir.create(directory)
    }

  #check if file exists already
    if(length(list.files(directory,
                         pattern = ".tif$",
                         full.names = TRUE)) > 0){

      message("Landcover layer present, skipping download")
      return(invisible(NULL))

    }



  #Note: I'm not sure if this is a permanent link or not, so this might not be a permanent solution

    url <- "https://sfiler.environment.gov.za:8443/ssf/s/readFile/folderEntry/40906/8afbc1c77a484088017a4e8a1abd0052/1624802570000/last/SA_NLC_2020_Geographic.tif.vat.zip"

    filename <- strsplit(x = url,
                         split = "/",
                         fixed = T)[[1]][length(strsplit(x = url,
                                                         split = "/",
                                                         fixed = T)[[1]])]

  #Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

    if(getOption('timeout') < 1000){
      options(timeout = 1000)
    }


  #Download the file
    download.file(url = url,
                  destfile = paste(directory, filename, sep = ""))

  #Unzip the file
    unzip(zipfile = paste(directory, filename, sep = ""), exdir = directory)

  #Delete the zipped version (which isn't much smaller anyway)
    file.remove(paste(directory, filename, sep = ""))

  # Load the raster
    raster_i <- raster::raster(x = list.files(directory,
                                              pattern = ".tif$",
                                              full.names = TRUE))

  # Reproject domain to match raster

    domain_tf <- sf::st_transform(x = domain,
                                  crs = crs(raster_i))

  # Crop to extent

    raster_i <- raster::crop(x = raster_i,
                             y = extent(domain_tf))

  # Mask to domain

    raster_i <- terra::mask(x = raster_i,
                            mask = domain_tf)

  # Save the cropped/masked raster
      writeRaster(x = raster_i,
                  filename = list.files(directory,
                                        pattern = ".tif$",
                                        full.names = TRUE),
                  overwrite = TRUE)

  # Finish up
    message("Landcover layer downloaded")
    return(invisible(NULL))

}



