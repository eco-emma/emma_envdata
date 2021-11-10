#script for learning rgee

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
