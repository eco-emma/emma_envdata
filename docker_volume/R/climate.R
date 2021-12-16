#R script to download climate data (CHELSA)

#' @author Brian Maitner

library(ClimDatDownloadR)


#make a directory if one doesn't exist yet

  if(!dir.exists("data/raw_data/chelsa")){
    dir.create("data/raw_data/chelsa")
  }

#Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

  if(getOption('timeout') < 1000){
    options(timeout = 1000)
  }

# Download the data
  # Note that it would be useful to clip these to a polygon to save space
  # It would also be useful if only the relevant data could be downloaded (rather than downloading and THEN pruning)

  ClimDatDownloadR::Chelsa.Clim.download(save.location = "docker_volume/raw_data/chelsa/",
                                         parameter = "bio",
                                         clip.extent = c(16.3449768409,  32.830120477, -34.8191663551, -22.0913127581),
                                         clipping = TRUE,
                                         delete.raw.data = TRUE
                                         )

  dirs <- list.dirs("docker_volume/raw_data/chelsa/bio/",
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

#Check that everything looks good
  # library(raster)
  # test <- raster(list.files("docker_volume/raw_data/chelsa/",
  #                           pattern = "bio10_01",
  #                           full.names = T,
  #                           recursive = T))
  #
  # plot(test)
  # rm(test)
