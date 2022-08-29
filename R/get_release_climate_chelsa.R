#R script to download climate data (CHELSA)

#library(ClimDatDownloadR)
library(terra)

#' @author Brian Maitner
#' @description This function will download CHELSA climate data if it isn't present, and (invisibly) return a NULL if it is present
#' @param temp_directory Where to save the files, defaults to "data/raw_data/climate_chelsa/"
#' @param domain domain (sf polygon) used for masking
#' @param tag Tag for the release
#' @import ClimDatDownloadR
get_release_climate_chelsa <- function(temp_directory = "data/temp/raw_data/climate_chelsa/",
                                       tag = "raw_static",
                                       domain){

  #ensure temp directory is empty

    if(dir.exists(temp_directory)){
      unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)
    }

  #make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory,recursive = TRUE)
    }


  #Make sure there is a release by attempting to create one.  If it already exists, this will fail

    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  tag),
             error = function(e){message("Previous release found")})

  #Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

    if(getOption('timeout') < 1000){
      options(timeout = 1000)
    }


  #Transform domain to wgs84 to get the coordinates

  # domain_extent <-
  #   domain %>%
  #     st_transform(crs("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")@projargs)%>%
  #     extent()

  domain_tf <-
    domain %>%
      st_transform(crs("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")@projargs)


  # Download the data
  # Note that it would be useful to clip these to a polygon to save space
  # It would also be useful if only the relevant data could be downloaded (rather than downloading and THEN pruning)

  bio_vec <-
  c("01","02","03","04","05","06","07","08","09",
    "10","11","12","13","14","15","16","17","18","19")

  for(i in bio_vec){

    # download files
      download.file(url = paste("https://os.zhdk.cloud.switch.ch/envicloud/chelsa/chelsa_V1/climatologies/bio/CHELSA_bio10_",i,".tif",sep = ""),
                    destfile = file.path(temp_directory,paste("CHELSA_bio10_",i,"_V1.2.tif",sep = ""))
                    )

    # load
      rast_i <- terra::rast(file.path(temp_directory,paste("CHELSA_bio10_",i,"_V1.2.tif",sep = "")))

    # crop

      rast_i <- terra::crop(x = rast_i,
                  y = ext(domain_tf))

    # mask
      rast_i <-
      terra::mask(rast_i,
                  mask = terra::vect(domain_tf))

    # save raster
      terra::writeRaster(x = rast_i,
                         filename = file.path(temp_directory,paste("CHELSA_bio10_",i,"_V1.2.tif",sep = "")),
                         overwrite = TRUE)

    # plot
      # plot(rast_i)
      # plot(domain_tf,add=TRUE,col=NA)

    rm(rast_i)

  }

  rm(i,bio_vec)


    # release
      to_release <-
        list.files(path = file.path(temp_directory),
                   recursive = TRUE,
                   full.names = TRUE)


      to_release <-
        to_release[grepl(pattern = "CHELSA",
                         ignore.case = TRUE,
                         x = basename(to_release))]

        pb_upload(repo = "AdamWilsonLab/emma_envdata",
                  file = to_release,
                  tag = tag)

    # delete directory and contents
        unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)



  message("CHELSA climate files downloaded")
  return(Sys.Date())


} # end fx

