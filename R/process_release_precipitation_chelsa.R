#' @author Brian Maitner
#' @param input_dir directory where the input files live
#' @param output_dir directory for the output files
#' @param template path to raster file to use as a template for reprojection
#' @param ... Does nothing, but is used in making connections between files in the targets framework
#' @note This function uses method = bilinear at present
process_release_precipitation_chelsa <- function(input_tag = "raw_static",
                                                 output_tag = "processed_static",
                                                 temp_directory = "data/temp/raw_data/precipitation_chelsa/",
                                                 template_release,
                                                 sleep_time = 30,
                                                 ...
                                                 ){

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

      template <- terra::rast(file.path(temp_directory, template_release$file))

  # get input rasters

    raster_list <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                           tag = input_tag) %>%
      filter(grepl(pattern = "CHELSA_prec",
                   x = file_name)) %>%
      filter(grepl(pattern = ".tif",
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

    raster_i <- terra::rast(file.path(temp_directory, raster_list$file_name[i]))

    #Use bilinear for everything

      method <- "bilinear"

      terra::project(x = raster_i,
                     y = template,
                     method = method,
                     filename = file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = "")),
                     overwrite = TRUE)


    if(crs(rast(file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = ""))),proj=TRUE)
       != crs(template,proj = TRUE)){stop("Issue with reprojection")}



    pb_upload(file = file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = "")),
              repo = "AdamWilsonLab/emma_envdata",
              tag = output_tag,
              name = raster_list$file_name[i])

    rm(raster_i)

    file.remove( file.path(temp_directory, raster_list$file_name[i]) )
    file.remove( file.path(temp_directory, paste("temp_",raster_list$file_name[i],sep = "")) )
    gc()

  } #i loop

  #Clear out the folder

  unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
  gc()


  #End functions

  message("Finished processing chelsa precipitation layers")
  return(invisible(NULL))


} #end fx



#################################

