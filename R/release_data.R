library(piggyback)

#' @author Brian Maitner
#' @param data_directory Directory storing the data you want to serve via Github releases
#' @param tag tag for the release
#' @param ... Does nothing but helps with targets connections
#' @note Releases doesn't handle directories, so any directory structure is converted to part of the file name
release_data <- function(data_directory = "data/processed_data/model_data/", tag = "current", ...){



  #Make sure there is a release by attempting to create one.  If it already exists, this will fail
    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                     tag =  tag),
             error = function(e){message("Previous release found")})

  #Get a list of files already released
    released_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                              tag = tag)


  # Get a lost of the local files
    local_files <- data.frame(local_filename = list.files(path = data_directory,
                                recursive = TRUE,
                                full.names = TRUE))

  # Convert local filenames to be releases compatible
    local_files$file_name <-
        sapply(X = local_files$local_filename,
               FUN = function(x){

                 name_i <- gsub(pattern = data_directory,
                                replacement = "",
                                x = x)

                 name_i <- gsub(pattern = "/",
                                replacement = "-",
                                x = name_i)
                 return(name_i)

               })

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


    # We only want time differences of greater than zero (meaning that the local file is more recent) or NA
      merged_info <- merged_info[which(!merged_info$diff_hrs < 0 | is.na(merged_info$diff_hrs)),]

    #Quit if there are no new/updated files to release
      if(nrow(merged_info) == 0){

        message("Releases are already up to date.")
        return(invisible(NULL))


      }


    # loop through and release everything
      for( i in 1:nrow(merged_info)){

        Sys.sleep(0.1) #We need to limit our rate in order to keep Github happy


        pb_upload(file = merged_info$local_filename[i],
                  repo = "AdamWilsonLab/emma_envdata",
                  tag = tag,
                  name = merged_info$file_name[i])




      } # end i loop

  # End
    message("Finished releasing data")
    return(invisible(NULL))


}#end function
