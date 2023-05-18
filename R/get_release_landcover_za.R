# land cover from https://egis.environment.gov.za/sa_national_land_cover_datasets

#' @author Brian Maitner

#' @description This function will download South Africa national landcover layers, skipping any that have been downloaded already.
#' @author Brian Maitner
#' @param temp_directory The directory the soil layers should be saved to, defaults to "data/temp/raw_data/landcover_za/"
#' @param tag The tag for release, default is "raw_static"
#' @param domain domain (sf polygon) used for masking
get_release_landcover_za <- function(temp_directory = "data/temp/raw_data/landcover_za/",
                                     tag = "raw_static",
                                     domain) {

  #  #Ensure directory is empty if it exists

  if(dir.exists(temp_directory)){
    unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
  }


  #make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
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
                  destfile = file.path(temp_directory, filename))

  #Unzip the file
    unzip(zipfile = file.path(temp_directory, filename),
          exdir = file.path(temp_directory))

  #Delete the zipped version (which isn't much smaller anyway)

    unlink(file.path(temp_directory, filename))

  # Load the raster

    raster_i <- terra::rast(x = list.files(temp_directory,
                                              pattern = ".tif$",
                                              full.names = TRUE))

  # Reproject domain to match raster

    domain_tf <- sf::st_transform(x = domain,
                                  crs = crs(raster_i))

  # Crop to extent

    raster_i <- terra::crop(x = raster_i,
                             y = extent(domain_tf))

  # Mask to domain

    raster_i <- terra::mask(x = raster_i,
                            mask = domain_tf)

  # Save the cropped/masked raster

    terra::writeRaster(x = raster_i,
                       filename = list.files(temp_directory,
                                             pattern = ".tif$",
                                             full.names = TRUE),
                       overwrite = TRUE)


  # Release

    pb_upload(file = list.files(temp_directory,
                                pattern = ".tif$",
                                full.names = TRUE),
              repo = "AdamWilsonLab/emma_envdata",
              tag = tag,
              overwrite = TRUE)


  # Delete temp folder
    rm(raster_i)

    unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)

  # Finish up
    message("Landcover layer downloaded")
    return(invisible(NULL))

}




