

#' @description Download using download.file but make sure it worked
#' @author Brian Maitner
#' @param url as in download.file
#' @param destfile as in download.file
#' @param max_attempts The maximum number of attempts before giving up
#' @param sleep_time Amount of time to wait between attempts. Worth using if problems may be due to temporary internet outage
#' @note This function also handles the bug in download.file when using windows. 
robust_download_file <- function(url, destfile, max_attempts = 10, sleep_time = 10){
  
  
  attempts = 0
  
  while(attempts < max_attempts){
    
    
    dl <-
      tryCatch(expr = 
                 {if(.Platform$OS.type == "windows") {
                   
                   download.file(url = url,
                                 destfile = destfile,
                                 quiet = FALSE,
                                 mode = "wb")
                   
                 } else {
                   
                   
                   # download the full file
                   download.file(url = url,
                                 destfile = destfile)
                   
                   
                   
                 }},
               error = function(e){e}
               
               
               
      )#end trycatch
    
    
    #if the file was downloaded and exists, break out of the while loop
    
    if( !inherits(dl,"error") & file.exists(destfile)){return(invisible(dl))}

    #if file wasn't downloaded, add to the attempt counter and wait
    
    attempts <- attempts + 1
    
    message("Download attempt ",attempts, " of ", max_attempts, " failed")
    Sys.sleep(sleep_time)
    
    rm(dl)
    
    
    
  }#end while
  
  stop("Maximum download attempts reached without success for ", destfile)  
  
    
}#end fx

