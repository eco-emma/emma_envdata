#https://books.ropensci.org/targets/walkthrough.html

#Install stuff I may not have already
  install.packages("cubelyr")

# Inspect the pipeline
  tar_manifest()

#visualize the pipeline
  tar_glimpse()
  tar_visnetwork()

#run the pipeline
  tar_make()

test <- raster::raster("data/raw_data/ndvi_modis/2000_02_18.tif")
raster::plot(test)
library(raster)
unique(getValues(test))

# Note:
  # download speed for e.g. ndvi layers much slower now.  Possibly due to new, more complex, domain?
