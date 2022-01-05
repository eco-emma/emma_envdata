#Code for downloading raw data used by the EMMA project

  #' @author Brian Maitner


  # This code was written to work with a particular docker instance, to set it up (modifying your directory accordingly):
    # docker run -d -e DISABLE_AUTH=true -p 8787:8787 -v C:/Users/"Brian Maitner"/Desktop/current_projects/emma_targets:/home/rstudio/emma_targets adamwilsonlab/emma:latest

  #the code below would be more useful (wouldn't require the change in wd), but causes problem for installation
    ## docker run -d -e DISABLE_AUTH=true -p 8787:8787 -v C:/Users/"Brian Maitner"/Desktop/current_projects/emma_targets:/home/rstudio adamwilsonlab/emma_docker:latest

# Code to ensure the directory in docker matches the directory in the github project in rstudio
  if(getwd() == "/home/rstudio"){setwd("/home/rstudio/emma_targets/")}

#Install packages not in docker image
  install.packages("bibtex", "rdryad")

#Load packages
  library(rgee)

  #Initialize rgee
    ee_Initialize(drive = TRUE)

  #set up directories if needed

    if(!dir.exists("data/raw_data/")){dir.create("data/raw_data/")}
    if(!dir.exists("data/processed_data/")){dir.create("data/processed_data/")}

# Infrequent (~ annual?) updates

  #Elevation (NASADEM)
    source("R/get_elevation_nasadem.R")
    get_elevation_nasadem()

  #Climate (CHELSA)
    source("R/get_climate_chelsa.R")
    get_climate_chelsa()

  #Precipitation
    source("R/get_precipitation_chelsa.R")
    get_precipitation_chelsa()

  #Clouds
    source("R/get_clouds_wilson.R")
    get_clouds_wilson()

  #Landcover from ZA
    source("R/get_landcover_za.R")
    get_landcover_za()

  #ALOS variables from GEE - TPI, insolation, landforms, mTPI, diversity, CHILI
    source("R/get_alos.R")
    get_alos()

# Frequent (~ weekly - monthly) updates

  #NDVI
    source("R/get_ndvi_modis.R")
    get_ndvi()

  #KNDVI
    source("R/get_kndvi_modis.R")
    get_kndvi()

  #Fire from MODIS
    source("R/get_fire_modis.R")
    get_fire_modis()

  #NDVI dates from MODIS
    source("R/get_ndvi_dates_modis.R")
    get_ndvi_dates_modis()


#Process data (order matters)

  #Fire day-of-year to UNIX date
    source("R/process_fire_doy_to_unix_date.R")
    process_fire_doy_to_unix_date()

  #Fire UNIX date to most recent burn date
    source("R/process_burn_date_to_last_burned_date.R")
    process_burn_date_to_last_burned_date()

  #Most recent burn date to days since most recent burn (relative to NDVI dates)
    source("R/process_ndvi_relative_days_since_fire.R")
    process_ndvi_relative_days_since_fire()


################################################################################

    # Notes:

      # Modify ndvi per kndvi to be smaller files

      # Note: should update code that processes unix date into most recent burn to optionally take in the SA burn polygons

      # Note: are the "process_data" intermediates useful or should things be rolled together?  It would probably be slower but require less space

      # Note: if we need to save space and don't need the fire DOY layers or other intermediates, we can clear out all but the last layer (since the ee downloads are based on the most recent layer)

      # update Get_domain to optionally return domain as a sf object (vs ee)

      # add polygon data to modis fire product

      # add a function to remove the files from the rgee backup folder
