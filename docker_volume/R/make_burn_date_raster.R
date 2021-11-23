library(raster)
library(lubridate)
library(sf)
library(fasterize)

#This script should:
  #1) mask bad fire dates
  #2) adjust burn date to the corresponding NDVI date

#Get corresponding NDVI data

  source("docker_volume/R/ndvi_modis_dates.R")

#Grab fire data
  source("docker_volume/R/fire_modis.R")

#The two collections we care about are:

  #1) fire_clean  (QA checked fire data)
  #2) ndvi_integer_dates (dates relative to UNIX era corresponding to NDVI sample)


adjust_burndate_to_modis <- function(burn_collection,modis_collection){

  #1) convert dates to integer date since unix era


  get_integer_date_fire <-function(img) {

    # 1. Extract the DayOfYear band
    day_values <- img$select("BurnDate") #still works as of this line

    # 2. Get the first day of the year and the UNIX base date.
    first_doy <- ee$Date(day_values$get("system:time_start"))$format("Y")
    base_date <- ee$Date("1970-01-01")
    # 3. Get the day diff between year start_date and UNIX date
    daydiff <- ee$Date(first_doy)$difference(base_date,"day")

    day_values <- day_values$add(daydiff$int())$copyProperties(img) #this step makes "day_values" and element, rather than image

    day_values <- ee$Image(day_values$copyProperties(img))#this turns things back into an image
    day_values$toInt()    #this converts things to integer

  }


    fire_integer <- fire_clean$map(get_integer_date_fire)

  #2) convert date to date of last burn
      #filter by date(e.g. include only dates before the focal date), and then take max

    #test image
    last_fire_date <- function(img){

        #A) Get the date of the image (so we can pull older stuff)

            focal_data <- img$select("BurnDate")
            start_date <- ee$Date(focal_data$get("system:time_start"))
            end_date <- ee$Date(focal_data$get("system:time_end"))

        #B) Select the older rasters
            focal_dataset <- fire_integer$filterDate(start = "1900-01-01",
                                                     opt_end = end_date)

            focal_dataset$max()$copyProperties(img, c('system:id', 'system:time_start','system:time_end'))

    }


    fire_continuous_integer <- fire_integer$map(last_fire_date)

  #3) Convert date of last burn to time since last burn
      #corresponding modis NDVI date - burn date for corresponding image




}#end fx

#################

#Works

##########################
#Debugging max()
Map$addLayer(eeObject = fire_clean$max(),
             fireviz <- list(
               min = fire_clean$getInfo()$properties$visualization_0_min,
               max = fire_clean$getInfo()$properties$visualization_0_max,
               palette = c('00FFFF','FF00FF')
             ))#works just fine works

Map$addLayer(fire_integer$max(),
             visParams = list(
               min = 11262,
               max = 18932,
               palette = c('00FFFF','FF00FF')
             ))

#Next step: double check that the last fire date function is performing appropriately
