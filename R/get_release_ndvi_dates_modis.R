# Get MODIS NDVI dates

#Load packages
library(rgee)
library(raster)
library(lubridate)
library(piggyback)
library(tidyverse)

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

#' @author Brian Maitner
#' @description This is an internal function used to convert the ee date to the UNIX standard date. It is meant to be an R equivalent the the earth engine code above
#' @note Ideally, this code is temporary and can be deleted or commented out once GEE fixes the problems with newer MODIS layers
#' @note internal
convert_integer_date_R <- function(temp_directory){

  date_rasters <- list.files(temp_directory,pattern = ".tif$",full.names = TRUE)

  if(length(date_rasters)==0){return(NULL)}

    for(i in 1:length(date_rasters)){

      # load raster
       rast_i <- rast(date_rasters[i])

      # get first day of year
      year_start_date <-
       date_rasters[i] %>%
        strsplit(split = "/") %>%
        as.data.frame() %>%
        slice_tail(n = 1) %>%
        gsub(pattern = ".tif",replacement = "") %>%
        as_date() %>%
        lubridate::floor_date(unit = "year") %>%
        as.numeric()-1 #subtract one because there is no zeroth day of the year.


  # Convert the raster to unix date
      rast_i <-
      rast_i %>%
        mask(mask = rast_i>0,
             maskvalue = 0,
             updatevalue=NA,)+year_start_date

  # save output

      terra::writeRaster(x = rast_i,
                         filename = date_rasters[i],overwrite=TRUE)

    }#i loop


}#interger date R function

#' @author Brian Maitner, with tips from csaybar
#' @description This code is designed to modify the MODIS "DayOfYear" band to a "days relative to Jan 01 1970" band to facilitate comparisons with fire data and across years.
#' @param directory The directory the ndvi date layers should be saved to, defaults to "data/raw_data/ndvi_dates_modis/"
#' @param domain domain (sf polygon) used for masking
#' @param max_layers the maximum number of layers to download at once.  Set to NULL to ignore.  Default is 50
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy
#' @note This code assumes that data are downloaded in order, which is usually the case.  In the case that a raster is lost, it won't be replaced automatically unless it happens to be at the very end.
#' Probably not going to cause a problem, but worth noting out of caution.
#'
get_release_ndvi_dates_modis <- function(temp_directory = "data/temp/raw_data/ndvi_dates_modis/",
                                         repo_tag = "raw_ndvi_dates_modis",
                                         domain,
                                         max_layers = 50,
                                         sleep_time = 1) {

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

    if(!repo_tag %in% release_assetts$tag){

      #Make sure there is a release by attempting to create one.  If it already exists, this will fail

      tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                       tag =  repo_tag),
               error = function(e){message("Previous release found")})

    }

  #Initialize earth engine (for targets works better if called here)

    ee_Initialize()

  # Load the collection

    modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A1")

  # Format the domain

    domain <- sf_as_ee(x = domain)
    domain <- domain$geometry()

  # convert date to UNIX standard (ie days from 1-1-1970)

    #ndvi_integer_dates <- modis_ndvi$map(get_integer_date) # MODIS in GEE is currently broken and this causes an error on data 2-2-22 or later

    ndvi_integer_dates <- modis_ndvi$select("DayOfYear") #comment this line out if the above is uncommented

  # Download to local

    #Get a list of files already released

    release_assetts %>%
      dplyr::filter(tag == repo_tag) -> released_files

    # released_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
    #                            tag = tag)

    released_files$date <- gsub(pattern = ".tif",
                                replacement = "",
                                x = released_files$file_name)

    released_files <-
      released_files %>%
      filter(file_name != "") %>%
      filter(file_name != "log.csv")


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

        message("No new NDVI date layers to download")
        return(max(gsub(pattern = "_",replacement = "-",x = released_files$date))) #return the last date that had been done

      }


  # Download the new stuff

    tryCatch(expr =
               ee_imagecollection_to_local(ic = ndvi_integer_dates_new,
                                           region = domain,
                                           dsn = temp_directory),
             error = function(e){message("Captured an error in rgee/earth engine processing of NDVI dates.")}
    )

  # Convert the dates

      #note that this section could be omitted if ndvi_integer_dates <- modis_ndvi$map(get_integer_date) is used

      convert_integer_date_R(temp_directory = temp_directory)

  # end date conversion

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
                    tag = repo_tag)

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
        mutate(date_format = lubridate::as_date(date_format))%>%
        dplyr::select(date_format) -> local_files

      return(as.character(max(local_files$date_format))) # return the date of the latest file that was updated




}#end function


########################################


