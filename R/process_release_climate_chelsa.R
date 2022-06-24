#' @author Brian Maitner
#' @param input_tag directory where the input files live
#' @param output_tag directory for the output files
#' @param template_release info returned by get_release_template_raster()
#' @param ... Does nothing, but is used in making connections between files in the targets framework
#' @note This function uses bilinear for continuous variables and nearest neighbor for categorical
process_release_climate_chelsa <- function(input_tag = "raw_static",
                                           output_tag = "processed_static",
                                           temp_directory = "data/temp/raw_data/climate_chelsa/",
                                           template_release,
                                           sleep_time = 30,
                                           ...){

  # Ensure directory is empty

    if(dir.exists(temp_directory)){
      unlink(x = file.path(temp_directory), recursive =  TRUE, force = TRUE)
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

  # get input rasters

    files <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                         tag = input_tag) %>%
      filter(grepl(pattern = "CHELSA_bio",x = file_name))

  #Download files

    robust_pb_download(file = files$file_name,
                       dest = temp_directory,
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = input_tag,
                       max_attempts = 10,
                       sleep_time = sleep_time)



  #reformat and save each

  for(i in 1:nrow(files)){

      raster_i <- terra::rast(file.path(temp_directory, files$file_name[i]))

    #Use bilinear for everything

      method <- "bilinear"

      terra::project(x = raster_i,
                     y = template,
                     method = method,
                     filename = file.path(temp_directory,paste("reproj_",files$file_name[i],sep = "")),
                     overwrite = TRUE)

      rm(raster_i)

      file.remove(file.path(temp_directory,files$file_name[i]))

      file.rename(from = file.path(temp_directory,paste("reproj_",files$file_name[i],sep = "")),
                  to = file.path(temp_directory,files$file_name[i]))



  } #i loop

  #Upload files

    pb_upload(file = file.path(temp_directory,files$file_name),
              repo = "AdamWilsonLab/emma_envdata",
              tag = output_tag)

  #Clean up

    unlink(x = file.path(temp_directory), recursive =  TRUE, force = TRUE)



  #End functions

  message("Finished processing chelsa climate layers")
  return(invisible(NULL))


} #end fx



#################################

