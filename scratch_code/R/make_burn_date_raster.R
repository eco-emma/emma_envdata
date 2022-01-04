library(raster)
library(lubridate)
library(sf)
library(fasterize)

# This script should:
  #1) mask bad fire dates
  #2) adjust burn date to the corresponding NDVI date

# Get corresponding NDVI data

  source("docker_volume/R/ndvi_modis_dates.R")

# Grab fire data
  #Ideally we can comment out the code for downloading data and leave it in ee
  source("docker_volume/R/fire_modis.R")

# Update fire data from day of the year to unix date
  # Ideally this bit will be moved to earth engine
  source("docker_volume/R/fire_doy_to_unix_date.R")
  fire_doy_to_unix_date(input_folder = "docker_volume/raw_data/fire_modis/",
                        output_folder = "docker_volume/raw_data/fire_modis_integer_date")

# Create "most recent burn date raster" matched to ndvi
  source("docker_volume/R/burn_date_to_last_burned_date.R")
  burn_date_to_last_burned_date(input_folder = "docker_volume/raw_data/fire_modis_integer_date",
                                output_folder = "docker_volume/raw_data/fire_modis_most_recent_burn_date")


# The two collections we care about are:

  #1) fire_clean  (QA checked fire data)
  #2) ndvi_integer_dates (dates relative to UNIX era corresponding to NDVI sample)

############################################################################

#Abandoned (temporarily) code below

# adjust_burndate_to_modis <- function(burn_collection,modis_collection){
#
#   #1) convert dates to integer date since unix era
#
#
#   get_integer_date_fire <-function(img) {
#
#     # 1. Extract the DayOfYear band
#     day_values <- img$select("BurnDate")
#
#     # 2. Get the first day of the year and the UNIX base date.
#     first_doy <- ee$Date(day_values$get("system:time_start"))$format("Y")
#     base_date <- ee$Date("1970-01-01")
#     # 3. Get the day diff between year start_date and UNIX date
#     daydiff <- ee$Date(first_doy)$difference(base_date,"day")
#
#     day_values <- day_values$add(daydiff$int())$copyProperties(day_values) #this step makes "day_values" and element, rather than image
#
#     day_values <- ee$Image(day_values$copyProperties(img))#this turns things back into an image
#
#     day_values<- day_values$toInt()    #this converts things to integer
#
#
#     #This is needed since system properties aren't copied
#     day_values <- day_values$set('system:index',img$get('system:index'))
#     day_values <- day_values$set('system:time_start',img$get('system:time_start'))
#     day_values <- day_values$set('system:time_end',img$get('system:time_end'))
#     day_values
#
#
#   }
#
#
#     fire_integer <- fire_clean$map(get_integer_date_fire)
#     fire_integer$getInfo()
#
#   #2) convert date to date of last burn
#       #filter by date(e.g. include only dates before the focal date), and then take max
#
#
#     most_recent_burns <- function(collection) {
#
#       #// Create an initial image.
#
#       #Here, we append metadata to the first image so we can toss it later
#       first_image <-collection$select("BurnDate")$
#         first()$
#         set("to_delete","y")$
#         set("system:index","-1") #this line might be causing problems
#
#       #first_image$getInfo() #ok
#
#       first <- ee$ImageCollection(ee$Image(first_image))
#
#       #first$getInfo() #looks good
#
#       #Write a function that appends the maximum value to that point to the raster
#       appendmax <- function(image, previous) {
#
#         #Merge the current and previous
#         image <- image$select("BurnDate")
#
#         temp_collection <- ee$ImageCollection(previous)$merge(image) #merge adds shit to system index
#
#
#         #Take the max value (i.e. the most recent fire date)
#         max_to_date <- ee$Image(temp_collection$max())
#         max_to_date <- max_to_date$copyProperties(image)
#         max_to_date <- max_to_date$
#           set('system:time_start',image$get('system:time_start'))$
#           set('system:time_end',image$get('system:time_end'))$
#           set('og_index',image$get('system:index'))
#
#
#
#
#         #Append the current image to the collection
#         max_to_date <- ee$ImageCollection(previous)$merge(ee$Image(max_to_date))
#         #max_to_date$getInfo()
#         max_to_date
#
#       }
#
#       #Apply the function using an iterate call
#       out <- ee$ImageCollection(collection$iterate(appendmax, first))
#
#       #Toss the first image (was only there to set up an ImageCollection to add to)
#       out <- out$filterMetadata("to_delete","not_equals","y")
#       #out$getInfo()
#
#
#     }
#
#     most_recent_burn_date <- most_recent_burns(fire_integer)
#     ee_print(most_recent_burn_date)
#     most_recent_burn_date$getInfo()
#
#     # Saving is a problem because earthengine adds new system:index names to new files, and in doing so makes them longer and longer
#     #Need to work around this or else deal with filenames hundreds of characters long.
#     #I did a workaround by manually iterating through dates.  The dates seem to make sense
#
#     # ee_imagecollection_to_local(ic = most_recent_burn_date,
#     #                             region = sabb,
#     #                             dsn = "docker_volume/raw_data/fire_modis_most_recent_burn_date/")
#     #
#
#
#   # So the collection "most recent burn date" seems to be what we need from the fire data
#       #might need format edits or re-thinking
#   #
#
#
#
#
#
#
# }#end fx
#
# #################
#
# #Works
#
# ##########################
# #Debugging
#
# Map$addLayer(most_recent_burn_date$first())
# mrbd_list <- ee$ImageCollection$toList(most_recent_burn_date,1000)
# Map$addLayer(ee$Image(mrbd_list$get(200)))
# #seems to work
#
