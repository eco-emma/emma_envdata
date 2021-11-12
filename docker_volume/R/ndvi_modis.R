#' @author Brian Maitner, but built from code by Qinwen and Adam

library(cptcity)
library(raster)
library(stars)
library(rgee)
library(sf)
library(rgdal)
library(googledrive)
library(stringr)

#make a directory if one doesn't exist yet

if(!dir.exists("docker_volume/raw_data/modis_ndvi")){
  dir.create("docker_volume/raw_data/modis_ndvi")
}

  ee_Initialize(drive = TRUE)
  #ee_check()

  modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A2")


#get metadata

  info<- modis_ndvi$getInfo()

  #Make a bounding box of South Africa so we can download just the relevant data
  # Note: it would be better to use a polygon of just the focal regions instead

  sabb <- ee$Geometry$Rectangle(
    coords = c(16.3449768409, -34.8191663551, 32.830120477, -22.0913127581),
    proj = "EPSG:4326",
    geodesic = FALSE
  )


  #Set Visualization parameters

  ndviviz <- list(
    min = info$properties$visualization_0_min,
    max = info$properties$visualization_0_max,
    palette = c('00FFFF','FF00FF')
  )



#MODIS makes it simple to filter out poor quality pixels thanks to a quality control bits band (DetailedQA). The following function helps us to distinct between good data (bit == …00) and marginal data (bit != …00).

  getQABits <- function(image, qa) {
    # Convert binary (character) to decimal (little endian)
    qa <- sum(2^(which(rev(unlist(strsplit(as.character(qa), "")) == 1))-1))
    # Return a mask band image, giving the qa value.
    image$bitwiseAnd(qa)$lt(1)
  }

#Using getQABits we construct a single-argument function (mod13A2_clean) that is used to map over all the images of the collection (modis_ndvi).
  mod13A2_clean <- function(img) {
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

  ndvi_clean <- modis_ndvi$map(mod13A2_clean)

#What has been downloaded already?

  images_downloaded <- list.files("docker_volume/raw_data/modis_ndvi/",full.names = F,pattern = ".tif")
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

#Download
  ee_imagecollection_to_local(ic = ndvi_clean_and_new,
                            region = sabb,
                            dsn = "docker_volume/raw_data/modis_ndvi/")

