expiration_date <- "2022-05-01"

# add information on date uncertainty

# check why parquet files aren't updating -> update functions to return latest raster date or timestamp

#' @author Brian Maitner
#' @description This function converts rasters containing burn dates (in UNIX date format) to rasters containing the most recent burn date (also in UNIX format)
#' @param sanbi_sf The SANBI fire polygons, loaded as an sf object. Ignored if NUL
#' @param expiration_date If supplied as a date, layers processed before this will be re-processed.  Ignored if NULL.  If specifying, should be "yyyy-mm-dd" format.
#' @param max_fire_duration Numeric.  The maximum number of days a fire could run.  Any fires lasting longer than this are removed.

process_release_burn_date_to_last_burned_date <- function(input_tag = "processed_fire_dates",
                                                          output_tag = "processed_most_recent_burn_dates",
                                                          temp_directory_input = "data/temp/processed_data/fire_dates/",
                                                          temp_directory_output = "data/temp/processed_data/most_recent_burn_dates/",
                                                          sleep_time = 1,
                                                          sanbi_sf = NULL,
                                                          expiration_date = NULL,
                                                          max_fire_duration = 30,
                                                          ...){

  #make folder if needed

    if(!dir.exists(temp_directory_input)){dir.create(temp_directory_input, recursive = TRUE)}

    if(!dir.exists(temp_directory_output)){dir.create(temp_directory_output, recursive = TRUE)}

  # clear out any accidental remnants

    file.remove(list.files(temp_directory_input,full.names = TRUE))
    file.remove(list.files(temp_directory_output,full.names = TRUE))

  #Make sure there is a release or else create one.

    pb_assests <- pb_list(repo = "AdamWilsonLab/emma_envdata")

    if(!input_tag %in% pb_assests$tag){

      tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                       tag =  input_tag),
               error = function(e){message("Previous release found")})

      Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

    }



  #Make sure there is a release by attempting to create one.  If it already exists, this will fail

    if(!output_tag %in% pb_assests$tag){

      tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                       tag =  output_tag),
               error = function(e){message("Previous release found")})

      Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

    }

  # get files

    input_files  <-  pb_assests %>%
                      filter(tag == input_tag) %>%
                      filter(file_name != "")


    output_files  <- pb_assests %>%
                      filter(tag == output_tag) %>%
                      filter(file_name != "")

    # prune input files to only ones not in output

    if(is.null(expiration_date)){ #if no expiration date, only process dates not in the output

      input_files <- input_files[which(!input_files$file_name %in% output_files$file_name),]

    }else{ #if expiration date given, process any files that aren't in the output or are older than the output

      input_files <- input_files[input_files$timestamp < as_date(expiration_date),]
      output_files <- output_files[output_files$timestamp > as_date(expiration_date),]
      input_files <- input_files[which(!input_files$file_name %in% output_files$file_name),]

    }

    if(nrow(input_files) == 0) {
      message("Finished processing fire day-of-year to date")
      return(
        pb_assests %>%
          filter(tag == input_tag) %>%
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

  #If all input has been processed, skip

    if(nrow(input_files) == 0) {
      message("Finished processing fire dates")
      return(
        pb_assests %>%
          filter(tag == input_tag) %>%
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

  # If sanbi sf has been provided, do some quality control

        if(!is.null(sanbi_sf)){


          # Manual fixes (hopefully temporary)
          sanbi_sf$DateExting[which(sanbi_sf$DateExting=="7197-07-31")] <- "1979-07-31"
          sanbi_sf$DateExting[which(sanbi_sf$DateExting=="3009-02-04")] <- "2009-02-04"
          sanbi_sf$DateExting[which(sanbi_sf$DateExting=="2103-03-26")] <- "2013-03-26"
          sanbi_sf$DateExting[which(sanbi_sf$DateExting=="2066-03-05")] <- "2006-03-05"


          # Toss any fires that are too long or which burn backwards in time

          sanbi_sf %>%
            mutate(fire_duration = sanbi_sf$DateExting - sanbi_sf$DateStart) %>%
            filter((fire_duration <= max_fire_duration & fire_duration >= 0)|
                     is.na(fire_duration)) -> sanbi_sf

          # Add a new date column
          sanbi_sf %>%
            mutate( most_recent_burn = case_when( !is.na(DateExting) ~ as.character(DateExting), # If available, take extinguish date
                                                  is.na(DateExting) & !is.na(DateStart) ~ as.character(DateStart),# next, prioritize start date
                                                  is.na(DateExting) & is.na(DateStart) & MONTH != 0 ~ as.character(paste(YEAR,MONTH, "01", sep = "-")),# next, prioritize start date
                                                  is.na(DateExting) & is.na(DateStart) & MONTH == 0 ~ as.character(paste(YEAR, "01", "01", sep = "-")) #take month + year

            )) %>%
            mutate(most_recent_burn = as_date(most_recent_burn)) %>%
            mutate(numeric_most_recent_burn = as.numeric(most_recent_burn)) -> sanbi_sf

          # Toss any polygons that do not specify an exact date and occur during MODIS time period (year 2000 or later)
          sanbi_sf %>%
            filter( (!is.na(DateStart) & !is.na(DateExting) & YEAR >= 2000)|
                      YEAR < 2000) -> sanbi_sf


          # Toss anything in the future
          sanbi_sf %>%
            filter(numeric_most_recent_burn < Sys.Date()) -> sanbi_sf

        }


  #Start with input raster 1 or the last output raster.
      if(nrow(output_files) == 0){

          robust_pb_download(file = input_files$file_name[1],
                             dest = temp_directory_input,
                             repo = "AdamWilsonLab/emma_envdata",
                             tag = input_tag,
                             overwrite = TRUE,
                             max_attempts = 10,
                             sleep_time = sleep_time)


        previous_raster <- raster(file.path(temp_directory_input,input_files$file_name[1]))

      }else{


        robust_pb_download(file = output_files$file_name[nrow(output_files)],
                           dest = temp_directory_output,
                           repo = "AdamWilsonLab/emma_envdata",
                           tag = output_tag,
                           overwrite = TRUE,
                           max_attempts = 10,
                           sleep_time = sleep_time)

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
                       sleep_time = 2,
                       max_fire_duration = 30)

    #Load the raster
    raster_i <- raster(file.path(temp_directory_input,input_files$file_name[i]))

    #Get an equivalent raster using the SANBI data



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
    return(
      input_files %>%
        filter(tag == input_tag) %>%
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



}#end fx
