#' @author Brian Maitner, but built from code by Qinwen and Adam
#' @note the date associated with each daily V006 and V006.1 retrieval is the center of the moving 16 day input window.


library(rgee)

directory <- "data/raw_data/kndvi_modis_daily/"

#make a directory if one doesn't exist yet

  if(!dir.exists(directory)){
    dir.create(directory)
  }


#Get needed collections

  modis_brdf <- ee$ImageCollection("MODIS/006/MCD43A4") #500 m
  brdf_qa <- ee$ImageCollection("MODIS/006/MCD43A2")


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
    select(0)$rename("knd")$
    set('system:time_start',img$get('system:time_start'))$ #these last lines just copy over metadata I thought might be useful
    set('system:time_end',img$get('system:time_end'))

}

kndvi <- modis_brdf$map(get_kndvi)

#' @param img A kndvi rgee image,
#' @note this function currently sets the mask to ignore snow or anything worse than "good" data
kndvi_clean <- function(img) {

  # Extract the kNDVI band (should be the only band anyway)
    kndvi_focal <- img$select("knd")

  # Get the corresponding QA layer by filtering on start and end time
    qa_focal <- ee$ImageCollection("MODIS/006/MCD43A2")$
      filterDate(start = kndvi_focal$get("system:time_start"),
                 opt_end = kndvi_focal$get("system:time_end"))$
      first() #first call needed to convert from n = l image collection to image

  # Convert to a mask. Potential QA bands to use are:

    # "Snow_BRDF_Albedo"
      # 0 = Snow free, 1 = snow
        # excluding snow

      snow_mask <- qa_focal$select("Snow_BRDF_Albedo")$eq(0) #for the mask, valid values should be 1)

    # "BRDF_Albedo_ValidObs_Band1" and "BRDF_Albedo_ValidObs_Band2"
      #The QA data are 16 bits (0-15).  Each bit specifies whether the corresponding day was either 0 (not used) or 1 (valid data)
      # Note also that we need to make use of 2 bands (bitmasks for layers 1 and 2)
        # skipping, since this is info is summarized in BRDF_Albedo_Band_Quality_Band1

    # "BRDF_Albedo_LandWaterType"
      # Bits 0-2: Land/water type
      # 0: Shallow ocean
      # 1: Land (nothing else but land)
      # 2: Ocean coastlines and lake shorelines
      # 3: Shallow inland water
      # 4: Ephemeral water
      # 5: Deep inland water
      # 6: Moderate or continental ocean
      # 7: Deep ocean
        # Skipping, since we can filter out water later

    #"BRDF_Albedo_Band_Quality_Band1" and "BRDF_Albedo_Band_Quality_Band2"
      # 0: Best quality, full inversion (WoDs and RMSE are good)
      # 1: Good quality, full inversion (also including the cases with no clear sky observations over the day of interest and those with a Solar Zenith Angle that is > 70 degrees even though WoDs and RMSE majority are good)
      # 2: Magnitude inversion (numobs ≥ 7)
      # 3: Magnitude inversion (numobs ≥ 2 & < 7)
      # 4: Fill value
        # excluding anything worse than "good" (i.e. values above 1)

      red_qa_mask <- qa_focal$select("BRDF_Albedo_Band_Quality_Band1")$lte(1) #for the mask, valid values should be 1)

      nir_qa_mask <- qa_focal$select("BRDF_Albedo_Band_Quality_Band2")$lte(1) #for the mask, valid values should be 1)

  #Apply the masks
      img$updateMask(snow_mask)$updateMask(red_qa_mask)$updateMask(nir_qa_mask)

}

kndvi_cleaned <- kndvi$map(kndvi_clean)

  #Map$addLayer(kndvi$filterDate("2010-07-01")$first(),visParams = ndviviz)
  #Map$addLayer(kndvi_cleaned$filterDate("2010-07-01")$first(),visParams = ndviviz)


stop("Add code here for temporal aggregation to 16 days")

  #requires an ee reducer
    #reducers use mask for weighting by default, but can use other things  (i.e. metrics of quality)

# Finally, download what is needed


#What has been downloaded already?

images_downloaded <- list.files(directory,full.names = F,pattern = ".tif")
images_downloaded <- gsub(pattern = ".tif",replacement = "",x = images_downloaded,fixed = T)

#check to see if any images have been downloaded already
if(length(images_downloaded)==0){

  newest <- lubridate::as_date(-1) #if nothing is downloaded, start in 1970

}else{

  newest <- max(lubridate::as_date(images_downloaded)) #if there are images, start with the most recent

}


#Filter the data to exclude anything you've already downloaded (or older)
kndvi_clean_and_new <- kndvi_cleaned$filterDate(start = paste(as.Date(newest+1),sep = ""),
                                            opt_end = paste(format(Sys.time(), "%Y-%m-%d"),sep = "") )

#Download
ee_imagecollection_to_local(ic = kndvi_clean_and_new,
                            region = sabb,
                            dsn = directory)


###############################################


# Preliminary mapping used to make sure I could get NDVI right (since it uses the same data as kndvi)

# brdf_ndvi <- ee$ImageCollection("MODIS/MCD43A4_006_NDVI")# can use this to check calculations of ndvi
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
