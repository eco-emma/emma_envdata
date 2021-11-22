# Get MODIS NDVI dates


#' @author Brian Maitner, with tips from csaybar

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



########################################


  get_integer_date <-function(img) {

    # 1. Extract the DayOfYear band
      day_values <- img$select("DayOfYear")

    # 2. Get the first day of the year and the UNIX base date.
      first_doy <- ee$Date(day_values$get("system:time_start"))$format("Y")
      base_date <- ee$Date("1970-01-01")


    # 3. Get the day diff between year start_date and UNIX date
      daydiff <- ee$Date(first_doy)$difference(base_date,"day")

    # 4. Mask to only values greater than zero.
      mask <- day_values$gt(0)
      day_values <- day_values$updateMask(mask)

    # #Now, I just need to add the origin to the map
      day_values$add(daydiff)
  }

############################################

ndvi_integer_dates <- modis_ndvi$map(get_integer_date)

ee_imagecollection_to_local(ic = ndvi_integer_dates,
                            region = sabb,
                            dsn = "docker_volume/raw_data/modis_ndvi_dates/")

