library(sf)
library(piggyback)
library(tidyverse)
library(lubridate)
library(fasterize)
# add information on date uncertainty

# check why parquet files aren't updating -> update functions to return latest raster date or timestamp

#' @author Brian Maitner
#' @description This function converts rasters containing burn dates (in UNIX date format) to rasters containing the most recent burn date (also in UNIX format)
#' @param sanbi_sf The SANBI fire polygons, loaded as an sf object. Ignored if NUL
#' @param expiration_date If supplied as a date, layers processed before this will be re-processed.  Ignored if NULL.  If specifying, should be "yyyy-mm-dd" format.

process_release_burn_date_to_last_burned_date <- function(input_tag = "processed_fire_dates",
                                                          output_tag = "processed_most_recent_burn_dates",
                                                          temp_directory_input = "data/temp/processed_data/fire_dates/",
                                                          temp_directory_output = "data/temp/processed_data/most_recent_burn_dates/",
                                                          sleep_time = 1,
                                                          sanbi_sf = sanbi_fires_shp,
                                                          expiration_date = NULL,
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



  #Make sure there is a release, create if needed

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


          # Manual fixes (hopefully temporary).  Manual fixes are educated guesses based on the assumption that fires are unlikely to burn > 30 days, only burn forward in time, have not been reported by time travelers, and that MONTH is correct.
          sanbi_sf$DateExting[which(sanbi_sf$DateExting=="7197-07-31")] <- "1979-07-31"
          sanbi_sf$DateExting[which(sanbi_sf$DateExting=="3009-02-04")] <- "2009-02-04"
          sanbi_sf$DateExting[which(sanbi_sf$DateExting=="2103-03-26")] <- "2013-03-26"
          sanbi_sf$DateExting[which(sanbi_sf$DateExting=="2066-03-05")] <- "2006-03-05"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="OUTE/06/2016/01")] <- "2016-06-03"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="LMBR/04/2015/03")] <- "2015-04-11"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="TKOP/12/2019/01")] <- "2019-12-17"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="KGBG/02/2017/03")] <- "2017-02-15" #unclear when this occurred, so treating it as month and year
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="KGBG/02/2017/03")] <- "2017-02-15" #unclear when this occurred, so treating it as month and year
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="OUTE/10/2014/01")] <- "2014-10-15" #unclear when this occurred, so treating it as month and year
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="OUTE/10/2014/01")] <- "2014-10-15" #unclear when this occurred, so treating it as month and year
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="WATV/01/2016/04")] <- "2016-02-18"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="JONK/12/2020/01")] <- "2020-12-07"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="JONK/12/2020/01")] <- "2020-12-07"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="WATV/01/2016/04")] <- "2016-02-18"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="LMBR/03/1984/01")] <- "1984-03-05"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/02/1987/01")] <- "1987-03-12"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="HOTT/01/2016/01")] <- "2016-01-04"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="WATV/03/2003/02")] <- "2003-03-10"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="KAMM/03/2002/01")] <- "2002-04-09"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="WATV/03/2003/01")] <- "2003-03-01"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="WATV/03/2003/01")] <- "2003-03-06"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/12/1997/01")] <- "1998-01-05"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="WATV/02/2006/03")] <- "2006-02-23"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="ANYS/11/2017/02")] <- "2017-11-08"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="CEDB/02/2013/03")] <- "2013-02-07"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="ROCH/04/2020/01")] <- "2020-04-15" #assigning start date to middle of the month due to uncertainty
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="CEDB/12/1978/01")] <- "1978-12-25"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="DEHP/12/2002/01")] <- "2003-01-03"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="SWBG/04/1989/01")] <- "1989-04-07"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/04/1989/01")] <- "1989-04-09"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="GOUK/04/2005/01")] <- "2005-04-26"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/03/1999/01")] <- "1999-04-05"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/02/1994/01")] <- "1994-03-04"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="SWBG/03/1984/01")] <- "1984-03-05"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/03/1984/01")] <- "1984-03-06"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="SWBG/03/1984/01")] <- "1985-03-10"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/03/1984/01")] <- "1985-03-11"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="SWBG/03/1985/01")] <- "1985-03-10"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/03/1985/01")] <- "1985-03-11"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="SWBG/04/1987/01")] <- "1987-04-08"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/04/1987/01")] <- "1987-04-09"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="DEHP/01/2007/01")] <- "2007-02-03"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="SWBG/03/1982/01")] <- "1982-03-02"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="WATV/01/2013/01")] <- "2013-02-01"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="SWBG/01/1998/01")] <- "1998-01-04"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/01/1998/01")] <- "1998-01-05"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/07/1984/01")] <- "1984-07-03"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="SWBG/07/1984/01")] <- "1984-07-02"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="GOUK/06/1996/01")] <- "1996-06-07"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="GOUK/06/1996/01")] <- "1996-06-07"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="SWBG/02/2006/02")] <- "2006-02-07"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="SWBG/02/2006/02")] <- "2006-02-07"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="GOUK/06/1996/01")] <- "1996-06-07"
          sanbi_sf$DateExting[which(sanbi_sf$FIRE_CODE=="GOUK/06/1996/01")] <- "1996-06-07"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="OUTE/06/1941/01")] <- "1941-06-09"
          sanbi_sf$DateStart[which(sanbi_sf$FIRE_CODE=="OUTE/06/1943/01")] <- "1943-06-05"

          #Toss any start dates noted as "fake"
          sanbi_sf$DateStart[which(grepl(pattern = "START DATE FAKE",
                                         x = sanbi_sf$LOCAL_DESC,
                                         ignore.case = TRUE))] <- NA


          # Add a new date column
          sanbi_sf %>%
            mutate( most_recent_burn = case_when( !is.na(DateExting) ~ as.character(DateExting), # If available, take extinguish date
                                                  is.na(DateExting) & !is.na(DateStart) ~ as.character(DateStart),# next, prioritize start date
                                                  is.na(DateExting) & is.na(DateStart) & MONTH != 0 ~ as.character(paste(YEAR, MONTH, "15", sep = "-")),# next, prioritize start date. set unknown date to middle of the month
                                                  is.na(DateExting) & is.na(DateStart) & MONTH == 0  & YEAR < 1996 ~ as.character(paste(YEAR, "01", "01", sep = "-")) #take month + year

                                                  # 1) if DateExting is present, use that, else
                                                  #   2) if DateStart is present, use that, else
                                                  #     3) if YEAR and MONTH are present assign the date as the 15th of that month, else
                                                  #       4) if YEAR < 1996 assign the date as January 1 of that YEAR, else
                                                  #         5) NULL


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

  #Fix sf projection

    if(!is.null(sanbi_sf)){

      st_transform(x = sanbi_sf,
                   crs = st_crs(previous_raster)) -> sanbi_sf



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

    #Load the raster
    raster_i <- raster(file.path(temp_directory_input,input_files$file_name[i]))

      #if SANBI polygon is missing, just use MODIS

        if(is.null(sanbi_sf)){

          max_i <- max(stack(raster_i,previous_raster))
          max_i[max_i==0] <- NA

        }else{

          #if SANBI sf is present, construct a raster and use all three

            sanbi_sf %>%
              filter(most_recent_burn < input_files$date[i]) %>%
              fasterize(raster = raster_i,field = "numeric_most_recent_burn") -> sanbi_raster_i

          sanbi_raster_i[is.na(terra::values(sanbi_raster_i))] <- 0 #safe to use 0 because no fires occured on that day

          max_i <- max(stack(raster_i,previous_raster,sanbi_raster_i))
          max_i[max_i == 0] <- NA

        }


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
