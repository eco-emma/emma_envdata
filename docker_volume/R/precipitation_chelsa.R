#Precipitation

# download the version 1.2 precipitation data
# January and July for the CFR region as *.grd files? (c(1,7))

library(ClimDatDownloadR)

#make a directory if one doesn't exist yet

  if(!dir.exists("docker_volume/raw_data/chelsa")){
    dir.create("docker_volume/raw_data/chelsa")
  }

#Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

  if(getOption('timeout') < 1000){
    options(timeout = 1000)  
  }

# Download the data
  # Note that it would be useful to clip these to a polygon to save space
  # It would also be useful if only the relevant data could be downloaded (rather than downloading and THEN pruning)

  ClimDatDownloadR::Chelsa.Clim.download(save.location = "docker_volume/raw_data/chelsa/",
                                         parameter = "prec",
                                         month.var = c(1,7),
                                         version.var = c("1.2"),
                                         clip.extent = c(16.3449768409,  32.830120477, -34.8191663551, -22.0913127581),
                                         clipping = TRUE,
                                         delete.raw.data = TRUE
                                         )

#Rename the directory

  dirs <- list.dirs("docker_volume/raw_data/chelsa/prec/",
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
  
  sapply(X = list.files(path = "docker_volume/raw_data/chelsa/prec/",full.names = T,recursive = T,pattern = ".tif"),
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





