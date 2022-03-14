#' @author Brian Maitner
#' @description This function converts rasters containing burn dates (in UNIX date format) to rasters containing the most recent burn date (also in UNIX format)

process_release_burn_date_to_last_burned_date <- function(input_tag = "processed_fire_dates",
                                                          output_tag = "processed_most_recent_burn_dates",
                                                          temp_directory_input = "data/temp/processed_data/fire_dates/",
                                                          temp_directory_output = "data/temp/processed_data/most_recent_burn_dates/",
                                                          sleep_time = 1,
                                                          ...){

  #make folder if needed

    if(!dir.exists(temp_directory_input)){dir.create(temp_directory_input, recursive = TRUE)}

    if(!dir.exists(temp_directory_output)){dir.create(temp_directory_output, recursive = TRUE)}

  # clear out any accidental remnants

    file.remove(list.files(temp_directory_input,full.names = TRUE))
    file.remove(list.files(temp_directory_output,full.names = TRUE))

  #Make sure there is a release by attempting to create one.  If it already exists, this will fail

    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  input_tag),
             error = function(e){message("Previous release found")})

    Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

  #Make sure there is a release by attempting to create one.  If it already exists, this will fail

    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  output_tag),
             error = function(e){message("Previous release found")})

    Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

  # get files

    input_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                            tag = input_tag) %>%
      filter(file_name != "")

    Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

    output_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                             tag = output_tag)%>%
      filter(file_name != "")

    Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

    # prune input files to only ones not in output

    input_files <- input_files[which(!input_files$file_name %in% output_files$file_name),]


    if(nrow(input_files) == 0) {
      message("Finished processing fire day-of-year to date")
      return(invisible(NULL))
    }


  #Ensure input files are properly ordered

    input_files %>%
      mutate(date = file_name) %>%
      mutate(date = gsub(pattern = ".tif",replacement = "",x = .$date)) %>%
      mutate(date = gsub(pattern = "/",replacement = "",x = .$date)) %>%
      mutate(date = as_date(date)) %>%
      mutate(number = as.numeric(date)) %>%
      arrange(number) -> input_files


  #Ensure output files are properly ordered

    output_files %>%
      mutate(date = file_name) %>%
      mutate(date = gsub(pattern = ".tif",replacement = "",x = .$date)) %>%
      mutate(date = gsub(pattern = "/",replacement = "",x = .$date)) %>%
      mutate(date = as_date(date)) %>%
      mutate(number = as.numeric(date)) %>%
      arrange(number) -> output_files


  #Prune any files that have been already done
    input_files <- input_files[which(!input_files$file_name %in% output_files$file_name),]

  #If all input has been processed, skip

    if(nrow(input_files) == 0) {
      message("Finished processing fire dates")
      return(invisible(NULL))
    }


  #Start with input raster 1 or the last output raster.
  if(nrow(output_files) == 0){

      robust_pb_download(file = input_files$file_name[1],
                         dest = temp_directory_input,
                         repo = "AdamWilsonLab/emma_envdata",
                         tag = input_tag,
                         overwrite = TRUE,
                         max_attempts = 10,
                         sleep_time = 2)


    previous_raster <- raster(file.path(temp_directory_input,input_files$file_name[1]))

  }else{


    robust_pb_download(file = output_files$file_name[1],
                       dest = temp_directory_output,
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = output_tag,
                       overwrite = TRUE,
                       max_attempts = 10,
                       sleep_time = 2)

    previous_raster <- raster(file.path(temp_directory_output,
                                        output_files$file_name[nrow(output_files)]))


  }

  #Iterate through all rasters, keeping a running tally of most recent burn
  for(i in 1:nrow(input_files)){

    #Get raster i
    robust_pb_download(file = input_files$file_name[i],
                       dest = temp_directory_input,
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = input_tag,
                       overwrite = TRUE,
                       max_attempts = 10,
                       sleep_time = 2)


    raster_i <- raster(file.path(temp_directory_input,input_files$file_name[i]))

    max_i <- max(stack(raster_i,previous_raster))

    #save output
      raster::writeRaster(x = max_i,
                          filename = file.path(temp_directory_output,input_files$file_name[i]),
                          overwrite=TRUE)

      pb_upload(file = file.path(temp_directory_output,input_files$file_name[i]),
                repo = "AdamWilsonLab/emma_envdata",
                tag = output_tag,
                name = input_files$file_name[i],
                overwrite = TRUE)

      Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

    #Set previous raster
      previous_raster <- max_i

    #Delete old rasters
      file.remove(file.path(temp_directory_output,input_files$file_name[i]))
      file.remove(file.path(temp_directory_input,input_files$file_name[i]))

  }#for loop

  # Delete temp files

    unlink(x = gsub(pattern = "/$",replacement = "",x = temp_directory_input), #sub used to delete any trailing slashes, which interfere with unlink
           recursive = TRUE)

    unlink(x = gsub(pattern = "/$",replacement = "",x = temp_directory_output), #sub used to delete any trailing slashes, which interfere with unlink
           recursive = TRUE)


  #End function

    message("Finished processing fire dates")
    return(invisible(NULL))


}#end fx
