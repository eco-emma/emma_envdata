library(rgee)
library(piggyback)
library(tidyverse)

#' @description This function will download the mean NDVI for the available time series across the domain
#' @author Brian Maitner
#' @param temp_directory The directory the fire layers should be saved to prior to releasing, defaults to "data/raw_data/mean_ndvi_modis/"
#' @param tag tag to be used for the Github release
#' @param domain domain (sf polygon) used for masking
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy
#' @import rgee
get_release_mean_ndvi_modis <- function(temp_directory = "data/temp/raw_data/mean_ndvi_modis/",
                                   tag = "current",
                                   domain,
                                   sleep_time = 1,
                                   json_token) {

  #  #Ensure directory is empty if it exists

    if(dir.exists(temp_directory)){
      unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
    }


  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }

  #Get release assetts

    released_assetts <- pb_list(repo = "AdamWilsonLab/emma_envdata")

  #Create releases if needed

    if(!tag %in% released_assetts$tag){

      #Make sure there is a release by attempting to create one.  If it already exists, this will fail

      tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                       tag =  tag),
               error = function(e){message("Previous release found")})

    }

  #Initialize earth engine (for targets works better if called here)
  #ee_Initialize()

  # Load the image collection
  #modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A1") #500 m
    modis_ndvi <- ee$ImageCollection('MODIS/061/MOD13A1') #500 m v 6.1
  # modis_ndvi <- ee$ImageCollection("MODIS/006/MOD13A2") #1 km


  #Format the domain
  domain <- sf_as_ee(x = domain)
  domain <- domain$geometry()

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
    ndvi_values <- img$select("NDVI")

    # Extract the quality band
    ndvi_qa <- img$select("SummaryQA")

    # Select pixels to mask
    quality_mask <- getQABits(ndvi_qa, "11")

    # Mask pixels with value zero.
    ndvi_values$updateMask(quality_mask)
  }


  # clean the dataset

    ndvi_clean <- modis_ndvi$map(mod13A1_clean)

  # take mean across dataset

    mean_ndvi <- ndvi_clean$mean()$reproject(crs = ndvi_clean$first()$projection(),
                                             scale = ndvi_clean$first()$projection()$nominalScale())

    #rgee::Map$addLayer(mean_ndvi)

  # This section causes errors in later layer (since early 2022).  Despite months of an open ticket on earth engine, the issue persists so I'll do it with R instead
  # #Adjust gain and offset.  The NDVI layer has a scale factor of 0.0001
  #   adjust_gain_and_offset <- function(img){
  #     img$add(10000)$divide(100)$round()
  #
  #   }
  # ndvi_clean_and_new <- ndvi_clean_and_new$map(adjust_gain_and_offset)


  #Download layers

    tryCatch(expr =
               ee_as_stars(image = mean_ndvi,
                           region = domain,
                           dsn = file.path(temp_directory,"mean_ndvi.tif"),
                           formatOptions = c(cloudOptimized = TRUE),
                           drive_cred_path = json_token
               ),
             error = function(e){message("Captured an error in rgee/earth engine processing of mean NDVI.")}
    )#trycatch


  #message("Done downloading mean NDVI layers for release")

  # end things if nothing was downloaded

  # if(nrow(local_files) == 0){
  #   message("Nothing downloaded")
  #   return(max(gsub(pattern = "_",replacement = "-",x = released_files$date))) #return the last date that had been done
  #
  # }

    rast_i  <- terra::rast(file.path(temp_directory,"mean_ndvi.tif"))

    # reformat

    rast_i <- ((rast_i + 10000)/100) %>%
      round()


    # check crs and update if needed

      nasa_proj <- "+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +R=6371007.181 +units=m +no_defs"

      if(!identical(crs(nasa_proj, proj = TRUE),crs(rast_i, proj = TRUE))){
        crs(rast_i) <- nasa_proj
      }


    # check extent

      if(verbose){message("Using first MODIS layer as template")}

      template <-
        released_assetts %>%
        filter(tag == "raw_ndvi_modis") %>%
        arrange(file_name) %>%
        slice_head(n=1)

      robust_pb_download(file = template$file_name[1],
                         dest = file.path(temp_directory),
                         repo =   paste(template$owner[1],
                                        template$repo[1],sep = "/"),
                         tag = template$tag[1],
                         overwrite = TRUE,
                         max_attempts = 10,
                         sleep_time = sleep_time)

      #rename the file being used as template.  This is done for rare instances where it might confict with other names

      file.rename(from = file.path(temp_directory,template$file_name[1]),
                  to = file.path(temp_directory,"template.tif"))

      template <- rast(file.path(temp_directory,"template.tif"))

      template_extent <- ext(template) |> as.character()


      # check whether the raster matches the correct extent

      if(!identical(template_extent, original_extent)){

        message("Detected error in MODIS extent, correcting")

        rast_i <- terra::resample(rast_i,y = template,method="near")

      }else{

        if(verbose){message("MEan NDVI extent looks good")}

      }





    # save

      writeRaster(x = rast_i,
                  filename = file.path(temp_directory, "mean_ndvi.temp.tif"))

      rm(rast_i)

      file.remove(file.path(temp_directory, "mean_ndvi.tif"))

      file.rename(from = file.path(temp_directory, "mean_ndvi.temp.tif"),
                  to = file.path(temp_directory,"mean_ndvi.tif"))


    # check that updates worked

      updated_raster <- terra::rast(x = file.path(temp_directory,"mean_ndvi.tif"))


      if(!identical(nasa_proj, crs(updated_raster, proj=TRUE))){
        stop("Error in fixing CRS")

      }

      if(!identical(template_extent,
                    ext(updated_raster) |> as.character())){

        message("Error in fixing extent")

      }




    # Upload

    Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

    pb_upload(file = file.path(temp_directory,"mean_ndvi.tif"),
              repo = "AdamWilsonLab/emma_envdata",
              tag = tag)


  # Delete temp files
    rm(updated_raster)

    unlink(x = file.path(temp_directory), recursive = TRUE)


    message("\nFinished Downloading mean NDVI layer")


  ndvi_clean$getInfo()$features %>%
  lapply(FUN = function(x){x$properties$`system:index`}) %>%
    unlist() %>%
    as_date() %>%
    max() -> most_recent_date

  return(as.character(most_recent_date)) # return the date of the latest file that was updated


}

