# Get MODIS NDVI dates


#' @author Brian Maitner, but built from code by Qinwen and Adam

#Load packages
library(rgee)
library(raster)
library(lubridate)

#Make a directory
if(!dir.exists("docker_volume/raw_data/modis_ndvi_dates")){
  dir.create("docker_volume/raw_data/modis_ndvi_dates")
}

ee_Initialize(drive = TRUE)

modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A2")

#Make a bounding box of the extent we want

  ext <- readRDS(file = "docker_volume/other_data/domain_extent.RDS")

  sabb <- ee$Geometry$Rectangle(
    coords = c(ext@xmin,ext@ymin,ext@xmax,ext@ymax),
    proj = "EPSG:4326",
    geodesic = FALSE
  )

  rm(ext)


#So, in order to convert to to integer, I can do:
  #ymd(year) + DayOfYear - 1 (need to subtract 1 since values start with 1, not zero)


#MODIS makes it simple to filter out poor quality pixels thanks to a quality control bits band (DetailedQA).
#The following function helps us to distinct between good data (bit == …00) and marginal data (bit != …00).

  getQABits <- function(image, qa) {
    # Convert binary (character) to decimal (little endian)
    qa <- sum(2^(which(rev(unlist(strsplit(as.character(qa), "")) == 1))-1))
    # Return a mask band image, giving the qa value.
    image$bitwiseAnd(qa)$lt(1)
  }

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


#Clean the dataset

  ndvi_clean <- modis_ndvi$map(mod13A2_clean)


########################################


#So, we want a function that takes in an image and returns the data as integer format

    get_integer_composite_date <-function(img) {

    # extract the DayOfYear band
      day_values <- img$select("DayOfYear")
      # Get the first day of the year and convert to an integer.

      #the next three lines of code need to be modified to work in gee
        start_date <- rgee::ee_get_date_img(img)$time_start #can't use R code with map
        #start_date_ms <- img$getInfo()$properties$`system:index` #get the start date
        #start_date <- ee$Image$getInfo(img)$properties$`system:index`

        focal_origin <- lubridate::floor_date(x = start_date,unit = "years") #this gets the first date of the year.  all modis dates are relative to this
        #focal_origin <- paste(strsplit(x = start_date_ms,split = "_")[[1]][1],"-01-01",sep = "")

        focal_origin <- as.numeric(as.Date(focal_origin))-1 #1 is subtracted so that a value of 1 on the raster corresponds to a Jan 1, not Jan 2

    #Mask to only values greater than zero.
      #Personal note: whoever coined this term is a sadist.
      #This is the exact opposite of how a real mask works and always confuses me.

      mask <- day_values$gt(0)
      day_values <- day_values$updateMask(mask) #masked values read as 0

    # #Now, I just need to add the origin to the map
      day_values$add(focal_origin)

    }

############################################

#Since the above function doesn't work with $map() (yet...), I'll wrap it in a for loop and download the layers one by one instead
  #Note that this is temporary, and I intend to modify this to play with the burn date code as well

#get a list of all dates or ids

modis_dates <- ee_get_date_ic(modis_ndvi)

#get the transformed date layer for each

  for( i in 1:nrow(modis_dates)){


    date_i <- modis_dates$time_start[i]
    date_i <- gsub(pattern = " GMT",replacement = "",x = date_i)
    img_i <- modis_ndvi$filterDate(date_i)

    #check that theres only one layer
    if(length(img_i$getInfo()$features)!=1){stop("Too many layers")}

    #turn from collection to image
    img_i <- img_i$first()

    modis_integer_date <- get_integer_composite_date(img = img_i)

    #Code to download (code to read in burn date rasters will go here)
    ee_as_raster(image = modis_integer_date,
                 region = sabb,
                 dsn = paste("docker_volume/raw_data/modis_ndvi_dates/",
                             gsub(pattern = "-",replacement = "_",x = date_i),
                             sep = ""))




  }


################################################

  #scratch code
modis_integer_date <- get_integer_composite_date(img = img)
#modis_integer_date_collection <- modis_ndvi$map(get_integer_composite_date) #doesn't work yet
Map$addLayer(modis_integer_date,
             visParams =list(
               min = 11000,
               max = 11050,
               palette = c('00FFFF','FF00FF')
               ))


