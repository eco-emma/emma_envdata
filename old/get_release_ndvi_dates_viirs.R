# Get MODIS NDVI dates

#Load packages
library(rgee)
library(raster)
library(lubridate)
library(piggyback)
library(tidyverse)

#' @author Brian Maitner, with tips from csaybar
#' @description This is an internal function used to convert the ee date to the UNIX standard date
get_integer_date_viirs <-function(img) {

  # per https://lpdaac.usgs.gov/products/vnp13a1v001/, dates between 1 and 366 are values, 0 and -1 not.
  # so we need to mask or otherwise ignore these values before calculating the doy

  # 1. Extract the DayOfYear band
  day_values <- img$select("composite_day_of_the_year")

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
#' @param directory The directory the ndvi date layers should be saved to, defaults to "data/raw_data/ndvi_dates_modis/"
#' @param domain domain (sf polygon) used for masking
#' @param max_layers the maximum number of layers to download at once.  Set to NULL to ignore.  Default is 50
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy
#' @note This code assumes that data are downloaded in order, which is usually the case.  In the case that a raster is lost, it won't be replaced automatically unless it happens to be at the very end.
#' Probably not going to cause a problem, but worth noting out of caution.
#'
get_release_ndvi_dates_viirs <- function(temp_directory = "data/temp/raw_data/ndvi_dates_viirs/",
                                         tag = "raw_ndvi_dates_viirs",
                                         domain,
                                         max_layers = 50,
                                         sleep_time = 1,
                                         json_token) {

  # clean out directory if it exists

    if(dir.exists(temp_directory)){
      unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)
    }

  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }

  #Get release assetts

  release_assetts <- pb_list(repo = "AdamWilsonLab/emma_envdata")

  #Create releases if needed

  if(!tag %in% release_assetts$tag){

    #Make sure there is a release by attempting to create one.  If it already exists, this will fail

    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  tag),
             error = function(e){message("Previous release found")})

  }

  #Initialize earth engine (for targets works better if called here)

    #ee_Initialize()

  # Load the collection

    viirs_ndvi <- ee$ImageCollection("NOAA/VIIRS/001/VNP13A1") #500 m v 6.1

  # Format the domain

    domain <- sf_as_ee(x = domain)
    domain <- domain$geometry()

  # convert date to UNIX standard (ie days from 1-1-1970)

    ndvi_integer_dates <- viirs_ndvi$map(get_integer_date_viirs)


  # Download to local

    #Get a list of files already released


    released_files <-
      release_assetts %>%
      dplyr::filter(.data$tag == .env$tag)


    released_files$date <- gsub(pattern = ".tif",
                                replacement = "",
                                x = released_files$file_name)

    released_files <-
      released_files %>%
      dplyr::filter(file_name != "") %>%
      dplyr::filter(file_name != "log.csv")


    #check to see if any images have been downloaded already

    if(nrow(released_files) == 0){

      newest <- lubridate::as_date(-1) #if nothing is downloaded, start in 1970

    }else{

      newest <- max(lubridate::as_date(released_files$date)) #if there are images, start with the most recent

    }


    # Filter the data to exclude anything you've already downloaded

      ndvi_integer_dates_new <-
        ndvi_integer_dates$
        filter(ee$Filter$gt("system:index",
                            gsub(pattern = "-", replacement = "_", x = newest)
        )
        )

    # Function to optionally limit the number of layers downloaded at once

      if(!is.null(max_layers)){

        info <- ndvi_integer_dates_new$getInfo()

        to_download <- unlist(lapply(X = info$features,FUN = function(x){x$properties$`system:index`}))

        to_download <- gsub(pattern = "_",replacement = "-",x = to_download)

        if(length(to_download) > max_layers){

          # ndvi_integer_dates_new <- ndvi_integer_dates_new$filterDate(start = to_download[1],
          #                                                     opt_end = to_download[max_layers+1])

          ndvi_integer_dates_new <-
            ndvi_integer_dates_new$
            filter(ee$Filter$lte("system:index",
                                 gsub(pattern = "-",
                                      replacement = "_",
                                      x = to_download[max_layers])
            )
            )

        }


      }# end if maxlayers is not null

  # Skip download if up to date already

      if(length(ndvi_integer_dates_new$getInfo()$features) == 0){

        message("No new VIIRS NDVI date layers to download")
        return(max(gsub(pattern = "_",replacement = "-",x = released_files$date))) #return the last date that had been done

      }


  # Download the new stuff

      #Download layers

      if(length(ndvi_integer_dates_new$getInfo()$features) == 1 ){

        # assign name

        file_name <- ndvi_integer_dates_new$getInfo()$features[[1]]$properties$`system:index`

        # convert to image

        ndvi_integer_dates_new_image <- ndvi_integer_dates_new %>%
          ee$ImageCollection$toList(count = 1, offset = 0) %>%
          ee$List$get(0) %>%
          ee$Image()

        # download single image

        tryCatch(expr =
                   ee_as_stars(image = ndvi_integer_dates_new_image,
                               region = domain,
                               dsn = file.path(temp_directory,file_name),
                               formatOptions = c(cloudOptimized = true),
                               drive_cred_path = json_token
                   ),
                 error = function(e){message("Captured an error in rgee/earth engine processing of NDVI.")}
        )#trycatch

      }else{

        tryCatch(expr =
                   ee_imagecollection_to_local(ic = ndvi_integer_dates_new,
                                               region = domain,
                                               dsn = temp_directory,
                                               formatOptions = c(cloudOptimized = true),
                                               drive_cred_path = json_token
                                               #,scale = 463.3127
                   ),
                 error = function(e){message("Captured an error in rgee/earth engine processing of NDVI.")}
        )

      }#else

  # Push files to release

      # Get a list of the local files

      local_files <- data.frame(local_filename = list.files(path = temp_directory,
                                                            recursive = TRUE,
                                                            full.names = TRUE))

      # End if there are no new/updated files to release

      if(nrow(local_files) == 0){

        message("Releases are already up to date.")
        return(max(gsub(pattern = "_",replacement = "-",x = released_files$date))) #return the last date that had been done


      }

        # loop through and release everything

        for( i in 1:nrow(local_files)){

          Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

          pb_upload(file = local_files$local_filename[i],
                    repo = "AdamWilsonLab/emma_envdata",
                    tag = tag)

        } # end i loop


    # Delete temp files
        unlink(x = file.path(temp_directory), #sub used to delete any trailing slashes, which interfere with unlink
               recursive = TRUE)

    # Finish up
      message("Finished Downloading NDVI date layers")

      local_files %>%
        dplyr::filter(grepl(pattern = ".tif$",x = local_filename)) %>%
        mutate(date_format = basename(local_filename)) %>%
        mutate(date_format = gsub(pattern = ".tif",replacement = "",x = date_format)) %>%
        mutate(date_format = gsub(pattern = "_",replacement = "-",x = date_format)) %>%
        mutate(date_format = lubridate::as_date(date_format)) %>%
        dplyr::select(date_format) -> local_files

      return(as.character(max(local_files$date_format))) # return the date of the latest file that was updated




}#end function


########################################


