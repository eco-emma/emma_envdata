#' @author Brian Maitner
#' @description The goal of this script is to deal with the mismatch between MODIS fire and NDVI dates, producing time-since-fire raster that is pair with a NDVI raster

library(lubridate)
library(raster)

match_ndvi_and_fire_modis_dates <- function(ndvi_date_folder = "docker_volume/raw_data/modis_ndvi_dates/",
                                            fire_date_folder = "docker_volume/raw_data/fire_modis_most_recent_burn_date/",
                                            fire_output_folder = "docker_volume/raw_data/days_since_burn_matched_to_ndvi/"){

  #Make folder if needed
    if(! dir.exists(fire_output_folder)){ dir.create(fire_output_folder) }


  #Get a list of files with different formats
  fire_files <- list.files(fire_date_folder, full.names = T,pattern = ".tif")
  ndvi_files <- list.files(ndvi_date_folder, full.names = T,pattern = ".tif")


  fire_no_dir <- gsub(pattern = fire_date_folder,replacement = "",x = fire_files)
  ndvi_no_dir <- gsub(pattern = ndvi_date_folder,replacement = "",x = ndvi_files)

  fire_files <- data.frame(input_file = fire_files,
                            date = as_date(gsub(pattern = ".tif",
                                                replacement = "",
                                                x = gsub(pattern = "/",
                                                         replacement = "",
                                                         x = fire_no_dir))))
  ndvi_files <- data.frame(input_file = ndvi_files,
                           date = as_date(gsub(pattern = ".tif",
                                               replacement = "",
                                               x = gsub(pattern = "/",
                                                        replacement = "",
                                                        x = ndvi_no_dir))))

  fire_files$number <- as.numeric(fire_files$date)
  fire_files$end_date <- ceiling_date(x = fire_files$date,unit = "month") %m-% days(1)
  fire_files$end_number <- as.numeric(fire_files$end_date)
  fire_files <- fire_files[order(fire_files$number),]

  ndvi_files$number <- as.numeric(ndvi_files$date)
  ndvi_files <- ndvi_files[order(ndvi_files$number),]







  #Get a list of fire stuff that has been processed

    # code will go here to get the dates from the fire_output_folder and use them to prune the ndvi files
    message("Brian write code")


  #Iterate through each NDVI layer (that hasn't been processed) and generate a corresponding set of fire dates

    for(i in 1:nrow(ndvi_files)){

      #Get ndvi raster and metadata
        ndvi_raster_i <- raster(ndvi_files$input_file[i])
        start_date_i <- ndvi_files$date[i]
        start_date_numeric_i <- ndvi_files$number[i]
        end_date_numeric_i <- ndvi_files$number[i]+16

      #Get the next fire date raster that occurs after
        fire_index <- min(which(fire_files$end_number >= end_date_numeric_i))

      #If there isn't a next fire layer, stop processing
        if(is.infinite(fire_index)) {
          message("Done processing NDVI dates")
          return(invisible(NULL))
          }

      #Make a "time since last fire" layer

        #Grab fire layer occurring after, STOP if one doesn't exist
          fire_raster_2_i <- raster(fire_files$input_file[fire_index])
          fire_2_start_date <- fire_files$number[fire_index]

        #Grab previous fire layer, or make an empty one if needed
          if(fire_index > 1){

            fire_raster_1_i <- raster(fire_files$input_file[fire_index-1])
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
          plot(fire_raster_2_i - fire_raster_1_i  )
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
                      filename = paste(fire_output_folder,
                                       gsub(pattern = "-",
                                            replacement = "_",
                                            x = ndvi_files$date[i]),
                                       ".tif",
                                       sep = ""))





    }#for ndvi loop




}

