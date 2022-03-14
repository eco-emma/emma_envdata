#' @description Download using piggyback but make sure it worked
#' @author Brian Maitner
#' @param file as in pb_download
#' @param dest as in pb_download
#' @param repo as in pb_download
#' @param tag as in pb_download
#' @param overwrite as in pb_download
#' @param max_attempts The maximum number of attempts before giving up
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy
robust_pb_download <- function(file, dest, repo, tag, overwrite = TRUE, max_attempts = 10, sleep_time = 1, ...){

  if(is.null(file)){

    robust_pb_download_bulk(dest = dest,
                            repo = repo,
                            tag = tag,
                            overwrite = overwrite,
                            max_attempts = max_attempts,
                            sleep_time = sleep_time,...)

    return(dest)

  }else{

    robust_pb_download_solo(file = file,
                            dest = dest,
                            repo = repo,
                            tag = tag,
                            overwrite = overwrite,
                            max_attempts = max_attempts,
                            sleep_time = sleep_time,...)

    return(dest)


  }


}# end robust pb_download function

##############################################

#' @description Oddly enough, this function is both a wrapper for robust_pb_download and an internal function therof.
robust_pb_download_bulk <- function(dest, repo, tag, overwrite = TRUE, max_attempts = 10, sleep_time = 1, ...){

  # make a directory if one doesn't exist yet

      if(!dir.exists(dest)){
        dir.create(dest, recursive = TRUE)
      }


  # First attempt bulk download

    pb_download(dest = dest,
                repo = repo,
                tag = tag,
                overwrite = overwrite)

  #Get a list of local files

    local_files <- list.files(dest)

  # Get a list of remote files

    release_files <- pb_list(repo = repo,
                             tag = tag)

  # validate local files

    bad_files <- NULL

    for(i in 1:length(local_files)){


      if(grepl(pattern = ".tif$", x = local_files[i])){

        if(!tryCatch({terra::rast(file.path(dest, local_files[i])); TRUE},
                     error = function(e) FALSE)){ bad_files <- c(bad_files,local_files[i]) }


      }

      # If this is a parquet, check that it loads.  If it throws an error, try again

      if(grepl(pattern = ".parquet", x = local_files[i])){

        if(!tryCatch({arrow::open_dataset(sources = file.path(dest, local_files[i])); TRUE},
                     error = function(e) FALSE)){
          bad_files <- c(bad_files,local_files[i])
          }


      }
    } #end local file checking

  #check for missing files

   bad_files  <- c(bad_files, release_files$file_name[which(!release_files$file_name %in% local_files)])

  #if everything looks ok, send a message and end

   if(length(bad_files)==0){

     message("All files appear to have downloaded correctly")
     return(dest)

   }


  # Next, attempt to download broken files carefully, checking if it was indeed downloaded



   for( i in 1:length(bad_files)){

     message(paste("Attempting to correct erroneous pb_download ", i , "of", length(bad_files)))

     robust_pb_download_solo(file = bad_files[i],
                        dest = dest,
                        repo = repo,
                        tag = tag,
                        overwrite = TRUE,
                        max_attempts = max_attempts,
                        sleep_time = sleep_time,
                        ...)


   }

  message("File downloads complete")
  return(dest)


}# end robust pb_download function

########################################################
robust_pb_download_solo <- function(file, dest, repo, tag, overwrite = TRUE, max_attempts = 10, sleep_time = 1, ...){

  if(is.null(file)){
    stop("use bulk version")

  }


  # First remove existing files.  Failing to do this makes it harder to distinguish between failed downloads and old files

  if(file.exists(file.path(dest, file)) ){

    file.remove(file.path(dest, file))

  }


  # Next, attempt to download file, checking if it was indeed downloaded

  for( i in 1:max_attempts){

    #Try to download file

    pb_download(file = file,
                dest = dest,
                repo = repo,
                tag = tag,
                overwrite = overwrite,
                ...)

    # Check whether file exists

    file_present  <- file.exists(file.path(dest, file))

    # If file isn't present, try again
    if(!file_present){
      Sys.sleep(sleep_time)
      next
    }

    # If this is a tif, check that it loads.  If it throws an error, try again

    if(grepl(pattern = ".tif$", x = file)){

      if(!tryCatch({terra::rast(file.path(dest, file)); TRUE}, error = function(e) FALSE)){
        Sys.sleep(sleep_time)
        next
      }

    }

    # If this is a parquet, check that it loads.  If it throws an error, try again

    if(grepl(pattern = ".parquet", x = file)){

      if(!tryCatch({arrow::open_dataset(sources = file.path(dest, file)); TRUE}, error = function(e) FALSE)){
        Sys.sleep(sleep_time)
        next
      }

    }

    # If the file has gotten this far, it seems good and we can move on

    return(dest)


  } # i loop (~ "while")

  stop(paste(file, "File was not downloaded properly"))


}# end robust pb_download function


