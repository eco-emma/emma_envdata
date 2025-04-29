#' @author Brian Maitner
#' @description The goal of this script is to deal with the mismatch between MODIS fire and NDVI dates,
#' producing a time-since-fire raster that relative to a paired with an NDVI raster

library(lubridate)
library(tidyverse)
library(piggyback)

process_release_ndvi_relative_days_since_fire <- function(temp_input_ndvi_date_folder = "data/temp/raw_data/ndvi_dates_modis/",
                                                  temp_input_fire_date_folder = "data/temp/processed_data/most_recent_burn_dates/",
                                                  temp_fire_output_folder = "data/temp/processed_data/ndvi_relative_time_since_fire/",
                                                  input_fire_dates_tag = "processed_most_recent_burn_dates",
                                                  input_modis_dates_tag = "raw_ndvi_dates_modis",
                                                  output_tag = "processed_ndvi_relative_days_since_fire",
                                                  sleep_time = 5,
                                                  ...){

  # ensure output_folders empty

    if(dir.exists(temp_fire_output_folder)){
      unlink(file.path(temp_fire_output_folder),recursive = TRUE,force = TRUE)
    }

    if(dir.exists(temp_input_fire_date_folder)){
      unlink(file.path(temp_input_fire_date_folder),recursive = TRUE,force = TRUE)
    }

    if(dir.exists(temp_input_ndvi_date_folder)){
      unlink(file.path(temp_input_ndvi_date_folder),recursive = TRUE,force = TRUE)
    }

  # Make folder if needed

    if(! dir.exists(temp_fire_output_folder)){ dir.create(temp_fire_output_folder,
                                                     recursive = TRUE) }

    if(! dir.exists(temp_input_fire_date_folder)){ dir.create(temp_input_fire_date_folder,
                                                     recursive = TRUE) }

    if(! dir.exists(temp_input_ndvi_date_folder)){ dir.create(temp_input_ndvi_date_folder,
                                                     recursive = TRUE) }

  # check on releases

    release_assetts <- pb_list(repo = "AdamWilsonLab/emma_envdata")

  # Create releases if needed

      if(!input_modis_dates_tag %in% release_assetts$tag){

        tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                         tag =  input_modis_dates_tag),
                 error = function(e){message("Previous release found")})

      }

      if(!input_fire_dates_tag %in% release_assetts$tag){

        tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                         tag =  input_fire_dates_tag),
                 error = function(e){message("Previous release found")})

      }

      if(!output_tag %in% release_assetts$tag){

        tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                         tag =  output_tag),
                 error = function(e){message("Previous release found")})

      }



  #Get a list of files in the releases

    fire_files <-
    release_assetts %>%
      filter(tag == input_fire_dates_tag) %>%
      filter(file_name != "") %>%
      filter(grepl(pattern = ".tif$",x = file_name))%>%
      mutate(date = file_name) %>%
      mutate(date = gsub(pattern = ".tif",replacement = "",x = .$date)) %>%
      mutate(date = gsub(pattern = "/",replacement = "",x = .$date)) %>%
      mutate(date = as_date(date)) %>%
      mutate(number = as.numeric(date)) %>%
      mutate(end_date = ceiling_date(x = date,unit = "month") %m-% days(1)) %>%
      mutate(end_number = as.numeric(end_date)) %>%
      arrange(number)


    ndvi_files <-
      release_assetts %>%
      filter(tag == input_modis_dates_tag) %>%
      filter(file_name != "") %>%
      filter(grepl(pattern = ".tif$",x = file_name))%>%
      mutate(date = file_name) %>%
      mutate(date = gsub(pattern = ".tif",replacement = "",x = .$date)) %>%
      mutate(date = gsub(pattern = "/",replacement = "",x = .$date)) %>%
      mutate(date = as_date(date)) %>%
      mutate(number = as.numeric(date)) %>%
      mutate(end_date = ceiling_date(x = date,unit = "month") %m-% days(1)) %>%
      mutate(end_number = as.numeric(end_date)) %>%
      arrange(number)


  #Get a list of fire stuff that has been processed, and exclude anything that doesn't need to be done

    processed_files <-
      release_assetts %>%
      filter(tag == output_tag) %>%
      filter(file_name != "") %>%
      filter(grepl(pattern = ".tif$",x = file_name))%>%
      mutate(date = file_name) %>%
      mutate(date = gsub(pattern = ".tif",replacement = "",x = .$date)) %>%
      mutate(date = gsub(pattern = "/",replacement = "",x = .$date)) %>%
      mutate(date = as_date(date)) %>%
      mutate(number = as.numeric(date)) %>%
      mutate(end_date = ceiling_date(x = date,unit = "month") %m-% days(1)) %>%
      mutate(end_number = as.numeric(end_date)) %>%
      arrange(number)

    ndvi_files <- ndvi_files[which(!ndvi_files$file_name %in% processed_files$file_name),]


  #Quit if there is nothing to process
    if(nrow(ndvi_files) == 0){

      message("Finished processing fire day-of-year to date")

      return(
        release_assetts %>%
          filter(tag == input_modis_dates_tag) %>%
          dplyr::select(file_name) %>%
          filter(file_name != "") %>%
          filter(grepl(pattern = ".tif$", x = file_name)) %>%
          mutate(date_format = gsub(pattern = ".tif",
                                    replacement = "",
                                    x = file_name))%>%
          mutate(date_format = gsub(pattern = "_", replacement = "-", x = date_format)) %>%
          dplyr::pull(date_format) %>%
          max()
      )


    }



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

    Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

    ndvi_raster_i <- terra::rast(file.path(temp_input_ndvi_date_folder,ndvi_files$file_name[i]))


    # Get NDVI date metadata

      start_date_i <- ndvi_files$date[i]
      start_date_numeric_i <- ndvi_files$number[i]
      end_date_numeric_i <- ndvi_files$number[i] + 16


    # Check that ndvi dates and start/end dates make sense

      ndvi_raster_dates <- sort(unique(values(ndvi_raster_i)))

      if(any(ndvi_raster_dates < start_date_numeric_i |
             ndvi_raster_dates > end_date_numeric_i)) {

        warning("NDVI dates outside the 16 day window. Setting these to NAs")

        values_to_NA <-
          which(values(ndvi_raster_i< start_date_numeric_i)==1 |
                  values(ndvi_raster_i > end_date_numeric_i)==1)

        ndvi_raster_i[values_to_NA] <- NA

      }

      ndvi_raster_dates <- sort(unique(values(ndvi_raster_i)))


      if(any(ndvi_raster_dates < start_date_numeric_i |
             ndvi_raster_dates > end_date_numeric_i)) {
        stop("NDVI dates outside the 16 day window remaining.")

      }


    #Get the next fire date raster that occurs after
      suppressWarnings(fire_index <- min(which(fire_files$end_number >= end_date_numeric_i)))

        #If there isn't a next fire layer, stop processing
        if(is.infinite(fire_index)) {
          message("Done processing NDVI dates")

          return(
            release_assetts %>%
              filter(tag == input_modis_dates_tag) %>%
              dplyr::select(file_name) %>%
              filter(file_name != "") %>%
              filter(grepl(pattern = ".tif$", x = file_name)) %>%
              mutate(date_format = gsub(pattern = ".tif",
                                        replacement = "",
                                        x = file_name))%>%
              mutate(date_format = gsub(pattern = "_", replacement = "-", x = date_format)) %>%
              dplyr::pull(date_format) %>%
              max()
          )

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

    Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

    fire_raster_2_i <- terra::rast(file.path(temp_input_fire_date_folder,fire_files$file_name[fire_index]))

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

            Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy


        }

        fire_raster_1_i <- terra::rast(file.path(temp_input_fire_date_folder,fire_files$file_name[fire_index-1]))
        fire_1_start_date <- fire_files$number[fire_index-1]

      }else{

        fire_raster_1_i <- terra::setValues(fire_raster_2_i,values = 0)

      }

    #Grab previous fire layer, or make an empty one if needed

    if(fire_index > 2){


      # download the file if needed
      if(!file.exists(file.path(temp_input_fire_date_folder,fire_files$file_name[fire_index-2]))){

        robust_pb_download(file = fire_files$file_name[fire_index - 2],
                           dest = temp_input_fire_date_folder,
                           repo = "AdamWilsonLab/emma_envdata",
                           tag = input_fire_dates_tag,
                           overwrite = TRUE,
                           max_attempts = 10,
                           sleep_time = sleep_time)

        Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy


      }

      fire_raster_0_i <- terra::rast(file.path(temp_input_fire_date_folder,fire_files$file_name[fire_index-2]))
      fire_0_start_date <- fire_files$number[fire_index-2]

    }else{

      fire_raster_0_i <- terra::setValues(fire_raster_2_i,values = 0)

    }



    # Sanity checks on fire layers

      # Do all last fires occur within the specified month (or earlier?)

    # Make a fire layer that doesn't include anything after the end of the ndvi
    # This code replaces any fire dates that occur after the NDVI measurement
    # with the dates from the previous fire layer

      # Commenting this version out. Syntax doesn't work on current version of terra (as of 2024-01-03)
      # fire_raster_i <- fire_raster_2_i
      # fire_raster_i[fire_raster_2_i > ndvi_raster_i] <- fire_raster_1_i[fire_raster_i > ndvi_raster_i]


    # Less elegant, but works

      fire_raster_i <- fire_raster_2_i

      values_to_replace <- which(values(fire_raster_i) > values(ndvi_raster_i))

      fire_raster_i[values_to_replace] <- fire_raster_1_i[values_to_replace]

      values_to_replace <- which(values(fire_raster_i) > values(ndvi_raster_i))

      fire_raster_i[values_to_replace] <- fire_raster_0_i[values_to_replace]


    #plot(fire_raster_i)
    #plot(fire_raster_2_i - fire_raster_1_i  )
      rm(fire_raster_1_i,fire_raster_2_i,fire_raster_0_i)

    #Set fire dates of zero to NA (since its unlikely any occurred on precisely that date)
      fire_raster_i[fire_raster_i == 0] <- NA

    # Generate days since last fire (NA where no fire recorded)

    output_i <- ndvi_raster_i - fire_raster_i

    # Sanity check for negative days since fire

      if(any(values(output_i) < 0, na.rm = TRUE)){
        stop("Negative burn dates generated")
      }


    #Set name of output, save to a output folder

      names(output_i) <- gsub(pattern = "-",
                              replacement = "_",
                              x = ndvi_files$date[i])

      terra::writeRaster(x = output_i,
                          filename = file.path(temp_fire_output_folder, ndvi_files$file_name[i]),
                          overwrite=TRUE)


    #release the saved filed

      pb_upload(file = file.path(temp_fire_output_folder, ndvi_files$file_name[i]),
                repo = "AdamWilsonLab/emma_envdata",
                tag = output_tag,
                name = ndvi_files$file_name[i],
                overwrite = TRUE)

      Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy



    #Delete any files that are no longer needed
      rm(ndvi_raster_i, output_i)

        file.remove(file.path(temp_fire_output_folder,ndvi_files$file_name[i]))
        file.remove(file.path(temp_input_ndvi_date_folder,ndvi_files$file_name[i]))

        #unlink(file.path(temp_fire_output_folder,ndvi_files$file_name[i]),force = TRUE)

      if(file.exists(file.path(temp_input_fire_date_folder,fire_files$file_name[fire_index-3]))){
        file.remove(file.path(temp_input_fire_date_folder,fire_files$file_name[fire_index-3]))
      }


  }#for ndvi loop

    unlink(x = file.path(temp_fire_output_folder),recursive = TRUE,force = TRUE)
    unlink(x = file.path(temp_input_fire_date_folder),recursive = TRUE,force = TRUE)
    unlink(x = file.path(temp_input_ndvi_date_folder),recursive = TRUE,force = TRUE)
    gc()

  #End function

    message("Done processing NDVI dates")

    return(
      ndvi_files %>%
        filter(tag == input_modis_dates_tag) %>%
        dplyr::select(file_name) %>%
        filter(file_name != "") %>%
        filter(grepl(pattern = ".tif$", x = file_name)) %>%
        mutate(date_format = gsub(pattern = ".tif",
                                  replacement = "",
                                  x = file_name))%>%
        mutate(date_format = gsub(pattern = "_", replacement = "-", x = date_format)) %>%
        dplyr::pull(date_format) %>%
        max()
      )



}#end


