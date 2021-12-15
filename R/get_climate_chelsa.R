#R script to download climate data (CHELSA)

library(ClimDatDownloadR)

#' @author Brian Maitner
#' @description This function will download CHELSA climate data if it isn't present, and (invisibly) return a NULL if it is present
#' @import ClimDatDownloadR
get_climate_chelsa <- function(){

  #make a directory if one doesn't exist yet

    if(!dir.exists("data/raw_data/chelsa")){
      dir.create("data/raw_data/chelsa")
    }

  #Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

    if(getOption('timeout') < 1000){
      options(timeout = 1000)
    }


  #Get the extent
  ext <- readRDS(file = "data/other_data/domain_extent.RDS")

  if( length(list.files("data/raw_data/chelsa/",recursive = T)) == 19){
    message("CHELSA files found, skipping download")
    return(invisible(NULL))
    }



# Download the data
  # Note that it would be useful to clip these to a polygon to save space
  # It would also be useful if only the relevant data could be downloaded (rather than downloading and THEN pruning)


  ClimDatDownloadR::Chelsa.Clim.download(save.location = "data/raw_data/chelsa/",
                                         parameter = "bio",
                                         clip.extent = ext[1:4],
                                         clipping = TRUE,
                                         delete.raw.data = TRUE
  )

  dirs <- list.dirs("data/raw_data/chelsa/bio/",
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


  message("CHELSA files downloaded")
  return(invisible(NULL))


} # end fx

