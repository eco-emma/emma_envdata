library(rgee)
library(piggyback)
library(tidyverse)

#' @description This function will download ndvi layers (derived from MODIS 16 day products), skipping any that have been downloaded already.
#' @author Brian Maitner, but built from code by Qinwen, Adam, and the KNDVI ms authors
#' @param temp_directory The directory the fire layers should be saved to prior to releasing, defaults to "data/raw_data/ndvi_modis/"
#' @param tag tag to be used for the Github release
#' @param domain domain (sf polygon) used for masking
#' @param max_layers the maximum number of layers to download at once.  Set to NULL to ignore.  Default is 50
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy
#' @import rgee
get_release_ndvi_viirs <- function(temp_directory = "data/temp/raw_data/ndvi_viirs/",
                                   tag = "raw_ndvi_viirs",
                                   domain,
                                   max_layers = 50,
                                   sleep_time = 1,
                                   json_token) {

  #  #Ensure directory is empty if it exists

    if(dir.exists(temp_directory)){
      unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
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

  # Load the image collection
    viirs_ndvi <- ee$ImageCollection("NOAA/VIIRS/001/VNP13A1") #500 m v 6.1

  #Format the domain
    domain <- sf_as_ee(x = domain)
    domain <- domain$geometry()

  # Viirs makes it much easier to filter poor quality pixels by providing a QA layer with the bitwise hassle by providing a pixel_reliability layer
  # https://developers.google.com/earth-engine/datasets/catalog/NOAA_VIIRS_001_VNP13A1?hl=en#bands
  #MODIS makes it simple to filter out poor quality pixels thanks to a quality control bits band (DetailedQA).
  #The following function helps us to distinct between good data (bit == …00) and marginal data (bit != …00).


  clean_viirs <- function(img){

    # Extract the NDVI band
    ndvi_values <- img$select("NDVI")

    # Extract the quality band and create a mask
    ndvi_qa <- img$select("pixel_reliability")$lte(2)

    # Mask pixels with value zero.
    ndvi_values$updateMask(ndvi_qa)


  }



  # clean the dataset

    ndvi_clean <- viirs_ndvi$map(clean_viirs)

  #Get a list of files already released
    release_tag <- tag

    released_files  <-
    release_assetts %>%
      dplyr::filter(tag == release_tag) %>%
      mutate(date = gsub(pattern = ".tif",
                         replacement = "",
                         x = file_name)) %>%
      dplyr::filter(file_name != "") %>%
      dplyr::filter(file_name != "log.csv")


  #check to see if any images have been downloaded already

  if(nrow(released_files) == 0){

    newest <- lubridate::as_date(-1) #if nothing is downloaded, start in 1970

  }else{

    newest <- max(lubridate::as_date(released_files$date)) #if there are images, start with the most recent

  }


  #Filter the data to exclude anything you've already downloaded (or older)

    ndvi_clean_and_new <- ndvi_clean$filterDate(start = paste(as.Date(newest+1),sep = ""),
                                                opt_end = paste(format(Sys.time(), "%Y-%m-%d"),sep = "") ) #I THINK I can just pull the most recent date, and then use this to download everything since then


  # Function to optionally limit the number of layers downloaded at once
  ## Note that this code is placed before the gain and offset adjustment, which removes the metadata needed in the date filtering


    # info <- ndvi_clean_and_new$getInfo()
    # to_download <- unlist(lapply(X = info$features,FUN = function(x){x$properties$`system:index`}))
    # to_download <- gsub(pattern = "_",replacement = "-",x = to_download)
    #
    # if(!is.null(max_layers)){
    #
    #   if(max_layers < length(to_download)){
    #
    #     ndvi_clean_and_new <- ndvi_clean_and_new$filterDate(start = to_download[1],opt_end = to_download[max_layers+1])
    #
    # }}


    #the following code works fine when run interactively, but throws an error when run all at once.  No idea why.

    if(!is.null(max_layers)){

      info <- ndvi_clean_and_new$getInfo()
      to_download <- unlist(lapply(X = info$features,FUN = function(x){x$properties$`system:index`}))
      to_download <- gsub(pattern = "_",replacement = "-",x = to_download)

      if(length(to_download) > max_layers){

        ndvi_clean_and_new <- ndvi_clean_and_new$filterDate(start = to_download[1],
                                                            end = to_download[max_layers+1])

      }


    }# end if maxlayers is not null




  #Adjust gain and offset.  The NDVI layer has a scale factor of 0.0001
    #we further adjust this so that ndvi values are positive to save raster size
    adjust_gain_and_offset <- function(img){

        img$add(10000)$divide(100)$round()

    }


  ndvi_clean_and_new <- ndvi_clean_and_new$map(adjust_gain_and_offset)


  # Check if anything to download

    if(length(ndvi_clean_and_new$getInfo()$features) == 0 ){

      message("Releases are already up to date.")
      return(max(gsub(pattern = "_",replacement = "-",x = released_files$date))) #return the last date that had been done

    }


  #Download layers

  if(length(ndvi_clean_and_new$getInfo()$features) == 1 ){

    # assign name

    file_name <- ndvi_clean_and_new$getInfo()$features[[1]]$properties$`system:index`

    # convert to image

    ndvi_clean_and_new_image <- ndvi_clean_and_new %>%
      ee$ImageCollection$toList(count = 1, offset = 0) %>%
      ee$List$get(0) %>%
      ee$Image()

    # download single image

    tryCatch(expr =
               ee_as_stars(image = ndvi_clean_and_new_image,
                           region = domain,
                           dsn = file.path(temp_directory,file_name),
                           formatOptions = c(cloudOptimized = true),
                           drive_cred_path = json_token
               ),
             error = function(e){message("Captured an error in rgee/earth engine processing of NDVI.")}
    )#trycatch

  }else{

    tryCatch(expr =
               ee_imagecollection_to_local(ic = ndvi_clean_and_new,
                                           region = domain,
                                           dsn = temp_directory,
                                           formatOptions = c(cloudOptimized = true),
                                           drive_cred_path = json_token
                                           #,scale = 463.3127
               ),
             error = function(e){message("Captured an error in rgee/earth engine processing of NDVI.")}
    )

  }#else

    #message("Done downloading NDVI layers for release")

  #Push files to release

    # Get a list of the local files

      local_files <- data.frame(local_filename = list.files(path = temp_directory,
                                                            recursive = TRUE,
                                                            full.names = TRUE))

  # end things if nothing was downloaded

    if(nrow(local_files) == 0){
      message("Nothing downloaded")
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


  message("\nFinished Downloading VIIRS NDVI layers")

  local_files %>%
    dplyr::filter(grepl(pattern = ".tif$",x = local_filename)) %>%
    mutate(date_format = basename(local_filename)) %>%
    mutate(date_format = gsub(pattern = ".tif",replacement = "",x = date_format)) %>%
    mutate(date_format = gsub(pattern = "_",replacement = "-",x = date_format)) %>%
    mutate(date_format = lubridate::as_date(date_format))%>%
    dplyr::select(date_format) -> local_files

  return(as.character(max(local_files$date_format))) # return the date of the latest file that was updated


}

