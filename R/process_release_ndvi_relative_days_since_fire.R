#' @author Brian Maitner
#' @description The goal of this script is to deal with the mismatch between MODIS fire and NDVI dates,
#' producing a time-since-fire raster that relative to a paired with an NDVI raster

library(lubridate)
library(raster)

process_release_ndvi_relative_days_since_fire <- function(temp_input_ndvi_date_folder = "data/temp/raw_data/ndvi_dates_modis/",
                                                  temp_input_fire_date_folder = "data/temp/processed_data/most_recent_burn_dates/",
                                                  temp_fire_output_folder = "data/temp/processed_data/ndvi_relative_time_since_fire/",
                                                  input_fire_dates_tag = "processed_most_recent_burn_dates",
                                                  input_modis_dates_tag = "raw_ndvi_dates_modis",
                                                  output_tag = "processed_ndvi_relative_days_since_fire",
                                                  sleep_time = 5,
                                                  ...){

  #Make folder if needed
    if(! dir.exists(temp_fire_output_folder)){ dir.create(temp_fire_output_folder,
                                                     recursive = TRUE) }

    if(! dir.exists(temp_input_fire_date_folder)){ dir.create(temp_input_fire_date_folder,
                                                     recursive = TRUE) }

    if(! dir.exists(temp_input_ndvi_date_folder)){ dir.create(temp_input_ndvi_date_folder,
                                                     recursive = TRUE) }


  #Make sure releases exist

      #Make sure there is a release by attempting to create one.  If it already exists, this will fail

      tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                       tag =  input_modis_dates_tag),
               error = function(e){message("Previous release found")})

      Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

      tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                       tag =  input_fire_dates_tag),
               error = function(e){message("Previous release found")})

      Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

      tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                       tag =  output_tag),
               error = function(e){message("Previous release found")})

      Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy


  #Get a list of files in the releases

    fire_files <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                          tag = input_fire_dates_tag) %>%
                          filter(file_name != "")

    ndvi_files <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                          tag = input_modis_dates_tag) %>%
                          filter(file_name != "")%>%
                          filter(file_name != "log.csv")




  fire_files <-
  fire_files %>%
    mutate(date = file_name) %>%
    mutate(date = gsub(pattern = ".tif",replacement = "",x = .$date)) %>%
    mutate(date = gsub(pattern = "/",replacement = "",x = .$date)) %>%
    mutate(date = as_date(date)) %>%
    mutate(number = as.numeric(date)) %>%
    mutate(end_date = ceiling_date(x = date,unit = "month") %m-% days(1)) %>%
    mutate(end_number = as.numeric(end_date)) %>%
    arrange(number)

  ndvi_files <-
  ndvi_files %>%
    mutate(date = file_name) %>%
    mutate(date = gsub(pattern = ".tif",replacement = "",x = .$date)) %>%
    mutate(date = gsub(pattern = "/",replacement = "",x = .$date)) %>%
    mutate(date = as_date(date)) %>%
    mutate(number = as.numeric(date)) %>%
    mutate(end_date = ceiling_date(x = date,unit = "month") %m-% days(1)) %>%
    mutate(end_number = as.numeric(end_date)) %>%
    arrange(number)


  #Get a list of fire stuff that has been processed, and exclude anything that doesn't need to be done

    processed_files <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                          tag = output_tag) %>%
      filter(file_name != "")%>%
      filter(file_name != "log.csv")

    ndvi_files <- ndvi_files[which(!ndvi_files$file_name %in% processed_files$file_name),]

  #Iterate through each NDVI layer (that hasn't been processed) and generate a corresponding set of fire dates

  for(i in 1:nrow(ndvi_files)){

    #Get ndvi raster and metadata

      robust_pb_download(file = ndvi_files$file_name[i],
                         dest = temp_input_ndvi_date_folder,
                         repo = "AdamWilsonLab/emma_envdata",
                         tag = input_modis_dates_tag,
                         overwrite = TRUE,
                         max_attempts = 10,
                         sleep_time = sleep_time)

    ndvi_raster_i <- raster(file.path(temp_input_ndvi_date_folder,ndvi_files$file_name[i]))

    start_date_i <- ndvi_files$date[i]
    start_date_numeric_i <- ndvi_files$number[i]
    end_date_numeric_i <- ndvi_files$number[i] + 16

    #Get the next fire date raster that occurs after
      suppressWarnings(fire_index <- min(which(fire_files$end_number >= end_date_numeric_i)))

    #If there isn't a next fire layer, stop processing
    if(is.infinite(fire_index)) {
      message("Done processing NDVI dates")
      return(invisible(NULL))
    }

    #Make a "time since last fire" layer

    #Grab next fire layer(downloading if needed)

      if(!file.exists(file.path(temp_input_fire_date_folder, fire_files$file_name[fire_index]))){
        robust_pb_download(file = fire_files$file_name[fire_index],
                           dest = temp_input_fire_date_folder,
                           repo = "AdamWilsonLab/emma_envdata",
                           tag = input_fire_dates_tag,
                           overwrite = TRUE,
                           max_attempts = 10,
                           sleep_time = sleep_time)

      }

    fire_raster_2_i <- raster(file.path(temp_input_fire_date_folder,fire_files$file_name[fire_index]))
    fire_2_start_date <- fire_files$number[fire_index]

    #Grab previous fire layer, or make an empty one if needed

      if(fire_index > 1){


        # download the file if needed
        if(!file.exists(file.path(temp_input_fire_date_folder,fire_files$file_name[fire_index-1]))){

            robust_pb_download(file = fire_files$file_name[fire_index - 1],
                               dest = temp_input_fire_date_folder,
                               repo = "AdamWilsonLab/emma_envdata",
                               tag = input_fire_dates_tag,
                               overwrite = TRUE,
                               max_attempts = 10,
                               sleep_time = sleep_time)

        }

        fire_raster_1_i <- raster(file.path(temp_input_fire_date_folder,fire_files$file_name[fire_index-1]))
        fire_1_start_date <- fire_files$number[fire_index-1]

      }else{

        fire_raster_1_i <- setValues(fire_raster_2_i,values = 0)

      }

    # Make a fire layer that doesn't include anything after the end of the ndvi
    # This code replaces any fire dates that occur after the NDVI measurement
    # with the dates from the previous fire layer

    fire_raster_i <- fire_raster_2_i
    fire_raster_i[fire_raster_2_i > ndvi_raster_i] <- fire_raster_1_i[fire_raster_i > ndvi_raster_i]

    #plot(fire_raster_i)
    #plot(fire_raster_2_i - fire_raster_1_i  )
      rm(fire_raster_1_i,fire_raster_2_i)

    #Set fire dates of zero to NA (since its unlikely any occurred on precisely that date)
      fire_raster_i[fire_raster_i == 0] <- NA

    # Generate days since last fire (NA where no fire recorded)

    output_i <- ndvi_raster_i - fire_raster_i

    #Set name of output, save to a output folder

    names(output_i) <- gsub(pattern = "-",
                            replacement = "_",
                            x = ndvi_files$date[i])

    writeRaster(x = output_i,
                filename = file.path(temp_fire_output_folder, ndvi_files$file_name[i]))

    #release the saved filed

      pb_upload(file = file.path(temp_fire_output_folder, ndvi_files$file_name[i]),
                repo = "AdamWilsonLab/emma_envdata",
                tag = output_tag,
                name = ndvi_files$file_name[i],
                overwrite = TRUE)


    #Delete any files that are no longer needed


    file.remove(file.path(temp_fire_output_folder,ndvi_files$file_name[i]))

      if(fire_index > 2){

        file.remove(file.path(temp_input_fire_date_folder,fire_files$file_name[fire_index-2]))

      }


  }#for ndvi loop

    unlink(x = file.path(temp_fire_output_folder),recursive = TRUE)
    unlink(x = file.path(temp_input_fire_date_folder),recursive = TRUE)
    unlink(x = file.path(temp_input_ndvi_date_folder),recursive = TRUE)


  #End function
  message("Done processing NDVI dates")
  return(invisible(NULL))


}


