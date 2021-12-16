#GCFR soil layers (Cramer et al. 2019) - https://doi.org/10.5061/dryad.37qc017

#' @author Brian Maitner

library(rvest)
library(rdryad)

# Set up directories if need be
  if(!dir.exists("docker_volume/raw_data/soil_gcfr")){
    dir.create("docker_volume/raw_data/soil_gcfr")
  }


# Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

  if(getOption('timeout') < 1000){
    options(timeout = 1000)
  }


#Download the files from dryad
  locations <- dryad_download(dois = "10.5061/dryad.37qc017")

# Move the files to a permanent location (rdryad doesn't give you an option)
  file.copy(from = locations[[1]],
            to = "docker_volume/raw_data/soil_gcfr/",
            overwrite = TRUE)

# Delete the old copies from the temporary location
  file.remove(locations[[1]])

# Clean up
  rm(locations)
