#' @author Brian Maitner
#' @param input_dir directory where the input files live
#' @param output_dir directory for the output files
#' @param template_release path to raster file to use as a template for reprojection
#' @param ... Does nothing, but is used in making connections between files in the targets framework
#' @note This function uses bilinear for continuous variables and nearest neighbor for categorical
process_release_alos <- function(input_tag = "raw_static",
                                 output_tag = "processed_static",
                                 temp_directory = "data/temp/raw_data/alos/",
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

  # get input rasters

    raster_list <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                           tag = input_tag) %>%
      filter(grepl(pattern = "alos_",
                   x = file_name))

    robust_pb_download(file = raster_list$file_name,
                       dest = temp_directory,
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = input_tag,
                       max_attempts = 10,
                       sleep_time = sleep_time)


  # reformat and save each

      for(i in 1:nrow(raster_list)){

        raster_i <- terra::rast(file.path(temp_directory, raster_list$file_name[i]))


        #Use bilinear for everything except landforms

          if(length(grep(pattern = "landforms", x = raster_list$file_name[i])) > 0){

            method <- "near" # uncomment for terra

          }else{

            method <- "bilinear"

          }

      # terra doesn't overwrite, so I have to delete and rename

        terra::project(x = raster_i,
                       y = template,
                       method = method,
                       filename = file.path(temp_directory,
                                            gsub(pattern = ".tif$",
                                                 replacement = ".temp.tif",
                                                 x = raster_list$file_name[i])),
                       overwrite=TRUE)

      # check the projection

        if(terra::crs(rast(file.path(temp_directory,
                                     gsub(pattern = ".tif$",
                                          replacement = ".temp.tif",
                                          x = raster_list$file_name[i]))),
                      proj=TRUE) != terra::crs(template, proj=TRUE)){
          stop("Issue with reprojection")}

      # delete the original

        file.remove(file.path(temp_directory, raster_list$file_name[i]))

        file.rename(from = file.path(temp_directory,
                                     gsub(pattern = ".tif$",
                                          replacement = ".temp.tif",
                                          x = raster_list$file_name[i])),
                    to = file.path(temp_directory, raster_list$file_name[i]))

        # check the new projection

          if(terra::crs(rast(file.path(temp_directory, raster_list$file_name[i])),
                        proj=TRUE) != terra::crs(template, proj=TRUE)){
            stop("Issue with reprojection")}

        # upload the new file

        pb_upload(file = file.path(temp_directory, raster_list$file_name[i]),
                  repo = "AdamWilsonLab/emma_envdata",
                  tag = output_tag,
                  name = raster_list$file_name[i])

        rm(raster_i)

        file.remove(file.path(temp_directory, raster_list$file_name[i]))

        Sys.sleep(sleep_time)


      } #i loop


  #Clear out the folder

    unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)

  #End functions

    message("Finished processing ALOS layers")
    return(invisible(NULL))



} #end fx



#################################


# CSP/ERGo/1_0/Global/ALOS_mTPI
#continuous measure of hills vs valleys -> bilinear
#270


# "CSP/ERGo/1_0/Global/ALOS_CHILI"
#continuous -> bilinear
#90

# 'CSP/ERGo/1_0/Global/ALOS_landforms'
# categorical land classes -> near
#90 meter

# 'CSP/ERGo/1_0/Global/ALOS_topoDiversity'
#continuous -> bilinear
#270 m


