#Precipitation
# download the version 1.2 precipitation data
# January and July for the CFR region as *.grd files? (c(1,7))

#' @author Brian Maitner

library(terra)

#' @param temp_directory Where to save the files, defaults to "data/raw_data/precipitation_chelsa/"
#' @param tag Tag for release, default is "raw_static"
#' @param domain domain (sf polygon) used for masking
#' @import terra
get_release_precipitation_chelsa <- function(temp_directory = "data/temp/raw_data/precipitation_chelsa/",
                                     tag = "raw_static",
                                     domain) {

  #make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }

  #Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

    if(getOption('timeout') < 1000){
      options(timeout = 1000)
    }

  #Transform domain to wgs84 to get the coordinates

    # domain_extent <- sf::sf_project(from = crs(domain)@projargs,
    #                                 to =   crs("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")@projargs,
    #                                 pts = t(as.matrix(extent(domain))))


  domain_tf <-
    domain %>%
    st_transform(crs("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"))


  #Download the data
    precip_vec <-
      c("01","07")

  for(i in precip_vec){

    # download files
    download.file(url = paste("https://os.zhdk.cloud.switch.ch/envicloud/chelsa/chelsa_V1/climatologies/prec/CHELSA_prec_",i,"_V1.2_land.tif",sep = ""),
                  destfile = file.path(temp_directory,paste("CHELSA_prec_",i,"_V1.2_land.tif",sep = ""))
    )

    # load
    rast_i <- terra::rast(file.path(temp_directory,paste("CHELSA_prec_",i,"_V1.2_land.tif",sep = "")))

    # crop

    rast_i <- terra::crop(x = rast_i,
                          y = ext(domain_tf))

    # mask
    rast_i <-
      terra::mask(rast_i,
                  mask = terra::vect(domain_tf))

    # save raster
    terra::writeRaster(x = rast_i,
                       filename = file.path(temp_directory,paste("CHELSA_prec_",i,"_V1.2_land.tif",sep = "")),
                       overwrite = TRUE)

    # plot
    # plot(rast_i)
    # plot(domain_tf,add=TRUE,col=NA)

    rm(rast_i)

  }

  rm(i,precip_vec)


  #Make .grd version




  sapply(X = list.files(path = file.path(temp_directory),
                        full.names = T,recursive = T,pattern = ".tif"),
         FUN = function(x){
           writeRaster(x = raster(x),
                       filename = gsub(pattern = ".tif",
                                       replacement = ".grd",
                                       fixed = T,
                                       x = x),
                       overwrite = TRUE
           )
         }
  )



  # release
  to_release <-
    list.files(path = file.path(temp_directory),
               recursive = TRUE,
               full.names = TRUE)


  to_release <-
    to_release[grepl(pattern = "CHELSA_prec_",
                     ignore.case = TRUE,
                     x = basename(to_release))]

  pb_upload(repo = "AdamWilsonLab/emma_envdata",
            file = to_release,
            tag = tag)


  # Delete directory and contents

      unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)


  #Message that things are done

    message("Finished downloading CHELSA precipitation files")
    return(Sys.Date())




}



