#ALOS

#' @author Brian Maitner

#make a function to reduce code duplication

#' @param image_text is the text string used by gee to refer to an image, e.g. "CSP/ERGo/1_0/Global/ALOS_mTPI"
#' @param sabb Bounding Box to constrain area downloaded
#' @note This code is only deisnged to work with a handful of images by CSP/ERGo
get_alos_data <- function(image_text,sabb){


  focal_image <- ee$Image(image_text)


  focal_name <- focal_image$getInfo()$properties$visualization_0_name
  focal_name <- tolower(focal_name)
  focal_name <-gsub(pattern = " ", replacement = "_", x = focal_name)


  #get CRS
  crs <- focal_image$getInfo()$bands[[1]]$crs

  #Download the raster
  ee_as_raster(image = focal_image,
               region = sabb,
               #scale = 100, #used to adjust the scale. commenting out uses the default
               dsn = paste("data/raw_data/alos/",focal_name,sep = ""),
               maxPixels = 10000000000)


}# end function



#' @description This function makes use of the previous helper function to download data
get_alos <- function(directory = "data/raw_data/alos/"){

  #make a directory if one doesn't exist yet

  if(!dir.exists(directory)){
    dir.create(directory)
  }

  #Make a bounding box of the extent we want

  ext <- readRDS(file = "data/other_data/domain_extent.RDS")

  sabb <- ee$Geometry$Rectangle(
    coords = c(ext@xmin,ext@ymin,ext@xmax,ext@ymax),
    proj = "EPSG:4326",
    geodesic = FALSE
  )

  rm(ext)

  # Get files that have been downloaded
  alos_files <- list.files(directory,pattern = ".tif$")

  #Download files that have not previously been downloaded

  # mTPI
  if(!length(grep(pattern = "mtpi",x = alos_files)) > 0){
    get_alos_data(image_text = "CSP/ERGo/1_0/Global/ALOS_mTPI")
  }

  # CHILI
  if(!length(grep(pattern = "chili",x = alos_files)) > 0){
    get_alos_data(image_text = "CSP/ERGo/1_0/Global/ALOS_CHILI")
  }


  # landforms
  if(!length(grep(pattern = "landforms",x = alos_files)) > 0){
    get_alos_data(image_text = 'CSP/ERGo/1_0/Global/ALOS_landforms')
  }

  # topo diversity
  if(!length(grep(pattern = "topographic",x = alos_files)) > 0){
    get_alos_data(image_text = 'CSP/ERGo/1_0/Global/ALOS_topoDiversity')
  }




}






##################################

