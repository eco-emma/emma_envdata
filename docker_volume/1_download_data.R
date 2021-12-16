#Code for downloading raw data used by the EMMA project

  #' @author Brian Maitner


  #This code was written to work with a particular docker instance, to set it up (modifying your directory accordingly):
  #docker run -d -e DISABLE_AUTH=true -p 8787:8787 -v C:/Users/"Brian Maitner"/Desktop/current_projects/emma_targets:/home/rstudio/emma_targets adamwilsonlab/emma_docker:latest

  #the code below would be more useful (wouldn't require the change in wd), but causes problem for installation
  ##docker run -d -e DISABLE_AUTH=true -p 8787:8787 -v C:/Users/"Brian Maitner"/Desktop/current_projects/emma_targets:/home/rstudio adamwilsonlab/emma_docker:latest

# Code to ensure the directory in docer matches the directory in the github project in rstudio
  if(getwd()=="/home/rstudio"){setwd("/home/rstudio/emma_targets/")}


#Install packages (note: better to make these part of the docker image)
  install.packages(c("gdalUtils","qpdf","RefManageR","svMisc","bibtex","raster","rdryad","geojsonio"))
  install.packages("https://gitlab.rrz.uni-hamburg.de/helgejentsch/climdatdownloadr/-/archive/master/climdatdownloadr-master.tar.gz", repos = NULL, type = "source")

library(rgee)

#To run once
  #Again, would be better to make these part of the docker
  ee_install(confirm = FALSE) #note: would probably be faster to update the image to contain python, numpy, etc
  .rs.restartR() #this is needed to restart R after the installations that comes in the preceding line of code
  ee_clean_pyenv()

  ee_install_upgrade()

  ee_Initialize(drive = TRUE)


#Elevation (NASADEM)
  #source("docker_volume/R/elevation.R") #this will take a while
  sadem <- raster("docker_volume/raw_data/NASADEM.tif")

#Climate (CHELSA)
  #source("docker_volume/R/climate.R")

#Precipitation
  #source("docker_volume/R/precipitation_chelsa.R")


#ALOS variables from GEE - TPI, insolation, landforms, mTPI, diversity, CHILI



