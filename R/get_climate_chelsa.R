#R script to download climate data (CHELSA)

library(ClimDatDownloadR)

#' @author Brian Maitner
#' @description This function will download CHELSA climate data if it isn't present, and (invisibly) return a NULL if it is present
#' @param directory Where to save the files, defaults to "data/raw_data/climate_chelsa/"
#' @param domain domain (sf polygon) used for masking
#' @import ClimDatDownloadR
get_climate_chelsa <- function(directory = "data/raw_data/climate_chelsa/", domain){

  #make a directory if one doesn't exist yet

    if(!dir.exists(directory)){
      dir.create(directory)
    }

  #Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

    if(getOption('timeout') < 1000){
      options(timeout = 1000)
    }


  #Transform domain to wgs84 to get the coordinates

  domain_extent <- sf::sf_project(from = crs(domain)@projargs,
                                  to =   crs("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")@projargs,
                 pts = t(as.matrix(extent(domain))))

  if( length(list.files(directory,pattern = ".tif", recursive = T)) == 19){
    message("CHELSA files found, skipping download")
    return(invisible(NULL))
    }



# Download the data
  # Note that it would be useful to clip these to a polygon to save space
  # It would also be useful if only the relevant data could be downloaded (rather than downloading and THEN pruning)


  ClimDatDownloadR::Chelsa.Clim.download(save.location = directory,
                                         parameter = "bio",
                                         clip.extent = domain_extent[c(1,2,3,4)],
                                         clipping = TRUE,
                                         delete.raw.data = TRUE
                                         )



  dirs <- list.dirs(paste(directory,"bio/",sep = ""),
                    recursive = T,
                    full.names = T)

  dirs <-dirs[grep(pattern = "clipped",x = dirs)]

  file.rename(from = dirs,
              to = paste(strsplit(x = dirs,
                                  split = "clipped")[[1]][1],
                         "clipped",
                         sep = "")
              )
  rm(dirs)


  message("CHELSA climate files downloaded")
  return(invisible(NULL))


} # end fx

