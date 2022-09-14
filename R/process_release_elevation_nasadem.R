#' @author Brian Maitner
#' @param input_tag tag associated with input files
#' @param output_tag tag assocaited with output files
#' @param temp_directory A temporary directory to use for processessing.  Will be cleared out at the end.
#' @param template_release path to raster file to use as a template for reprojection
#' @param ... Does nothing, but is used in making connections between files in the targets framework
#' @note This function uses method = bilinear at present
process_release_elevation_nasadem <- function(input_tag = "raw_static",
                                              output_tag = "processed_static",
                                              temp_directory = "data/temp/raw_data/elevation_nasadem/",
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
                       sleep_time = sleep_time)

    template <- terra::rast(file.path(temp_directory, template_release$file))
    #template <- raster::raster(file.path(temp_directory, template_release$file))


    # get input rasters

    raster_list <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                           tag = input_tag) %>%
      filter(grepl(pattern = "nasadem",
                   x = file_name))

    robust_pb_download(file = raster_list$file_name,
                       dest = temp_directory,
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = input_tag,
                       max_attempts = 10,
                       sleep_time = sleep_time)


    # reformat and save each

    for(i in 1:nrow(raster_list)){

      #raster_i <- raster::raster(file.path(temp_directory, raster_list$file_name[i]))
      raster_i <- terra::rast(file.path(temp_directory, raster_list$file_name[i]))


      #Use bilinear for everything

        method <- "bilinear"

      # raster::projectRaster(from = raster_i,
      #                       to = template,
      #                       method = method,
      #                       filename = file.path(temp_directory, paste("tf_",raster_list$file_name[i],sep = "")),
      #                       overwrite = TRUE
      #                       )

      #Terra is currently having some problems with reading and writing so I've switched back to raster for now
        #ok, oddly enough terra resample seems to fail on github, but work locally.
        #even weirder, terra project seems to work on both

    #temp_i <-
      terra::project(x = raster_i,
                     y = template,
                     method = method,
                     filename = file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = "")),
                     overwrite = TRUE)

      # tf_i <-
      # terra::resample(x = raster_i,
      #                y = template,
      #                method = method,
      #                filename = file.path(temp_directory, paste("tf_",raster_list$file_name[i],sep = "")),
      #                overwrite = TRUE)

      # Double check projection, crs, extent

      if((terra::crs(rast(file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = ""))),proj=TRUE) != terra::crs(template,proj=TRUE))|
         (terra::res(rast(file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = ""))))[1] != terra::res(template)[1])|
         (terra::ext(rast(file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = "")))) != terra::ext(template))){

        message("template crs = ",terra::crs(template,proj=TRUE))

        # message("resampled raster on disk",i," crs = ",terra::crs(rast(file.path(temp_directory, paste("tf_",raster_list$file_name[i],sep = ""))),proj=TRUE))
        # message("resampled raster in memory crs = ",terra::crs(tf_i,proj=TRUE))

        message("reprojected raster in disk",i," crs = ",terra::crs(rast(file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = ""))),proj=TRUE))
        #message("reprojected raster in memory crs = ",terra::crs(temp_i,proj=TRUE))


        stop("Issue with reprojection")

      }


      pb_upload(file = file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = "")),
                repo = "AdamWilsonLab/emma_envdata",
                tag = output_tag,
                name = raster_list$file_name[i])

      # cleanup
        rm(raster_i)
        file.remove( file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = "")) )
        file.remove( file.path(temp_directory, raster_list$file_name[i]) )

        Sys.sleep(sleep_time)


    } #i loop

  # Clear out the folder

    unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
    gc()

  # End functions

    message("Finished processing elevation layer")
    return(as.character(Sys.Date()))


} #end fx



#################################

