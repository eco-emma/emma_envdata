#Code for extracting elevation data from google earth engine

#' @author Brian Maitner
#' @description This function will download NASADEM elevation data if it isn't present, and (invisibly) return a NULL if it is present
#' @import rgee
get_elevation_nasadem <- function(directory = "data/raw_data/elevation_nasadem/"){

  # Make a directory if one doesn't exist yet

  if(!dir.exists(directory)){
    dir.create(directory)
  }

  if(file.exists(paste(directory,"nasadem.tif",sep = ""))){
    message("NASADEM found, skipping download")
    return(invisible(NULL))

  }

  # Load the image
  dem <- ee$Image("NASA/NASADEM_HGT/001")

  #Get the domain
  domain <- get_domain()

  #Cut down to the one band we need
  dem <- dem$select("elevation")



  # #Download the raster
  # ee_as_raster(image = dem,
  #              region = domain,
  #              #scale = 100, #used to adjust the scale. commenting out uses the default
  #              dsn = directory,
  #              maxPixels = 10000000000)

  #Download the raster
  ee_as_raster(image = dem,
               region = domain,
               #scale = 100, #used to adjust the scale. commenting out uses the default
               dsn = paste(directory,"nasadem.tif",sep = ""),
               maxPixels = 10000000000)


  message("NASADEM download finished")
  return(invisible(NULL))



}#end fx



