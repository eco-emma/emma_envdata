#MCD64A1 v006

# library(cptcity)
# library(raster)
# library(stars)
library(rgee)
# library(sf)
# library(rgdal)
# library(googledrive)
# library(stringr)

#make a directory if one doesn't exist yet

if(!dir.exists("docker_volume/raw_data/fire_modis")){
  dir.create("docker_volume/raw_data/fire_modis")
}

ee_Initialize(drive = TRUE)
#ee_check()

modis_fire <- ee$ImageCollection("MODIS/006/MCD64A1")

#get metadata

  info <- modis_fire$getInfo()

#Make a bounding box of South Africa so we can download just the relevant data
# Note: it would be better to use a polygon of just the focal regions instead

sabb <- ee$Geometry$Rectangle(
  coords = c(16.3449768409, -34.8191663551, 32.830120477, -22.0913127581),
  proj = "EPSG:4326",
  geodesic = FALSE
)


#Set Visualization parameters

fireviz <- list(
  min = info$properties$visualization_0_min,
  max = info$properties$visualization_0_max,
  palette = c('00FFFF','FF00FF')
)

#Are there any QA bits we need?

  #<Put any QA bits here>



#What has been downloaded already?

images_downloaded <- list.files("docker_volume/raw_data/fire_modis/",full.names = F,pattern = ".tif")
images_downloaded <- gsub(pattern = ".tif",replacement = "",x = images_downloaded,fixed = T)


#check to see if any images have been downloaded already
  if(length(images_downloaded)==0){
    
    newest <- lubridate::as_date(-1) #if nothing is downloaded, start in 1970
    
    }else{
      
      newest <- max(lubridate::as_date(images_downloaded)) #if there are images, start with the most recent
      
      }



  
#Filter the data to exclude anything you've already downloaded (or older)
fire_new <- modis_fire$filterDate(start = paste(as.Date(newest+1),sep = ""),
                                            opt_end = paste(format(Sys.time(), "%Y-%m-%d"),sep = "") ) #I THINK I can just pull the most recent date, and then use this to download everything since then

#Download
ee_imagecollection_to_local(ic = fire_new,
                            region = sabb,
                            dsn = "docker_volume/raw_data/modis_ndvi/")


