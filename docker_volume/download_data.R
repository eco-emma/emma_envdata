#Code for downloading raw data used by the EMMA project
  #This code was written to work with a particular docker instance, to set it up (modifying your directory accordingly):
  #docker run -d -e DISABLE_AUTH=true -p 8787:8787 -v C:/Users/"Brian Maitner"/Desktop/current_projects/emma_targets/docker_volume:/home/rstudio/docker_volume adamwilsonlab/emma_docker:latest


#Install packages (note: better to make these part of the docker)
  install.packages(c("gdalUtils","qpdf","RefManageR","svMisc"))
  install.packages("bibtex")
  install.packages("https://gitlab.rrz.uni-hamburg.de/helgejentsch/climdatdownloadr/-/archive/master/climdatdownloadr-master.tar.gz", repos = NULL, type = "source")
  install.packages("raster")
  install.packages("rdryad")

library(rgee)
library(ClimDatDownloadR)

#To run once
  #Again, would be better to make these part of the docker
  
  ee_install(confirm = FALSE) #note: would probably be faster to update the image to contain python, numpy, etc
  .rs.restartR() #this is needed to restart R after the installations that come in the predicting line of code
  
  ee_install_upgrade()



#Elevation (NASADEM)
  #source("docker_volume/R/elevation.R") #this will take a while
  sadem <- raster("docker_volume/raw_data/NASADEM.tif")

#Climate (CHELSA)
  #source("docker_volume/R/climate.R")
  
#Precipitation
  #source("docker_volume/R/precipitation_chelsa.R")
  
  
#ALOS variables from GEE - TPI, insolation, landforms, mTPI, diversity, CHILI  
  
  
  
  