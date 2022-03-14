#' @author Brian Maitner
#' @description This code converts the modis fire dates from a numeric day of the year (e.g. jan 2 is 2), to the number of days in the unix era (days since jan 1 1970)
#' @note The goal is to replace this with earth engine code, but this is needed for double checking at present
#' @param input_tag Github release tag associated with input files
#' @param output_tag Github release tag to use with output files
#' @param temp_directory Where to store the files while working?  The directory is deleted at the end.
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy

process_release_fire_doy_to_unix_date <- function( input_tag = "raw_fire_modis",
                                                   output_tag = "processed_fire_dates",
                                                   temp_directory = "data/temp/processed_data/fire_dates/",
                                                   sleep_time = 1,
                                                   ...) {
  
  #make folder if needed
    if(!dir.exists(temp_directory)){dir.create(temp_directory, recursive = TRUE)}
  
  
  #Make sure there is a release by attempting to create one.  If it already exists, this will fail
    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  input_tag),
             error = function(e){message("Previous release found")})
  
  Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy
  
  #Make sure there is a release by attempting to create one.  If it already exists, this will fail
    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  output_tag),
             error = function(e){message("Previous release found")})
  
  #get files
  
    input_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                            tag = input_tag) %>%
                    filter(file_name != "")
    
    Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy
    
    output_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                            tag = output_tag)%>%
                      filter(file_name != "")

  #prune input files to only ones not in output
  
    
    
    input_files <- input_files[which(!input_files$file_name %in% output_files$file_name),]
    
    
    if(nrow(input_files) == 0) {
      message("Finished processing fire day-of-year to date")
      return(invisible(NULL))
    }
  
  #Do the actual processing of the fire day-of-year rasters into UNIX dates
  
    for(i in 1:length(input_files)){
      
      # download file i
        robust_pb_download(file = input_files$file_name[i],
                           dest = temp_directory,
                           repo = "AdamWilsonLab/emma_envdata",
                           tag = input_tag,
                           overwrite = TRUE,
                           max_attempts = 10)
  
      #Get raster
        raster_i <- raster(file.path(temp_directory,input_files$file_name[i]))  

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
                            filename = file.path(temp_directory,input_files$file_name[i]),
                            overwrite = TRUE)
        
        pb_upload(file = file.path(temp_directory,input_files$file_name[i]),
                  repo = "AdamWilsonLab/emma_envdata",
                  tag = output_tag,
                  name = input_files$file_name[i],
                  overwrite = TRUE)
        
        file.remove(file.path(temp_directory,input_files$file_name[i]))
      
        Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy
        
        
    }#for loop
  
  # Delete temp files
    
    unlink(x = gsub(pattern = "/$",replacement = "",x = temp_directory), #sub used to delete any trailing slashes, which interfere with unlink
           recursive = TRUE)  
    
  #End function

    message("Finished processing fire day-of-year to date")
    return(invisible(NULL))
  
  
}
