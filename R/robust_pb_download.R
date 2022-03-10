#' @description Download using piggyback but make sure it worked
#' @author Brian Maitner
#' @param file as in pb_download
#' @param dest as in pb_download
#' @param repo as in pb_download
#' @param tag as in pb_download
#' @param overwrite as in pb_download
#' @param max_attempts The maximum number of attempts before giving up
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy
robust_pb_download <- function(file, dest, repo, tag, overwrite, max_attempts = 10, sleep_time = 1 ){
  
  #Check that dest has a slash at the end
  
  
  # First remove existing files.  Failing to do this makes it harder to distinguish between failed downloads and old files
  
  if(file.exists(paste(dest,file,sep = "")) ){
    
    file.remove(paste(dest,file,sep = ""))
    
  }
  
  
  # Next, attempt to download file, checking if it was indeed downloaded
  
  for( i in 1:max_attempts){
    
    #Try to download file
    
    pb_download(file = file,
                dest = dest,
                repo = repo,
                tag = tag,
                overwrite = overwrite)
    
    # Check whether file exists
    
    file_present  <- file.exists(paste(dest,file,sep = ""))
    
    # If file isn't present, try again
    if(!file_present){
      Sys.sleep(sleep_time)
      next 
    }
    
    # If this is a tif, check that it loads.  If it throws an error, try again
    
    if(grepl(pattern = ".tif$", x = file)){
      
      if(!tryCatch({terra::rast(paste(dest,file,sep = "")); TRUE}, error = function(e) FALSE)){
        Sys.sleep(sleep_time)
        next
      }
      
    }
    
    # If this is a parquet, check that it loads.  If it throws an error, try again
    
    if(grepl(pattern = ".parquet", x = file)){
      
      if(!tryCatch({arrow::open_dataset(sources = paste(dest,file,sep = "")); TRUE}, error = function(e) FALSE)){
        Sys.sleep(sleep_time)
        next
      }
      
    }
    
    # If the file has gotten this far, it seems good and we can move on
    
    return(invisible(NULL))
    
    
  } # i loop (~ "while")
  
  stop(paste(file, "File was not downloaded properly"))
  
  
}# end robust pb_download function

