#Code for extracting elevation data from google earth engine

#' @author Brian Maitner
#' @description This function will download NASADEM elevation data if it isn't present, and (invisibly) return a NULL if it is present
#' @import rgee
#' @param directory directory to save data in. Defaults to "data/raw_data/elevation_nasadem/"
#' @param domain domain (spatialpolygons* object) used for masking
get_release_elevation_nasadem <- function(temp_directory = "data/temp/raw_data/elevation_nasadem/",
                                          tag = "raw_static",
                                          domain){
  
  # Make a directory if one doesn't exist yet
  
  if(!dir.exists(temp_directory)){
    dir.create(temp_directory,recursive = TRUE)
  }
  
  #Check if files exist already

  #Initialize rgee (if not done within the function won't work with targets for some reason)
    ee_Initialize()
  
  # Load the image
    dem <- ee$Image("NASA/NASADEM_HGT/001")
  
  #Format the domain
    domain <- sf_as_ee(x = domain)
    domain <- domain$geometry()
    
  #Cut down to the one band we need
    dem <- dem$select("elevation")
  
  
  #Download the raster
    ee_as_raster(image = dem,
                 region = domain,
                 #scale = 100, #used to adjust the scale. commenting out uses the default
                 dsn = file.path(temp_directory, "nasadem.tif"),
                 maxPixels = 10000000000)
    
    
  # Release file
    pb_upload(repo = "AdamWilsonLab/emma_envdata",
              file = file.path(temp_directory,"nasadem.tif"),
              tag = tag,
              name = "nasadem.tif")

  #Remove file
    unlink(temp_directory,recursive = TRUE,force = TRUE)
  
  # End  
    message("NASADEM download finished")
    return(invisible(NULL))
  
  
  
}#end fx



