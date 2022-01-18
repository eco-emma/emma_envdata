#' @author Brian Maitner
#' @description This code converts the modis fire dates from a numeric day of the year (e.g. jan 2 is 2), to the number of days in the unix era (days since jan 1 1970)
#' @note The goal is to replace this with earth engine code, but this is needed for double checking at present


process_fire_doy_to_unix_date <- function(input_folder = "data/raw_data/fire_modis/",
                             output_folder = "data/processed_data/fire_dates/", ...){


  #make folder if needed
    if(!dir.exists(output_folder)){dir.create(output_folder)}


  #get files

    input_files <- list.files(input_folder, full.names = T)

    output_files <- list.files(output_folder, full.names = T)

  #prune input files to only ones not in output

    input_no_dir <- gsub(pattern = input_folder,replacement = "", x = input_files)

    output_no_dir <- gsub(pattern = output_folder,replacement = "", x = output_files)

    input_files <- input_files[which(!input_no_dir %in% output_no_dir)]

    rm(input_no_dir, output_no_dir)

    if(length(input_files) == 0) {
      message("Finished processing fire day-of-year to date")
      return(invisible(NULL))
    }

  #Do the actual processing of the fire day-of-year rasters into UNIX dates

    for(i in 1:length(input_files)){

      #Get raster
      raster_i <- raster(input_files[i])

      #Get year and convert to numeric
      date_i <- raster_i@data@names

      date_i <- gsub(pattern = "X", replacement = "", x = date_i)

      year_i <- strsplit(x = date_i,split = "_")[[1]][1]

      year_i <- as.numeric(as_date(paste(year_i, "-01-01")))

      #Add numeric year to raster cells

      mask_i <- raster_i > 0

      raster_i <- raster::mask(x = raster_i,
                               mask = mask_i,
                               maskvalue = 0,
                               updatevalue = NA)

      raster_i <- raster_i + year_i - 1

      raster_i[!mask_i] <- 0

      #save output
      raster::writeRaster(x = raster_i,
                          filename = paste(output_folder,"/",date_i,".tif",sep = ""),
                          overwrite = TRUE)

      }#for loop

  #End function

    message("Finished processing fire day-of-year to date")
    return(invisible(NULL))


}
