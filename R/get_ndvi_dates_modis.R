# Get MODIS NDVI dates

#Load packages
library(rgee)
library(raster)
library(lubridate)


#' @author Brian Maitner, with tips from csaybar
#' @description This is an internal function used to convert the ee date to the UNIX standard date
get_integer_date <-function(img) {

  # 1. Extract the DayOfYear band
    day_values <- img$select("DayOfYear")

  # 2. Get the first day of the year and the UNIX base date.
    first_doy <- ee$Date(day_values$get("system:time_start"))$format("Y")
    base_date <- ee$Date("1970-01-01")


  # 3. Get the day diff between year start_date and UNIX date
    daydiff <- ee$Date(first_doy)$difference(base_date,"day")

  # 4. Mask to only values greater than zero.
    mask <- day_values$gt(0)
    day_values <- day_values$updateMask(mask)

  # #Now, I just need to add the origin to the map
    day_values$add(daydiff)
}



#' @author Brian Maitner, with tips from csaybar
#' @description This code is designed to modify the MODIS "DayOfYear" band to a "days relative to Jan 01 1970" band to facilitate comparisons with fire data and across years.
#' @note This code assumes that data are downloaded in order, which is usually the case.  In the case that a raster is lost, it won't be replaced automatically unless it happens to be at the very end.
#' Probably not going to cause a problem, but worth noting out of caution.
get_ndvi_dates_modis <- function(directory = "data/raw_data/ndvi_dates_modis/") {

  #Make a directory

    if(!dir.exists(directory)){
      dir.create(directory)
    }

  #ee_Initialize(drive = TRUE)

    modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A1")

  #get domain

    domain <- get_domain()

  # convert date to UNIX standard (ie days from 1-1-1970)

    ndvi_integer_dates <- modis_ndvi$map(get_integer_date)

    #Download to local

      #What has been downloaded already?

        images_downloaded <- list.files(directory,
                                        full.names = F,
                                        pattern = ".tif")

        images_downloaded <- gsub(pattern = ".tif",
                                  replacement = "",
                                  x = images_downloaded,
                                  fixed = T)


      #check to see if any images have been downloaded already
      if(length(images_downloaded) == 0){

        newest <- lubridate::as_date(-1) #if nothing is downloaded, start in 1970

      }else{

        newest <- max(lubridate::as_date(images_downloaded)) #if there are images, start with the most recent

      }


      #Filter the data to exclude anything you've already downloaded
        ndvi_integer_dates_new <-
          ndvi_integer_dates$
          filter(ee$Filter$gt("system:index",
                              gsub(pattern = "-", replacement = "_", x = newest)
          )
          )


    #Download the new stuff
      ee_imagecollection_to_local(ic = ndvi_integer_dates_new,
                                  region = domain,
                                  dsn = directory)
    #End function

      message("\nDownload of MODIS NDVI date files complete")

      return(invisible(NULL))


}#end function


########################################

