
library(rgee)
source("R/get_domain.R")

#' @description This function will download kndvi layers (derived from MODIS 16 day products), skipping any that have been downloaded already.
#' @author Brian Maitner, but built from code by Qinwen, Adam, and the KNDVI ms authors
#' @param directory The directory the kndvi layers should be saved to, defaults to "data/raw_data/kndvi_modis/"
#' @param domain domain (sf polygon) used for masking
#' @import rgee
get_kndvi_modis <- function(directory = "data/raw_data/kndvi_modis/", domain) {


  # Make a directory if one doesn't exist yet

    if(!dir.exists(directory)){
      dir.create(directory,recursive = TRUE)
    }

  #Initialize earth engine (for targets works better if called here)
    ee_Initialize()

  # Load the image collection
    modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A1") #500 m
    # modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A2") #1 km


  #Format the domain
    domain <- sf_as_ee(x = domain)
    domain <- domain$geometry()


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

  #Map$addLayer(modis_kndvi$first()$select("KNDVI"),visParams = ndviviz)


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
      kndvi_values$updateMask(quality_mask)


    }


  # Clean the dataset

    kndvi_clean <- modis_kndvi$map(mod13A1_clean)

  #What has been downloaded already?

    images_downloaded <- list.files(directory,
                                    full.names = F,
                                    pattern = ".tif")

    images_downloaded <- gsub(pattern = ".tif",
                              replacement = "",
                              x = images_downloaded,
                              fixed = T)

  #check to see if any images have been downloaded already
  if(length(images_downloaded) == 0){

    newest <- lubridate::as_date(-1) #if nothing is downloaded, start in 1970

  }else{

    newest <- max(lubridate::as_date(images_downloaded)) #if there are images, start with the most recent

  }


  #Filter the data to exclude anything you've already downloaded (or older)
  kndvi_clean_and_new <- kndvi_clean$filterDate(start = paste(as.Date(newest+1),sep = ""),
                                              opt_end = paste(format(Sys.time(), "%Y-%m-%d"),sep = "") ) #I THINK I can just pull the most recent date, and then use this to download everything since then


  #Adjust gain and offset
  adjust_gain_and_offset <- function(img){
    img$add(1)$multiply(100)$round()

  }


  kndvi_clean_and_new <- kndvi_clean_and_new$map(adjust_gain_and_offset)

  #Download
  ee_imagecollection_to_local(ic = kndvi_clean_and_new,
                              region = domain,
                              dsn = directory,
                              formatOptions = c(cloudOptimized = true)) #not sure the cloudOptimized is specified correctly



  message("Finished Downloading KNDVI layers")
  return(invisible(NULL))


}# End get_kndvi fx







