#Code for downloading raw data used by the EMMA project

#' @author Brian Maitner


# This code was written to work with a particular docker instance, to set it up (modifying your directory accordingly):
# docker run -d -e DISABLE_AUTH=true -p 8787:8787 -v C:/Users/"Brian Maitner"/Desktop/current_projects/emma_envdata:/home/rstudio/emma_envdata adamwilsonlab/emma:latest

#the code below would be more useful (wouldn't require the change in wd), but causes problem for installation
## docker run -d -e DISABLE_AUTH=true -p 8787:8787 -v C:/Users/"Brian Maitner"/Desktop/current_projects/emma_envdata:/home/rstudio adamwilsonlab/emma_docker:latest

# Code to ensure the directory in docker matches the directory in the github project in rstudio
if(getwd() == "/home/rstudio"){setwd("/home/rstudio/emma_envdata/")}

#Install packages not in docker image
#install.packages("bibtex", "rdryad")
#install.packages("cmdstanr", repos = c("https://mc-stan.org/r-packages/", getOption("repos")))

#Load packages
library(rgee)
library(targets)

#Initialize rgee
ee_Initialize(drive = TRUE)

#If we need to extract values, use exactextractor
library(exactextractr)

################################################################################

# Notes:

# Have single-file scripts return directory names instead of NULL

# Figure out bug in ee_imagecollection_to_local causing it to omit file names and just give things the extensions

# Note: should update code that processes unix date into most recent burn to optionally take in the SA burn polygons

# add polygon data to modis fire product

# add a function to remove the files from the rgee backup folder

#https://books.ropensci.org/targets/walkthrough.html

#Install stuff I may not have already
  install.packages("cubelyr","visNetwork","rdryad")
  install.packages("arrow")

library(targets)
library(rgee)

ee_install()
ee_Initialize()

# Inspect the pipeline
  tar_manifest()

#visualize the pipeline
  tar_glimpse(level_separation = 200)
  tar_visnetwork()



curr_network <- tar_glimpse()
#curr_network <- tar_visnetwork()
htmlwidgets::saveWidget(widget = curr_network,
                        file = "scratch_code/current_network.html")
webshot::install_phantomjs()
webshot::webshot(url = "scratch_code/current_network.html",
                 file = "scratch_code/current_network.png",delay = 2,zoom = 10,vwidth = 400,vheight = 200)


?webshot
#run the pipeline
  tar_make()

  #tar_destroy("meta",ask = FALSE)

##################

#need to update rgee functions to use correct filename if only one layer
#need to update rgee functions to skip download if there is nothing TO download (since it takes a while to upload the domain)


###########################


library(arrow)
# Example code for working with arrow library


x <- open_dataset(sources = "data/processed_data/dynamic_parquet/")

x$schema
x$metadata

x  %>%
  filter(variable != "ndvi")%>%
  filter(date == 11261)%>%
  summarise(mean = mean(value))%>%
  head() %>%
  collect()

