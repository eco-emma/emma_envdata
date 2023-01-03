
library(rgee)
library(tidyverse)

#' @description This function will download kndvi layers (derived from MODIS 16 day products), skipping any that have been downloaded already.
#' @author Brian Maitner, but built from code by Qinwen, Adam, and the KNDVI ms authors
#' @param temp_directory The directory the fire layers should be saved to prior to releasing, defaults to "data/raw_data/kndvi_modis/"
#' @param tag tag to be used for the Github release
#' @param domain domain (sf polygon) used for masking
#' @param max_layers the maximum number of layers to download at once.  Set to NULL to ignore.  Default is 50
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy
#' @import rgee
get_release_kndvi_modis <- function(temp_directory = "data/temp/raw_data/kndvi_modis/",
                                    tag = "raw_kndvi_modis",
                                    domain,
                                    max_layers = 50,
                                    sleep_time = 1) {


  #  #Ensure directory is empty if it exists

  if(dir.exists(temp_directory)){
    unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
  }


  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }

  #Make sure there is a release by attempting to create one.  If it already exists, this will fail

    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  tag),
             error = function(e){message("Previous release found")})



  #Initialize earth engine (for targets works better if called here)

    ee_Initialize()

  # Load the image collection

    modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A1") #500 m
    # modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A2") #1 km


  #Format the domain

    domain <- sf_as_ee(x = domain)
    domain <- domain$geometry()

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

  #Get a list of files already released

    released_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                               tag = tag)

    released_files$date <- gsub(pattern = ".tif",
                                replacement = "",
                                x = released_files$file_name)

    released_files <-
    released_files %>%
      dplyr::filter(file_name != "") %>%
      dplyr::filter(file_name != "log.csv")


  #check to see if any images have been downloaded already

    if(nrow(released_files) == 0){

      newest <- lubridate::as_date(-1) #if nothing is downloaded, start in 1970

    }else{

      newest <- max(lubridate::as_date(released_files$date)) #if there are images, start with the most recent

    }


  #Filter the data to exclude anything you've already downloaded (or older)

    kndvi_clean_and_new <- kndvi_clean$filterDate(start = paste(as.Date(newest+1),sep = ""),
                                                  opt_end = paste(format(Sys.time(), "%Y-%m-%d"),sep = "") ) #I THINK I can just pull the most recent date, and then use this to download everything since then

  # Function to optionally limit the number of layers downloaded at once
  ## Note that this code is placed before the gain and offset adjustment, which removes the metadata needed in the date filtering

  if(!is.null(max_layers)){

    info <- kndvi_clean_and_new$getInfo()
    to_download <- unlist(lapply(X = info$features, FUN = function(x){x$properties$`system:index`}))
    to_download <- gsub(pattern = "_", replacement = "-", x = to_download)

    if(length(to_download) > max_layers){
      kndvi_clean_and_new <- kndvi_clean_and_new$filterDate(start = to_download[1],
                                                            opt_end = to_download[max_layers+1])

    }


  }# end if maxlayers is not null


  # This section causes errors in later layer (since early 2022).  Despite months of an open ticket on earth engine, the issue persists so I'll do it with R instead
  # #Adjust gain and offset
  #   adjust_gain_and_offset <- function(img){
  #     img$add(1)$multiply(100)$round()
  #
  #   }
#
#
#   kndvi_clean_and_new <- kndvi_clean_and_new$map(adjust_gain_and_offset)


  # Check if anything to download

    if(length(kndvi_clean_and_new$getInfo()$features) == 0 ){

      message("Releases are already up to date.")
      return(max(gsub(pattern = "_",replacement = "-",x = released_files$date))) #return the last date that had been done

    }


  #Download

  tryCatch(expr = ee_imagecollection_to_local(ic = kndvi_clean_and_new,
                                              region = domain,
                                              dsn = temp_directory,
                                              formatOptions = c(cloudOptimized = true)), #not sure the cloudOptimized is specified correctly
           error = function(e){
             message("\ Captured an error in rgee/earth engine processing of KNDVI.")
             }
  )



  #Push files to release

  # Get a lost of the local files

    local_files <- data.frame(local_filename = list.files(path = temp_directory,
                                                          recursive = TRUE,
                                                          full.names = TRUE))

    # end things if nothing was downloaded

      if(nrow(local_files) == 0){
        message("Nothing downloaded")
        return(max(gsub(pattern = "_",replacement = "-",x = released_files$date))) #return the last date that had been done
      }


    # Get a lost of the local files
      local_files <- data.frame(local_filename = list.files(path = temp_directory,
                                                            recursive = TRUE,
                                                            full.names = TRUE))



      # loop through and release everything

      for( i in 1:nrow(local_files)){

        # adjusting gain and offset
        # Note: this section could be omitted if earth engine fixes their modis import

        # load the file

        rast_i  <- terra::rast(local_files$local_filename[i])

        # reformat
          rast_i <- ((rast_i + 1)*100) %>%
            round()

        # save

        terra::writeRaster(x = rast_i,
                           filename = local_files$local_filename[i],
                           overwrite=TRUE)

        #cleanup
        rm(rast_i)

        # End gain and offset bit

        Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

        pb_upload(file = local_files$local_filename[i],
                  repo = "AdamWilsonLab/emma_envdata",
                  tag = tag)

      } # end i loop


  # Delete temp files
    unlink(x = gsub(pattern = "/$", replacement = "", x = temp_directory), #sub used to delete any trailing slashes, which interfere with unlink
           recursive = TRUE)

  # End

    message("Finished Downloading KNDVI layers")

    local_files %>%
      filter(grepl(pattern = ".tif$",x = local_filename)) %>%
      mutate(date_format = basename(local_filename)) %>%
      mutate(date_format = gsub(pattern = ".tif",replacement = "",x = date_format)) %>%
      mutate(date_format = gsub(pattern = "_",replacement = "-",x = date_format)) %>%
      mutate(date_format = lubridate::as_date(date_format))%>%
      dplyr::select(date_format) -> local_files

    return(as.character(max(local_files$date_format))) # return the date of the latest file that was updated


}# End get_kndvi fx







