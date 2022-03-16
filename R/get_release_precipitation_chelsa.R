#Precipitation
# download the version 1.2 precipitation data
# January and July for the CFR region as *.grd files? (c(1,7))

#' @author Brian Maitner

library(ClimDatDownloadR)

#' @param temp_directory Where to save the files, defaults to "data/raw_data/precipitation_chelsa/"
#' @param tag Tag for release, default is "raw_static"
#' @param domain domain (sf polygon) used for masking
#' @import ClimDatDownloadR
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

    domain_extent <- sf::sf_project(from = crs(domain)@projargs,
                                    to =   crs("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")@projargs,
                                    pts = t(as.matrix(extent(domain))))

  # Download the data
  # Note that it would be useful to clip these to a polygon to save space
  # It would also be useful if only the relevant data could be downloaded (rather than downloading and THEN pruning)

    ClimDatDownloadR::Chelsa.Clim.download(save.location = temp_directory,
                                           parameter = "prec",
                                           month.var = c(1,7),
                                           version.var = c("1.2"),
                                           clip.extent = domain_extent[c(1,2,3,4)],
                                           clipping = TRUE,
                                           delete.raw.data = TRUE
    )


  #Rename the files


    file.rename(from = list.files(temp_directory,full.names = TRUE,recursive = TRUE,pattern = ".tif"),
                to = gsub(pattern = "_clipped",replacement = "",x = list.files(temp_directory,full.names = TRUE,recursive = TRUE,pattern = ".tif"))
    )



  #Make .grd version

      sapply(X = list.files(path = paste(temp_directory,"prec/",sep = ""),
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

  # Release file

      pb_upload(repo = "AdamWilsonLab/emma_envdata",
                file = list.files(file.path(temp_directory),
                                  recursive = TRUE,
                                  full.names = TRUE),
                tag = tag)

  # Delete directory and contents

      unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)


  #Message that things are done

    message("Finished downloading CHELSA precipitation files")
    return(invisible(NULL))




}



