#MCD64A1 v006

library(rgee)

#Below I've modified some existing code to mask any data that isn't land data with sufficient information available
#There are additional filters we can apply using the QA data if we like, but this seems like a good start


#' @param image a QA image
#' @param qa binary numeric (e.g. 111 or 01) corresponding the QA settings to use. Note that this assumes you're starting with bit zero and doesn't handle shifts
#' @return an image resulting from the bitwiseAnd.  This can be transformed into a binary mask using $eq() or similar rgee functions
getQABits_match <- function(image, qa) {

  # Convert binary (character) to integer
  qa <- sum(2^(which(rev(unlist(strsplit(as.character(qa), "")) == 1))-1))

  # Return a mask band image, giving the qa value.
  image$bitwiseAnd(qa)



}


#' @param img A MCD64A1 rgee image,
#' @note this function sets the mask to ignore any date without bits zero and one ==1 (i.e. it ignores data from water and bad data)
MCD64A1_clean <- function(img) {
  # Extract the NDVI band
  fire_values <- img$select("BurnDate")

  # Extract the quality band
  fire_qa <- img$select("QA")

  # Compare the QA scores for the first two bits to a value of 1,1
  quality <- getQABits_match(fire_qa, "11")

  # Create a mask.  Since we only want cells that match both criteria, the bitwise logical for this is 1,1 (yes,yes).
  #The bitwise logical 1,1 translates to an integer value of 3, so we'll mask to everything that equals 3
  quality <- quality$eq(3)

  # Limit our observations to only pixels that have values of 1,1 for the first bits, per the binary "quality" raster (1=good, 0 = bad).
  fire_values$updateMask(quality)

  #Map$addLayer(fire_values)
}


#' @description This function will download fire layers (derived from MODIS 16 day products), skipping any that have been downloaded already.
#' @author Brian Maitner
#' @param directory The directory the fire layers should be saved to, defaults to "data/raw_data/fire_modis/"
#' @param domain domain (sf polygon) used for masking
#' @param max_layers the maximum number of layers to download at once.  Set to NULL to ignore.  Default is 50
#' @import rgee
get_fire_modis <- function(directory = "data/raw_data/fire_modis/", domain, max_layers = 50) {

  # make a directory if one doesn't exist yet

    if(!dir.exists(directory)){
      dir.create(directory, recursive = TRUE)
    }

  # Initialize earth engine (for targets works better if called here)
    ee_Initialize()

  # Load ee image collection

    modis_fire <- ee$ImageCollection("MODIS/006/MCD64A1")

  #Format the domain

    domain <- sf_as_ee(x = domain)
    domain <- domain$geometry()

  # # get metadata
  #
  #   info <- modis_fire$getInfo()
  #
  # # Set Visualization parameters
  #
  #   fireviz <- list(
  #     min = info$properties$visualization_0_min,
  #     max = info$properties$visualization_0_max,
  #     palette = c('00FFFF','FF00FF')
  #   )

  # Clean data using QA

    fire_clean <- modis_fire$map(MCD64A1_clean)

  #What has been downloaded already?

    images_downloaded <- list.files(directory,
                                    full.names = F,
                                    pattern = ".tif")

    images_downloaded <- gsub(pattern = ".tif",
                              replacement = "",
                              x = images_downloaded,
                              fixed = T)

  # check to see if any images have been downloaded already

    if(length(images_downloaded) == 0){

      newest <- lubridate::as_date(-1) #if nothing is downloaded, start in 1970

    }else{

      newest <- max(lubridate::as_date(images_downloaded)) #if there are images, start with the most recent

    }


  # Filter the data to exclude anything you've already downloaded (or older)
    fire_new_and_clean <- fire_clean$filterDate(start = paste(as.Date(newest+1),sep = ""),
                                                opt_end = paste(format(Sys.time(), "%Y-%m-%d"),sep = "") )


  # Function to optionally limit the number of layers downloaded at once

      if(!is.null(max_layers)){

        info <- fire_new_and_clean$getInfo()
        to_download <- unlist(lapply(X = info$features,FUN = function(x){x$properties$`system:index`}))
        to_download <- gsub(pattern = "_",replacement = "-",x = to_download)

        if(length(to_download) > 100){
          fire_new_and_clean <- fire_new_and_clean$filterDate(start = to_download[1],
                                                              opt_end = to_download[max_layers+1])

        }


      }



  # Download
    ee_imagecollection_to_local(ic = fire_new_and_clean,
                                region = domain,
                                dsn = directory)

    # ee_imagecollection_to_local(ic = fire_new_and_clean,
    #                             region = domain,
    #                             dsn = directory,
    #                             formatOptions = c(cloudOptimized = true))

    # # Cleanup
    #
    #   rm(fireviz, info, modis_fire)

    # End

      message("\nFinished download MODIS fire layers")
      return(invisible(NULL))



} #end fx





###################################

#Code for double-checking that masks and things seem to function appropriately

