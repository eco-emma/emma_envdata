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

  # make a directory if one doesn't exist yet

    if(!dir.exists(dest)){
      dir.create(dest, recursive = TRUE)
    }


  # Get a list of remote files

  release_files <- pb_list(repo = repo,
                           tag = tag)

  # If specifying files, narrow the set of files we're interested in down accordingly

  if(!is.null(file)){

    release_files <- release_files[which(release_files$file_name %in% file),]

  }



  # First attempt bulk download

    pb_download(file = file,
                dest = dest,
                repo = repo,
                tag = tag,
                overwrite = overwrite,
                ...)

    Sys.sleep(sleep_time)


  # validate local files

  bad_files <- NULL

  for(i in 1:nrow(release_files)){


    if(grepl(pattern = ".tif$", x = release_files$file_name[i])){

      if(!tryCatch({terra::rast(file.path(dest, release_files$file_name[i])); TRUE},
                   error = function(e) FALSE)){ bad_files <- c(bad_files,release_files$file_name[i]) }


    }

    # If this is a parquet, check that it loads.  If it throws an error, try again

    if(grepl(pattern = ".parquet", x = release_files$file_name[i])){

      if(!tryCatch({arrow::open_dataset(sources = file.path(dest, release_files$file_name[i])); TRUE},
                   error = function(e) FALSE)){
        bad_files <- c(bad_files,release_files$file_name[i])
      }


    }
  } #end local file checking


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

    #check whether the bulk version is needed

    if(is.null(file)){

      stop("use bulk version")

    }


  # First remove existing files.  Failing to do this makes it harder to distinguish between failed downloads and old files

    if(any(file.exists(file.path(dest, file)) )){

      sapply(X = file.path(dest,file),FUN = function(x){if(file.exists(x)){file.remove(x)}})

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

    Sys.sleep(sleep_time)
    return(dest)


  } # i loop (~ "while")

  stop(paste(file, "File was not downloaded properly"))


}# end robust pb_download function


