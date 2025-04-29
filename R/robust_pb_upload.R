#' @description Download using piggyback but make sure it worked
#' @author Brian Maitner
#' @param file as in pb_upload
#' @param repo as in upload
#' @param tag as in pb_upload
#' @param max_attempts The maximum number of attempts before giving up
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy
#' @param temp_directory Directory used to download files temporarily to see if they were uploaded properly.
#' @param name As in pb_upload.  Default, NULL, uses the filename.
#' @param overwrite SHould release be overwritten? Default is TRUE
#' @note This version forces overwriting of the files in the release, and uses a lot of GH queries.  Best reserved for cases you expect to fail or which are critical.
robust_pb_upload <- function(file,
                             repo="AdamWilsonLab/emma_model",
                             tag,
                             max_attempts = 10,
                             sleep_time = 1,
                             temp_directory = "data/temp/pb_test",
                             name = NULL,
                             overwrite = TRUE,
                             ...){



  # check/create release

    assets <- pb_list(repo = repo)

    if(!tag %in% assets$tag){

      caught<-tryCatch(pb_new_release(repo = repo,
                                      tag = tag),
                       error = function(e) e)

      if(exists("caught")){rm(caught)}

    }


  # create dir if needed

    if(!dir.exists(temp_directory)){dir.create(temp_directory,recursive = TRUE)}


  # loop through files


  for(i in 1:length(file)){

    message("attempting to upload file ", i, " of ",length(file),": ",file[i])

    attempts <- 1

    while(attempts < max_attempts){

      message("attempt ", attempts, " of ", max_attempts)


      #try to upload the file

      pb_upload(file = file[i],
                repo = repo,
                tag = tag,
                overwrite = overwrite,
                name = name)

      # as far as I can tell, the only way to figure out if an upload was broken is that the file in question is shown on the repo but can't be downloaded

      #check if the file was properly uploaded

      repo_status <- pb_list(repo = repo,tag = tag)

      if(basename(file[i]) %in% repo_status$file_name){

        file_uploaded <- TRUE

      }else{

          file_uploaded <- FALSE

          }

      #if the file wasn't even uploaded, skip to the next attempt without trying to downloaded

        if(!file_uploaded){

          attempts <- attempts+1

          next

        }

      # attempt to download the file

        pb_download(file = basename(file[i]),
                    dest = temp_directory,
                    repo = repo,
                    tag = tag)

     # record if file was successfully downloaded

      if(file.exists(file.path(temp_directory,basename(file[i])))){

        file_downloaded <- TRUE

      }else{

          file_downloaded <- FALSE

          }

    # if file was uploaded break out of the loop

      if(file_uploaded & file_downloaded){

        file.remove(file.path(temp_directory,basename(file[i])))

        message("File upload appears successful")

        break

        }

    # otherwise, increment

      attempts = attempts+1

    # and pause
      Sys.sleep(sleep_time)

    #message if failed
      if(attempts >= max_attempts){
        message("Uploading file ",file[i] ," failed. Giving up.")

      }

    }#while loop
  }# i file loop

  return(as.character(Sys.Date()))

}

##########################
