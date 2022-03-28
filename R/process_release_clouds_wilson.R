#' @author Brian Maitner
#' @param input_dir directory where the input files live
#' @param output_dir directory for the output files
#' @param template path to raster file to use as a template for reprojection
#' @param ... Does nothing, but is used in making connections between files in the targets framework
#' @note This function uses method = bilinear at present
process_release_clouds_wilson <- function(input_tag = "raw_static",
                                          output_tag = "processed_static",
                                          temp_directory = "data/temp/raw_data/clouds_wilson/",
                                          template_release,
                                          sleep_time = 30,
                                          ...){



  #  #Ensure directory is empty if it exists

    if(dir.exists(temp_directory)){
      unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
    }

  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }



  # get template raster

    robust_pb_download(file = template_release$file,
                       dest = temp_directory,
                       repo = template_release$repo,
                       tag = template_release$tag,
                       max_attempts = 10,
                       sleep_time = 10)

    #Pause to keep below the rate limit
      Sys.sleep(sleep_time)

    #template <- terra::rast(file.path(temp_directory, template_release$file))
    template <- raster::raster(file.path(temp_directory, template_release$file))


    # get input rasters

      raster_list <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                             tag = input_tag) %>%
        filter(grepl(pattern = "MODCF",
                     x = file_name))

      robust_pb_download(file = raster_list$file_name,
                         dest = temp_directory,
                         repo = "AdamWilsonLab/emma_envdata",
                         tag = input_tag,
                         max_attempts = 10,
                         sleep_time = sleep_time)

      #Pause to keep below the rate limit
        Sys.sleep(sleep_time)


  #reformat and save each

      for(i in 1:nrow(raster_list)){

        raster_i <- raster::raster(file.path(temp_directory, raster_list$file_name[i]))
        #raster_i <- terra::rast(file.path(temp_directory, raster_list$file_name[i]))


        #Use bilinear for everything

          method <- "bilinear"


        raster::projectRaster(from = raster_i,
                              to = template,
                              method = method,
                              filename = file.path(temp_directory, raster_list$file_name[i],sep = ""),
                              overwrite=TRUE
        )

        #Terra is currently having some problems with reading and writing so I've switched back to raster for now
        # terra::project(x = raster_i,
        #                y = template,
        #                method = method,
        #                filename = file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = "")),
        #                overwrite = TRUE)


        pb_upload(file = file.path(temp_directory, raster_list$file_name[i]),
                  repo = "AdamWilsonLab/emma_envdata",
                  tag = output_tag,
                  name = raster_list$file_name[i])

        rm(raster_i)

        file.remove(file.path(temp_directory, raster_list$file_name[i]))

        #Pause to keep below the rate limit
          Sys.sleep(sleep_time)


      } #i loop

  #Clear out the folder

    unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)

  #End functions

    message("Finished processing cloud layers")
    return(invisible(NULL))


} #end fx



#################################

