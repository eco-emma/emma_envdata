
#' @description to check the projection of MODIS products downloaded from rgee
#' @author Brian Maitner
#' @param temp_directory The directory the layers should be temporarily saved in
#' @param tag tag associated with the Github release
#' @param max_layers the maximum number of layers to correct at once.  Default (NULL) is to use all.
#' @param sleep_time amount of time to pause after using pb_upload/download.  Used to keep Git happy
#' @param verbose.  More messages are shown
process_fix_modis_release_projection <-
  function(temp_directory,
           tag,
           max_layers = NULL,
           sleep_time = 0.1,
           verbose = TRUE,
           ...){

    # specify the correct projection
      nasa_proj <- "+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +R=6371007.181 +units=m +no_defs"


    # get a list of released files
      released_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                                 tag = tag)

    #  #Ensure directory is empty if it exists

      if(dir.exists(temp_directory)){
        unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
      }


    # make a directory if one doesn't exist yet

      if(!dir.exists(temp_directory)){
        dir.create(temp_directory, recursive = TRUE)
      }

    #set up a  change log if needed

      if("log.csv" %in% released_files$file_name){

        robust_pb_download(file =  "log.csv",
                      dest = temp_directory,
                      repo = "AdamWilsonLab/emma_envdata",
                      tag = tag,
                      overwrite = TRUE,
                      max_attempts = 10,
                      sleep_time = sleep_time)


      }else{

        suppressWarnings(expr =
                           cbind("file","original_proj","assigned_proj") %>%
                           write.table(x = .,
                                       file = file.path(temp_directory,"log.csv"),
                                       append = FALSE,
                                       col.names = FALSE,
                                       row.names=FALSE,
                                       sep = ",")
        )


      }

    #Get a list of raster that haven't been fixed by comparison with the log

      rasters <- released_files$file_name[grep(x = released_files$file_name, pattern = ".tif")]

      log <- read.csv(paste(temp_directory, "log.csv", sep = ""))

      rasters <- rasters[which(!rasters %in% log$file)]

      if(!is.null(max_layers)){

        if(max_layers < length(rasters)){

          rasters <- rasters[1:max_layers]

        }



      }


    # check whether there is anything left to fix

      if(length(rasters) == 0){

        message(paste("Finished updating ",tag," projections",sep = ""))

        return(
          released_files %>%
            filter(tag == tag) %>%
            dplyr::select(file_name) %>%
            filter(file_name != "") %>%
            filter(grepl(pattern = ".tif$", x = file_name)) %>%
            mutate(date_format = gsub(pattern = ".tif",
                                      replacement = "",
                                      x = file_name))%>%
            mutate(date_format = gsub(pattern = "_", replacement = "-",
                                      x = date_format)) %>%
            dplyr::pull(date_format) %>%
            max()
        )


      }



    #iterate and fix
    for(i in 1:length(rasters)){

      if(verbose){message("Checking raster ", i, " of ", length(rasters))}

      # download ith raster

        robust_pb_download(file = rasters[i],
                    dest = temp_directory,
                    repo = "AdamWilsonLab/emma_envdata",
                    tag = tag,
                    overwrite = TRUE,
                    max_attempts = 10,
                    sleep_time = sleep_time)

        Sys.sleep(sleep_time)

      # load ith raster

        rast_i <- terra::rast(x = file.path(temp_directory,rasters[i]))

      # get the projection

        original_proj <- crs(rast_i, proj = TRUE)

      # check whether the raster matches the correct projection
      if(!identical(nasa_proj, original_proj)){

        message("Detected error in MODIS projection for raster ",rasters[i],
                " correcting and logging the change")

        crs(rast_i) <- nasa_proj

        # write a new raster with a different name

          terra::writeRaster(x = rast_i,
                             filename = gsub(pattern = ".tif$",
                                             replacement =".temp.tif",
                                             x =  file.path(temp_directory,rasters[i])),
                             filetype="GTiff",
                             overwrite = TRUE)

        # delete old raster

          unlink(file.path(temp_directory,rasters[i]))


        # update new name

          file.rename(from = gsub(pattern = ".tif$",
                                replacement =".temp.tif",
                                x =  file.path(temp_directory,rasters[i])),
                    to = file.path(temp_directory, rasters[i]))

        #log the change


        data.frame(file = rasters[i],
                   original_proj = original_proj,
                   assigned_proj = nasa_proj) %>%

          write.table(x = .,
                      file = file.path(temp_directory,"log.csv"),
                      append = TRUE,
                      col.names = FALSE,
                      row.names=FALSE,
                      sep = ",")

        # push the updated raster

          # pb_upload(file = file.path(temp_directory,rasters[i]),
          #           repo = "AdamWilsonLab/emma_envdata",
          #           tag = tag,
          #           name = rasters[i], overwrite = TRUE)

          robust_pb_upload(file = file.path(temp_directory,rasters[i]),
                    repo = "AdamWilsonLab/emma_envdata",
                    tag = tag,
                    name = rasters[i],
                    overwrite = TRUE,
                    sleep_time = sleep_time)

          #Sys.sleep(sleep_time)



        # push the updated log

          # pb_upload(file = file.path(temp_directory,"log.csv"),
          #           repo = "AdamWilsonLab/emma_envdata",
          #           tag = tag)
          #
          # Sys.sleep(sleep_time)

          robust_pb_upload(file = file.path(temp_directory,"log.csv"),
                    repo = "AdamWilsonLab/emma_envdata",
                    tag = tag,
                    sleep_time = sleep_time)


        # Delete the new raster

          unlink(file.path(temp_directory,rasters[i]))

      }else{

        #if the projection is correct, log it

        if(verbose){message("Projection for raster ", rasters[i], "looks correct")}

        data.frame(file = rasters[i],
                   original_proj = original_proj,
                   assigned_proj = nasa_proj) %>%

          write.table(x = .,
                      file = file.path(temp_directory,"log.csv"),
                      append = TRUE,
                      col.names = FALSE,
                      row.names=FALSE,
                      sep = ",")

          # pb_upload(file = file.path(temp_directory,"log.csv"),
          #           repo = "AdamWilsonLab/emma_envdata",
          #           tag = tag)
          #
          # Sys.sleep(sleep_time)

        robust_pb_upload(file = file.path(temp_directory,"log.csv"),
                         repo = "AdamWilsonLab/emma_envdata",
                         tag = tag,
                         name = NULL,
                         sleep_time = sleep_time)


          unlink(file.path(temp_directory,rasters[i]))


      }

    } #for i rasters loop

    # Cleanup and end

      # Delete temp files
        unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)

      # Finish up

        message(paste("Finished updating ",tag," projections",sep = ""))

        return(
          rasters |>
            gsub(pattern = ".tif", replacement = "") |>
            gsub(pattern = "_",replacement = "-") |>
            max()
          )





} # end function

###########################


