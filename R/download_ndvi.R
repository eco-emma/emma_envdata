library(cptcity)
library(raster)
library(stars)
library(rgee)
library(sf)
library(rgdal)

ee_Initialize(drive = TRUE)

#ee_install_upgrade()

#package_version('rgee')
#remove.packages('regee')



#Define a region of interest




roi <- ee$Geometry$Polygon(
  proj = "EPSG:4326",
  geodesic = FALSE,
  coords = list(
    c(19.5696, -33.660),
    c(18.146, -34.418),
    c(19.5696, -34.418)
    #c(18.146, -33.660)
  )
)

#roi <- ee$Geometry$Rectangle(
#  coords = c(-33.660,18.146,-34.418  ,19.5696),
#  proj = "EPSG:4326",
#  geodesic = FALSE
#)

#Search into the Earth Engine’s public data archive. We use the MOD13A2 V6 product. It is 16-day period product that provides two vegetation indices: NDVI and EVI.
#  ee_search_title("mod13") %>%
#  ee_search_title("1km") %>%
#  ee_search_display()
# seems like these ee_search functions were removed from the package.
#https://github.com/r-spatial/rgee/tree/master/R


modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A2")


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

#Filter the collection (modis_ndvi) by a date range.
#Select images only for one month
#Map over the collection (using mod13A2_clean) to remove bad pixels.
#Apply a temporal reducer function (median).


ndvi_composite <- modis_ndvi$
  filter(ee$Filter$date('2011-01-01', '2011-02-01'))$
  map(mod13A2_clean)$
  median()

#OPTIONAL: Use Map to display the results in an interactive way.

scale <- 0.0001
Map$setCenter(lon =18.83606, lat = -34.06176, zoom = 7)
Map$addLayer(
  eeObject = ndvi_composite,
  visParams = list(
    min = 0.2 / scale,
    max = 0.7 / scale,
    palette = cpt("grass_ndvi", 10)
  )
) + Map$addLayer(roi)


# To download the results we use the function ee_as_raster


#?ee_as_raster
mod_ndvi <- ee_as_raster(
  image = ndvi_composite,
  region = roi,
  scale = 1000,
  via = 'drive'
)

#?raster

##https://gist.github.com/csaybar/3f2f95790bf645a2da3ad82879bf8c39
