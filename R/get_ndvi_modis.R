library(rgee)
source("R/get_domain.R")

#' @description This function will download ndvi layers (derived from MODIS 16 day products), skipping any that have been downloaded already.
#' @author Brian Maitner, but built from code by Qinwen, Adam, and the KNDVI ms authors
#' @param directory The directory the ndvi layers should be saved to, defaults to "data/raw_data/ndvi_modis/"
#' @import rgee
get_ndvi <- function(directory = "data/raw_data/ndvi_modis/") {

  # Make a directory if one doesn't exist yet

  if(!dir.exists(directory)){
    dir.create(directory)
  }

  # Load the image collection
  modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A1") #500 m
  # modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A2") #1 km


  domain <- get_domain()

  #Set Visualization parameters

  ndviviz <- list(
    min = -1,
    max = 1,
    palette = c('00FFFF','FF00FF')
  )

  #MODIS makes it simple to filter out poor quality pixels thanks to a quality control bits band (DetailedQA).
  #The following function helps us to distinct between good data (bit == …00) and marginal data (bit != …00).

  getQABits <- function(image, qa) {
    # Convert binary (character) to decimal (little endian)
    qa <- sum(2^(which(rev(unlist(strsplit(as.character(qa), "")) == 1))-1))
    # Return a mask band image, giving the qa value.
    image$bitwiseAnd(qa)$lt(1)
  }

  #Using getQABits we construct a single-argument function (mod13A2_clean)
  #that is used to map over all the images of the collection (modis_ndvi).

  mod13A1_clean <- function(img) {
    # Extract the NDVI band
    ndvi_values <- img$select("NDVI")

    # Extract the quality band
    ndvi_qa <- img$select("SummaryQA")

    # Select pixels to mask
    quality_mask <- getQABits(ndvi_qa, "11")

    # Mask pixels with value zero.
    ndvi_values$updateMask(quality_mask)
  }


  #Make clean the dataset

  ndvi_clean <- modis_ndvi$map(mod13A1_clean)

  #What has been downloaded already?

  images_downloaded <- list.files(directory, full.names = F,pattern = ".tif")
  images_downloaded <- gsub(pattern = ".tif",replacement = "",x = images_downloaded,fixed = T)

  #check to see if any images have been downloaded already
  if(length(images_downloaded)==0){

    newest <- lubridate::as_date(-1) #if nothing is downloaded, start in 1970

  }else{

    newest <- max(lubridate::as_date(images_downloaded)) #if there are images, start with the most recent

  }



  #Filter the data to exclude anything you've already downloaded (or older)
  ndvi_clean_and_new <- ndvi_clean$filterDate(start = paste(as.Date(newest+1),sep = ""),
                                              opt_end = paste(format(Sys.time(), "%Y-%m-%d"),sep = "") ) #I THINK I can just pull the most recent date, and then use this to download everything since then

  #Adjust gain and offset.  The NDVI layer has a scale factor of 0.0001
  adjust_gain_and_offset <- function(img){
    img$add(10000)$divide(100)$round()

  }



  ndvi_clean_and_new <- ndvi_clean_and_new$map(adjust_gain_and_offset)


  #Download
  ee_imagecollection_to_local(ic = ndvi_clean_and_new,
                              region = domain,
                              dsn = directory,
                              formatOptions = c(cloudOptimized = true))




}

