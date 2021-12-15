#' @author Brian Maitner, but built from code by Qinwen and Adam

library(rgee)

# Specify where files will live
directory <- "data/raw_data/kndvi_modis/"

# Make a directory if one doesn't exist yet

  if(!dir.exists(directory)){
    dir.create(directory)
  }

# Load the image collection
  modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A1") #500 m
  # modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A2") #1 km


#Make a bounding box of the extent we want

  ext <- readRDS(file = "data/other_data/domain_extent.RDS")
  
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

# Add a kndvi band  
  
  get_kndvi <- function(img){
    
    red <- img$select("sur_refl_b01")
    nir <- img$select("sur_refl_b02")
    
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
      select(0)$rename("KNDVI")$
      set('system:time_start',img$get('system:time_start'))$ #these last lines just copy over metadata I thought might be useful
      set('system:time_end',img$get('system:time_end'))
    
    img$addBands(kndvi)
    
    
  }
  
modis_kndvi <- modis_ndvi$map(get_kndvi)

Map$addLayer(modis_kndvi$first()$select("KNDVI"),visParams = ndviviz)
  

#MODIS makes it simple to filter out poor quality pixels thanks to a quality control bits band (DetailedQA).
#The following function helps us to distinct between good data (bit == …00) and marginal data (bit != …00).

  getQABits <- function(image, qa) {
    # Convert binary (character) to decimal (little endian)
    qa <- sum(2^(which(rev(unlist(strsplit(as.character(qa), "")) == 1))-1))
    # Return a mask band image, giving the qa value.
    image$bitwiseAnd(qa)$lt(1)
  }

#Using getQABits we construct a single-argument function (mod13A2_clean)
#that is used to map over all the images of the collection (modis_ndvi).

  mod13A1_clean <- function(img) {
    # Extract the NDVI band
    kndvi_values <- img$select("KNDVI")
    
    # Extract the quality band
    ndvi_qa <- img$select("SummaryQA")
    
    # Select pixels to mask
    quality_mask <- getQABits(ndvi_qa, "11")
    
    # Mask pixels with value zero.
    ndvi_values$updateMask(quality_mask)
    
    
  }


# Clean the dataset

kndvi_clean <- modis_kndvi$map(mod13A1_clean)

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
  ndvi_clean_and_new <- ndvi_clean$filterDate(start = paste(as.Date(newest+1),sep = ""),
                                              opt_end = paste(format(Sys.time(), "%Y-%m-%d"),sep = "") ) #I THINK I can just pull the most recent date, and then use this to download everything since then

#Download
  ee_imagecollection_to_local(ic = ndvi_clean_and_new,
                              region = sabb,
                              dsn = directory)