# ee_print(modis_fire)
#
# #This function was adapted from code on the rgee help pages and converts binary to and integer value
# bin_to_integer <- function(x){sum(2^(which(rev(unlist(strsplit(as.character(x), "")) == 1))-1))}
#
#
# #make lookup table (faster than apply)
#   lookup <-
#     data.frame(values=unique(getValues(first_qa)),
#                t(sapply(X = unique(getValues(first_qa)),
#                         FUN = function(x){intToBits(x)[1:8]})))
#
#   colnames(lookup)[2:9] <- 0:7
#
# #convert 5-7 to integer
#   lookup$"5to7" <-
#     apply(X = lookup[7:9],
#           MARGIN = 1,
#           FUN = function(x){out <- bin_to_integer(x = rev(as.numeric(x)))})
#
# #check that cells flagged with burn dates at margins do indeed have said burn dates
#
#   first_qa <- ee_as_raster(image = modis_fire$first()$select("QA"),
#                            region = sabb,
#                            dsn = "first_fire_qa")
#
#   first_burndate <- ee_as_raster(image = modis_fire$first()$select("BurnDate"),
#                                  region = sabb,
#                                  dsn = "first_fire_burndate")
#
#   first_burndate[which(getValues(first_qa)==99)]

#ok, this suggests everything is correct:
# since the 5to7 column value of 3 corresponds to a date at the margins of the measurements,
# and shows up where burndate = 0

###################################################################################
# # Bit(s) Meaning
#   Bit 0: Land/water
#     0: Water grid cell
#     1: Land grid cell
#   Bit 1: Valid data flag. A value of 1 indicates that there was sufficient valid data in the reflectance time series for the grid cell to be processed. (NB Water grid cells will always have this bit clear.)
#     0: Insufficient valid data
#     1: Sufficient valid data
#   Bit 2: Shortened mapping period. This flag indicates that the period of reliable mapping does not encompass the full one-month product period, i.e., burns could not be reliably mapped over the full calendar month.
#     0: Mapping period not shortened
#     1: Mapping period shortened
#   Bit 3: Grid cell was relabeled during the contextual relabeling phase of the algorithm.
#     0: Grid cell was not relabeled
#     1: Grid cell was relabeled
#   Bit 4: Spare bit
#     0: N/A
#   Bits 5-7: Special condition code reserved for unburned grid cells. This code provides an explanation for any grid cells that were summarily classified as unburned by the detection algorithm due to special circumstances.
#     0: None or not applicable (i.e., burned, unmapped, or water grid cell).
#     1: Valid observations spaced too sparsely in time.
#     2: Too few training observations or insufficient spectral separability between burned and unburned classes.
#     3: Apparent burn date at limits of time series.
#     4: Apparent water contamination.
#     5: Persistent hot spot.
#     6: Reserved for future use.
#     7: Reserved for future use.

#############################################
#
# #Bits in R and other exploratory stuff
#
#   #R can also handle bitwise operations using e.g. bitwAnd
#   #Note that if we didn't want to match starting with the first we need to use bitShift
#
# # Below is a function that takes in a raster image and returns a lookup table corresponding to page 9 of the MCD64A1 user guide
#
#   #This function converts binary numbers to integers (e.g. 11 becomes 3)
#     bin_to_integer <- function(x){sum(2^(which(rev(unlist(strsplit(as.character(x), "")) == 1))-1))}
#
#   #This function takes in a raster of the modis QA layers and spits out a lookup table of the data
#   # this loookup table corresponds to page 9 of the MCD64A1 documentation.
#   MCD64A1_QA_lookup_table <- function(qa_raster){
#
#       lookup <-
#         data.frame(values=unique(getValues(qa_raster)),
#                    t(sapply(X = unique(getValues(qa_raster)),
#                             FUN = function(x){intToBits(x)[1:8]})))
#
#       colnames(lookup)[2:9] <- 0:7
#
#     #convert 5-7 to integer.  This step is necessary because bits 5-7 are used to encode non-binary information.  So we have to translate back into the integer values
#
#       lookup$"5to7" <-
#         apply(X = lookup[7:9],
#               MARGIN = 1,
#               FUN = function(x){out <- bin_to_integer(x = rev(as.numeric(x)))})
#
#     #lookup <- lookup[-7:-9]
#     return(lookup)
#
#
#   }
#
# # Apply the above function to an image
#
# first_qa <- ee$ImageCollection("MODIS/006/MCD64A1")$first()$select("QA")
# first_qa_raster <- ee_as_raster(image = first_qa,
#                                 region = sabb,
#                                 dsn = "docker_volume/temp_data/") #save this in a temp folder so I remember to delete it
#
# lookup <- MCD64A1_QA_lookup_table(qa_raster = first_qa_raster)
#
# ltable <- table(getValues(first_qa_raster))
# ltable <- as.data.frame(ltable)
# lookup <-
# merge(x = lookup,
#       y = ltable,
#       by.x="QA",by.y = "Var1")
#
#
#   # column QA refers to the integer value of the QA band
#   # columns 0-4 are the binary bits
#   # column "5to7" is the integer value encoded in columns 5-7
#
#   # so, from the table, we see that an integer value of 71 on the QA band means:
#     # the value was on land,
#     # there was suffient data,
#     # the mapping period was shortened,
#     # the grid cell was not relabeled, and
#     # there were issues with the training observation or spectral seperability

#############################
