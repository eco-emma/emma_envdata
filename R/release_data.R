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
  current_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                            tag = tag)


  # take a look at the available files
    release_files <- list.files(path = data_directory,
                                recursive = TRUE,
                                full.names = TRUE)

    # loop through and release everything
      for( i in 1:length(release_files)){

        Sys.sleep(0.01) #We need to limit our rate in order to keep Github happy

        file_i <- release_files[i]

        name_i <- gsub(pattern = data_directory,
                       replacement = "",
                       x = file_i)

        name_i <- gsub(pattern = "/",
                       replacement = "-",
                       x = name_i)



        pb_upload(file = file_i,
                  repo = "AdamWilsonLab/emma_envdata",
                  tag = "current",
                  name = name_i)




      } # end i loop

  # End
    message("Finished releasing data")
    return(invisible(NULL))


}#end function
