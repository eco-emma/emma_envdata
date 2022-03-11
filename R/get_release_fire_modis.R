#MCD64A1 v006

library(rgee)
library(piggyback)

#Below I've modified some existing code to mask any data that isn't land data with sufficient information available
#There are additional filters we can apply using the QA data if we like, but this seems like a good start


#' @param image a QA image
#' @param qa binary numeric (e.g. 111 or 01) corresponding the QA settings to use. Note that this assumes you're starting with bit zero and doesn't handle shifts
#' @return an image resulting from the bitwiseAnd.  This can be transformed into a binary mask using $eq() or similar rgee functions
getQABits_match <- function(image, qa) {

  # Convert binary (character) to integer
  qa <- sum(2^(which(rev(unlist(strsplit(as.character(qa), "")) == 1))-1))

  # Return a mask band image, giving the qa value.
  image$bitwiseAnd(qa)



}


#' @param img A MCD64A1 rgee image,
#' @note this function sets the mask to ignore any date without bits zero and one ==1 (i.e. it ignores data from water and bad data)
MCD64A1_clean <- function(img) {
  # Extract the NDVI band
  fire_values <- img$select("BurnDate")

  # Extract the quality band
  fire_qa <- img$select("QA")

  # Compare the QA scores for the first two bits to a value of 1,1
  quality <- getQABits_match(fire_qa, "11")

  # Create a mask.  Since we only want cells that match both criteria, the bitwise logical for this is 1,1 (yes,yes).
  #The bitwise logical 1,1 translates to an integer value of 3, so we'll mask to everything that equals 3
  quality <- quality$eq(3)

  # Limit our observations to only pixels that have values of 1,1 for the first bits, per the binary "quality" raster (1=good, 0 = bad).
  fire_values$updateMask(quality)

  #Map$addLayer(fire_values)
}


#' @description This function will download fire layers (derived from MODIS 16 day products), skipping any that have been downloaded already.
#' @author Brian Maitner
#' @param temp_directory The directory the fire layers should be saved to prior to releasing, defaults to "data/raw_data/fire_modis/"
#' @param tag tag to be used for the Github release
#' @param domain domain (sf polygon) used for masking
#' @param max_layers the maximum number of layers to download at once.  Set to NULL to ignore.  Default is 50
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy
#' @import rgee
get_release_fire_modis <- function(temp_directory = "data/temp/raw_data/fire_modis/",
                                   tag = "raw_fire_modis",
                                   domain,
                                   max_layers = 50,
                                   sleep_time = 1) {

  # make a directory if one doesn't exist yet

  if(!dir.exists(temp_directory)){
    dir.create(temp_directory, recursive = TRUE)
  }

  #Make sure there is a release by attempting to create one.  If it already exists, this will fail
    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  tag),
             error = function(e){message("Previous release found")})


  # Initialize earth engine (for targets works better if called here)
    ee_Initialize()

  # Load ee image collection

    modis_fire <- ee$ImageCollection("MODIS/006/MCD64A1")

  #Format the domain

    domain <- sf_as_ee(x = domain)
    domain <- domain$geometry()


  # Clean data using QA

    fire_clean <- modis_fire$map(MCD64A1_clean)

  #Get a list of files already released
    released_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                               tag = tag)

    released_files$date <- gsub(pattern = ".tif",
                                replacement = "",
                                x = released_files$file_name)

    released_files <-
      released_files %>%
      filter(file_name != "") %>%
      filter(file_name != "log.csv")


  # check to see if any images have been downloaded already

  if(nrow(released_files) == 0){

    newest <- lubridate::as_date(-1) #if nothing is downloaded, start in 1970

  }else{

    newest <- max(lubridate::as_date(released_files$date)) #if there are images, start with the most recent

  }


  # Filter the data to exclude anything you've already downloaded (or older)
    fire_new_and_clean <- fire_clean$filterDate(start = paste(as.Date(newest+1),sep = ""),
                                                opt_end = paste(format(Sys.time(), "%Y-%m-%d"),sep = "") )


  # Function to optionally limit the number of layers downloaded at once

  if(!is.null(max_layers)){

    info <- fire_new_and_clean$getInfo()
    to_download <- unlist(lapply(X = info$features,FUN = function(x){x$properties$`system:index`}))
    to_download <- gsub(pattern = "_",replacement = "-",x = to_download)

    if(length(to_download) > max_layers){

      fire_new_and_clean <- fire_new_and_clean$filterDate(start = to_download[1],
                                                          opt_end = to_download[max_layers+1])

    }


  }


  # Check if anything to download

    if(length(fire_new_and_clean$getInfo()$features) == 0 ){

      message("Releases are already up to date.")
      return(invisible(NULL))

    }

  # Download

    ee_imagecollection_to_local(ic = fire_new_and_clean,
                                region = domain,
                                dsn = temp_directory)


  #Push files to release

    # Get a lost of the local files
      local_files <- data.frame(local_filename = list.files(path = temp_directory,
                                                            recursive = TRUE,
                                                            full.names = TRUE))


      # Convert local filenames to be releases compatible
      local_files$file_name <-
        sapply(X = local_files$local_filename,
               FUN = function(x){

                 name_i <- gsub(pattern = temp_directory,
                                replacement = "",
                                x = x)

                 name_i <- gsub(pattern = "/",
                                replacement = "",
                                x = name_i)
                 return(name_i)

               })

    # Release local files

      # Get timestamps on local files
      local_files$last_modified <-
        Reduce(c, lapply(X = local_files$local_filename,
                         FUN =  function(x) {
                           file.info(x)$mtime})
        )


      # Figure out which files DON'T need to be released

            merged_info <- merge(x = released_files,
                                 y = local_files,
                                 all = TRUE)

            merged_info$diff_hrs <- difftime(time2 = merged_info$timestamp,
                                             time1 = merged_info$last_modified,
                                             units = "hours")

            merged_info <- merged_info[merged_info$file_name != "",]



      #

      # We only want time differences of greater than zero (meaning that the local file is more recent) or NA
        merged_info <- merged_info[which(!merged_info$diff_hrs < 0 | is.na(merged_info$diff_hrs)),]

      # Also toss anything that doesn't need to be uploaded (because doesn't exist locally)
        merged_info <- merged_info[which(!is.na(merged_info$local_filename)),]


      # Quit if there are no new/updated files to release
        if(nrow(merged_info) == 0){

          message("Releases are already up to date.")
          return(invisible(NULL))


        }

      # loop through and release everything
        for( i in 1:nrow(merged_info)){

          Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy


          pb_upload(file = merged_info$local_filename[i],
                    repo = "AdamWilsonLab/emma_envdata",
                    tag = tag,
                    name = merged_info$file_name[i])




        } # end i loop


  # Delete temp files
    unlink(x = gsub(pattern = "/$",replacement = "",x = temp_directory), #sub used to delete any trailing slashes, which interfere with unlink
           recursive = TRUE)

  # End
    message("\nFinished download MODIS fire layers")
    return(invisible(NULL))



} #end fx


