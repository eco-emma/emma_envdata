#' @description Code to delete unneeded files from workflow
#' @author Brian Maitner
clean_up <- function(){
  
  library(rgee)
  library(googledrive)
  
  ee_Initialize()
  
  tryCatch(expr = ee_clean_container(name = "rgee_backup",
                                     type = "drive",
                                     quiet = TRUE),
           error=function(e){message("No rgee backup to delete")}
           )
  
  
}