#Precipitation
  # download the version 1.2 precipitation data
  # January and July for the CFR region as *.grd files? (c(1,7))

#' @author Brian Maitner

library(ClimDatDownloadR)


get_precipitation_chelsa <- function(directory = "data/raw_data/precipitation_chelsa/") {

  #make a directory if one doesn't exist yet

  if(!dir.exists(directory)){
    dir.create(directory)
  }

  #Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

  if(getOption('timeout') < 1000){
    options(timeout = 1000)
  }

  #Get the extent
  ext <- readRDS(file = "data/other_data/domain_extent.RDS")

  if( length(list.files(directory,pattern = ".tif",recursive = T)) == 2){
    message("CHELSA precipitation files found, skipping download")
    return(invisible(NULL))
  }

  # Download the data
  # Note that it would be useful to clip these to a polygon to save space
  # It would also be useful if only the relevant data could be downloaded (rather than downloading and THEN pruning)

  ClimDatDownloadR::Chelsa.Clim.download(save.location = directory,
                                         parameter = "prec",
                                         month.var = c(1,7),
                                         version.var = c("1.2"),
                                         clip.extent = ext[c(1,3,2,4)],
                                         clipping = TRUE,
                                         delete.raw.data = TRUE
  )

  #need to fix the extent




  #Rename the directory

  dirs <- list.dirs(directory,
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

  #Make .grd version

  sapply(X = list.files(path = paste(directory,"prec/",sep = ""),
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


  #Message that things are done
  message("Finished downloading CHELSA precipitation files")
  return(invisible(NULL))




}



