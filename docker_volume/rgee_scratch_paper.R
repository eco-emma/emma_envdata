#Code for downloading raw data used by the EMMA project
  #This code was written to work with a particular docker instance, to set it up (modifying your directory accordingly):
  #docker run -d -e DISABLE_AUTH=true -p 8787:8787 -v C:/Users/"Brian Maitner"/Desktop/current_projects/emma_targets/docker_volume:/home/rstudio/docker_volume adamwilsonlab/emma_docker:latest



#devtools::install_github("matthewkling/chelsaDL")
install.packages(c("gdalUtils","qpdf","RefManageR","svMisc"))
install.packages("bibtex")
install.packages("https://gitlab.rrz.uni-hamburg.de/helgejentsch/climdatdownloadr/-/archive/master/climdatdownloadr-master.tar.gz", repos = NULL, type = "source")
install.packages("raster")

library(rgee)
library(ClimDatDownloadR)
#library(chelsaDL)

#To run once
ee_install() #note: would probably be faster to update the image to contain python, numpy, etc
ee_install_upgrade()



#Elevation (NASADEM)

  #source("docker_volume/R/elevation.R") #this will take a while
  sadem <- raster("docker_volume/raw_data/")

#Climate (CHELSA)
