#' @author Brian Maitner
#' @description This function converts rasters containing burn dates (in UNIX date format) to rasters containing the most recent burn date (also in UNIX format)

process_burn_date_to_last_burned_date <- function(input_folder = "data/processed_data/fire_dates/",
                                           output_folder = "data/processed_data/most_recent_burn_dates/",
                                           ...){


  if(!dir.exists(output_folder)){dir.create(output_folder,recursive = TRUE)}

  #Get lists of files
    input_files <- list.files(input_folder, full.names = T,pattern = ".tif")
    output_files <- list.files(output_folder, full.names = T,pattern = ".tif")

  #prune input files to only ones not in output
    input_no_dir <- gsub(pattern = input_folder,replacement = "",x = input_files)
    output_no_dir <- gsub(pattern = output_folder,replacement = "",x = output_files)

  #Ensure input files are properly ordered
    input_files <- data.frame(input_file = input_files,
                              date = as_date(gsub(pattern = ".tif",
                                                               replacement = "",
                                                               x = gsub(pattern = "/",
                                                                        replacement = "",
                                                                        x = input_no_dir))))
    input_files$number <- as.numeric(input_files$date)
    input_files <- input_files[order(input_files$number),]

  #Ensure output files are properly ordered
    output_files <- data.frame(output_file = output_files,
                              date = as_date(gsub(pattern = ".tif",
                                                  replacement = "",
                                                  x = gsub(pattern = "/",
                                                           replacement = "",
                                                           x = output_no_dir))))
    output_files$number <- as.numeric(output_files$date)
    output_files <- output_files[order(output_files$number),]

  #Prune any files that have been already done
    input_files <- input_files[which(!input_no_dir %in% output_no_dir),]
    rm(input_no_dir, output_no_dir)

  #If all input has been processed, skip
    if(nrow(input_files) == 0) {
      message("Finished processing fire dates")
      return(invisible(NULL))
    }


  #Start with input raster 1 or the last output raster.
    if(nrow(output_files) == 0){

      previous_raster <- raster(input_files$input_file[1])

    }else{

      previous_raster <- raster(output_files$output_file[nrow(output_files)])

    }

  #Iterate through all rasters, keeping a running tally of most recent burn
    for(i in 1:nrow(input_files)){

      #Get raster i
        raster_i <- raster(input_files$input_file[i])

        max_i <- max(stack(raster_i,previous_raster))

        #save output
        raster::writeRaster(x = max_i,
                            filename = paste(output_folder,"/",
                                             gsub(pattern = "-",
                                                  replacement = "_",
                                                  x = input_files$date[i]),
                                             ".tif",sep = ""),
                            overwrite=TRUE)

      #Set previous raster
        previous_raster <- max_i

    }#for loop

  #End function
    message("Finished processing fire dates")
    return(invisible(NULL))


}#end fx
