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

#Load packages
library(rgee)

#Initialize rgee
ee_Initialize(drive = TRUE)

#set up directories if needed

if(!dir.exists("data/raw_data/")){dir.create("data/raw_data/")}
if(!dir.exists("data/processed_data/")){dir.create("data/processed_data/")}


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

#run the pipeline
  tar_make()


##################

# gets to update

  #elevation nasa

  #landcover za

#process functions to update

  #alos

  #elevation


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

