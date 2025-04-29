#Code for extracting NDWI data from google earth engine
library(terra)

#' @author Brian Maitner
#' @description This function will download the most recent MODIS NDWI layer
#' @import rgee piggyback sf
#' @param directory directory to save data in. Defaults to "data/temp/raw_data/NDWI_MODIS/"
#' @param domain domain (spatialpolygons* object) used for masking
get_release_ndwi_modis <- function(temp_directory = "data/temp/raw_data/NDWI_MODIS/",
                                   tag = "current",
                                   domain,
                                   drive_cred_path = json_token){


  #  #Ensure directory is empty if it exists

    if(dir.exists(temp_directory)){
      unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
    }


  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }


  # Load the image

    warning("NDWI is only available for MODIS v 6.0 in GEE.  Check for v 6.1 in the future")
    ndwi <- ee$ImageCollection("MODIS/MCD43A4_006_NDWI")
    #ndwi <- ee$ImageCollection("MODIS/MCD43A4_061_NDWI")


  #Format the domain
    domain <- sf_as_ee(x = domain)
    domain <- domain$geometry()


    #cut down to the most recent year to work with it
      info <-
        ndwi$
        filterDate(start = as.character(Sys.Date()-365),
                        end = as.character(Sys.Date()))$
        select("NDWI")$
        getInfo()


  #Cut down to the most recent layer

    most_recent <-
    lapply(X = info$features,FUN = function(x){x$properties$`system:index`})%>%
      unlist()

    most_recent <- most_recent[length(most_recent)]

    most_recent_ee  <- ndwi$filter(ee$Filter$eq("system:index",most_recent))$first()

    # Map$addLayer(most_recent_ee) #for checking

  #Download the raster
    ndwi_raster <- ee_as_raster(image = most_recent_ee,
                                region = domain,
                                #scale = 100, #used to adjust the scale. commenting out uses the default
                                dsn = file.path(temp_directory, "ndwi.tif"),
                                maxPixels = 10000000000,
                                drive_cred_path = json_token)

    ndwi_raster <- rast(file.path(temp_directory, "ndwi.tif"))
    ndwi_raster_og <- ndwi_raster

    #plot(ndwi_raster_og)


  # Load raster

    #ndwi_raster <- terra::rast(file.path(temp_directory, "ndwi.tif"))

    nasa_proj <- "+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +R=6371007.181 +units=m +no_defs"

    if(!identical(crs(nasa_proj),crs(ndwi_raster))){
      crs(ndwi_raster) <- nasa_proj
    }

  #Write corrected raster (extra stuff needed because terra doesn't allow overwrite if in use)

    writeRaster(x = ndwi_raster,
                filename = file.path(temp_directory, "ndwi2.tif"))

    rm(ndwi_raster,ndwi_raster_og)

    file.remove(file.path(temp_directory, "ndwi.tif"))

    file.rename(from = file.path(temp_directory, "ndwi2.tif"),
                to = file.path(temp_directory, "ndwi.tif"))

  # Release file

    pb_upload(repo = "AdamWilsonLab/emma_envdata",
              file = file.path(temp_directory,"ndwi.tif"),
              tag = tag)

  #Remove files
    unlink(temp_directory,recursive = TRUE, force = TRUE)

  # End
    message("NDWI download finished")
    return(as.character(Sys.Date()))



}#end fx



