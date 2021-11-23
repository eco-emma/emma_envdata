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
          day_values <- img$select("BurnDate")

          # 2. Get the first day of the year and the UNIX base date.
          first_doy <- ee$Date(day_values$get("system:time_start"))$format("Y")
          base_date <- ee$Date("1970-01-01")


          # 3. Get the day diff between year start_date and UNIX date
          daydiff <- ee$Date(first_doy)$difference(base_date,"day")

          # 4. Mask to only values greater than zero.
          mask <- day_values$gt(0)
          day_values <- day_values$updateMask(mask)

          # Now, I just need to add the origin to the map
          #Note the use of "copyProperties", which copies over the start and end times
          day_values$
            add(daydiff)$
            copyProperties(img, c('system:id', 'system:time_start','system:time_end'))

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
                                                     opt_end = start_date)


            focal_dataset$getInfo()
            focal_dataset$aggregate_max()


    }


  #3) Convert date of last burn to time since last burn
      #corresponding modis NDVI date - burn date for corresponding image


}#end fx

#################
