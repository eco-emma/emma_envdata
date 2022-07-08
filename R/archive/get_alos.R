#ALOS

#' @author Brian Maitner

#make a function to reduce code duplication

#' @param image_text is the text string used by gee to refer to an image, e.g. "CSP/ERGo/1_0/Global/ALOS_mTPI"
#' @param dir directory to save data in
#' @param domain domain (sf polygon) used for masking
#' @note This code is only designed to work with a handful of images by CSP/ERGo
get_alos_data <- function(image_text, dir, domain){

  #Load the image

    focal_image <- ee$Image(image_text)

    focal_name <- focal_image$getInfo()$properties$visualization_0_name

    focal_name <- tolower(focal_name)

    focal_name <-gsub(pattern = " ", replacement = "_", x = focal_name)

  #Format the domain
    domain <- sf_as_ee(x = domain)
    domain <- domain$geometry()

  #get CRS
    crs <- focal_image$getInfo()$bands[[1]]$crs

  #Download the raster
    ee_as_raster(image = focal_image,
                 region = domain,
                 #scale = 100, #used to adjust the scale. commenting out uses the default
                 dsn = paste(dir,focal_name,sep = ""),
                 maxPixels = 10000000000)


}# end function



#' @description This function makes use of the previous helper function to download data
#' @param domain domain (sf polygon) used for masking
#' @param directory Where to save the files, defaults to "data/raw_data/alos/"
get_alos <- function(directory = "data/raw_data/alos/", domain){

  #make a directory if one doesn't exist yet

    if(!dir.exists(directory)){
      dir.create(directory, recursive = TRUE)
    }


  #Initialize earth engine (for targets works better if called here)
  ee_Initialize()

  # Get files that have been downloaded
    alos_files <- list.files(directory,pattern = ".tif$")

  #Download files that have not previously been downloaded

  # mTPI
    if(!length(grep(pattern = "mtpi",x = alos_files)) > 0){
      get_alos_data(image_text = "CSP/ERGo/1_0/Global/ALOS_mTPI",
                    dir = directory,
                    domain = domain)
    }

  # CHILI
    if(!length(grep(pattern = "chili",x = alos_files)) > 0){
      get_alos_data(image_text = "CSP/ERGo/1_0/Global/ALOS_CHILI",
                    dir = directory,
                    domain = domain)
    }


  # landforms
    if(!length(grep(pattern = "landforms",x = alos_files)) > 0){
      get_alos_data(image_text = 'CSP/ERGo/1_0/Global/ALOS_landforms',
                    dir = directory,
                    domain = domain)
    }

  # topo diversity
    if(!length(grep(pattern = "topographic",x = alos_files)) > 0){
      get_alos_data(image_text = 'CSP/ERGo/1_0/Global/ALOS_topoDiversity',
                    dir = directory,
                    domain = domain)
    }


  message("Finished downloading ALOS layers")

  return(directory)

}



##################################

