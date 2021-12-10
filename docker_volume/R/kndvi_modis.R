#' @author Brian Maitner, but built from code by Qinwen and Adam

library(rgee)

#make a directory if one doesn't exist yet

if(!dir.exists("data/raw_data/kndvi_modis")){
  dir.create("data/raw_data/kndvi_modis")
}

ee_Initialize(drive = TRUE)

#modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A2") #1 km
#modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A1") #500 m

modis_brdf <- ee$ImageCollection("MODIS/006/MCD43A4") #500 m
brdf_ndvi <- ee$ImageCollection("MODIS/MCD43A4_006_NDVI")# can use this to check


#band 1 = red
#band 2 = NIR


#get metadata

info <- modis_brdf$getInfo()
#info <- brdf_ndvi$getInfo()

ee_print(modis_brdf)

#Make a bounding box of the extent we want

ext <- readRDS(file = "docker_volume/other_data/domain_extent.RDS")

sabb <- ee$Geometry$Rectangle(
  coords = c(ext@xmin,ext@ymin,ext@xmax,ext@ymax),
  proj = "EPSG:4326",
  geodesic = FALSE
)

rm(ext)


#Set Visualization parameters

ndviviz <- list(
  min = -1,
  max = 1,
  palette = c('00FFFF','FF00FF')
)

#############################


#First, a preliminary mapping to make sure I can get NDVI correct
#########
#
# get_ndvi <- function(img){
#
#   red <- img$select("Nadir_Reflectance_Band1")
#   nir <- img$select("Nadir_Reflectance_Band2")
#
#   #(NIR - Red) / (NIR + Red)
#
#   num <- nir$subtract(red)
#   denom <- nir$add(red)
#
#   num$divide(denom)
#
# }
#
# ndvi_me <- modis_brdf$map(get_ndvi)
#
# Map$addLayer(eeObject = brdf_ndvi$first(),
#              visParams = ndviviz)
#
# Map$addLayer(eeObject = ndvi_me$first(),
#              visParams = ndviviz)
#
# #looks good
#
# Map$addLayer(eeObject = ndvi_me$first()$subtract(brdf_ndvi$first()),
#              visParams = ndviviz)#0 everywhere, so everything looks good


get_kndvi <- function(img){

  red <- img$select("Nadir_Reflectance_Band1")
  nir <- img$select("Nadir_Reflectance_Band2")

  #Commented out code below is the original ee code provided by https://doi-org.gate.lib.buffalo.edu/10.1126/sciadv.abc7447

  #// Compute D2 a rename it to d2
  #var D2 = nir.subtract(red).pow(2).select([0],['d2'])

  D2 <- nir$subtract(red)$pow(2)$select(0)$rename("d2") #note that this rename should be do-able within the select, but it seems to cause issues when rgee tries to rename a single band using select

  # // Gamma, defined as 1/sigmaˆ2
  # var gamma = ee.Number(4e6).multiply(-2.0);
  gamma <- ee$Number(4e6)$multiply(-2.0)

  # // Compute kernel (k) and KNDVI
  # var k = D2.divide(gamma).exp();

  k <- D2$divide(gamma)$exp()

  # var kndvi = ee.Image.constant(1)
  # .subtract(k).divide(
  #   ee.Image.constant(1).add(k))
  # .select([0],['knd']);

  kndvi <- ee$Image$constant(1)$
    subtract(k)$divide(
      ee$Image$constant(1)$add(k))$
    select(0)$rename("knd")

}

kndvi <- modis_brdf$map(get_kndvi)
ee_print(kndvi)
kndvi$first()$getInfo()


#Map$addLayer(eeObject = kndvi$first(),visParams = ndviviz)


#Next apply QA filters using MCD43A2 MODIS product
