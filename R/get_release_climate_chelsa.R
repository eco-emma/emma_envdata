#R script to download climate data (CHELSA)

library(terra)
library(ncdf4)

#' @author Brian Maitner & Adam Wilson
#' @description This function will download CHELSA climate data if it isn't present, and (invisibly) return a NULL if it is present
#' @param temp_directory Where to save the files, defaults to "data/raw_data/climate_chelsa/"
#' @param domain domain (sf polygon) used for masking
#' @param tag Tag for the release
#' @import terra
get_release_climate_chelsa <- function(temp_directory = "data/temp/raw_data/climate_chelsa/",
                                       tag = "raw_static",
                                       domain){

  #ensure temp directory is empty

    if(dir.exists(temp_directory)){
      unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)
    }

  #make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory,recursive = TRUE)
    }


  #Make sure there is a release by attempting to create one.  If it already exists, this will fail

    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  tag),
             error = function(e){message("Previous release found")})

  #Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

    if(getOption('timeout') < 1000){
      options(timeout = 1000)
    }


  #Transform domain to wgs84 to get the coordinates

  # domain_extent <-
  #   domain %>%
  #     st_transform(crs("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")@projargs)%>%
  #     extent()

  domain_tf <-
    domain %>%
    st_as_sf() %>%
      sf::st_transform(crs("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"))

  # Download the data
  # Note that it would be useful to clip these to a polygon to save space
  # It would also be useful if only the relevant data could be downloaded (rather than downloading and THEN pruning)

  # CF-compliant metadata for CHELSA bioclimatic variables
  bio_metadata <- tribble(
    ~bio_name, ~long_name, ~units,
    "bio01", "Annual Mean Temperature", "°C * 10",
    "bio02", "Mean Diurnal Range", "°C * 10",
    "bio03", "Isothermality", "%",
    "bio04", "Temperature Seasonality", "°C * 10",
    "bio05", "Max Temperature of Warmest Month", "°C * 10",
    "bio06", "Min Temperature of Coldest Month", "°C * 10",
    "bio07", "Temperature Annual Range", "°C * 10",
    "bio08", "Mean Temperature of Wettest Quarter", "°C * 10",
    "bio09", "Mean Temperature of Driest Quarter", "°C * 10",
    "bio10", "Mean Temperature of Warmest Quarter", "°C * 10",
    "bio11", "Mean Temperature of Coldest Quarter", "°C * 10",
    "bio12", "Annual Precipitation", "mm",
    "bio13", "Precipitation of Wettest Month", "mm",
    "bio14", "Precipitation of Driest Month", "mm",
    "bio15", "Precipitation Seasonality", "%",
    "bio16", "Precipitation of Wettest Quarter", "mm",
    "bio17", "Precipitation of Driest Quarter", "mm",
    "bio18", "Precipitation of Warmest Quarter", "mm",
    "bio19", "Precipitation of Coldest Quarter", "mm"
  )
  
  # Record download date
  download_date <- Sys.Date()

  for(idx in 1:nrow(bio_metadata)){
    i <- bio_metadata$bio_name[idx]

    # download files
      # download.file(url = paste("https://os.zhdk.cloud.switch.ch/envicloud/chelsa/chelsa_V1/climatologies/bio/CHELSA_bio10_",i,".tif",sep = ""),
      #               destfile = file.path(temp_directory,paste("CHELSA_bio10_",i,"_V1.2.tif",sep = ""))
      #               )

      # https://os.zhdk.cloud.switch.ch/chelsav2/GLOBAL/climatologies/1981-2010/bio/CHELSA_bio1_1981-2010_V.2.1.tif
      robust_download_file(url = paste("https://os.zhdk.cloud.switch.ch/chelsav2/GLOBAL/climatologies/1981-2010/bio/CHELSA_bio",sprintf("%02d", idx),"_1981-2010_V.2.1.tif",sep = ""),
                           destfile = file.path(temp_directory,paste("CHELSA_bio",sprintf("%02d", idx),"_1981-2010_V.2.1.tif",sep = "")),
                           max_attempts = 10,
                           sleep_time = 10
                           )

    # load
      rast_i <- terra::rast(file.path(temp_directory,paste("CHELSA_bio",sprintf("%02d", idx),"_1981-2010_V.2.1.tif",sep = "")))

    # crop

      rast_i <- terra::crop(x = rast_i,
                  y = ext(domain_tf))

    # mask
      rast_i <-
      terra::mask(rast_i,
                  mask = terra::vect(domain_tf))

    # Write as NetCDF with CF-compliant metadata
      nc_filename <- file.path(temp_directory, paste("CHELSA_", i, "_1981-2010_V.2.1.nc", sep = ""))
      
      # Use terra's writeCDF function which creates NetCDF4 files
      terra::writeCDF(x = rast_i,
                      filename = nc_filename,
                      overwrite = TRUE,
                      compression = 9)
      
      # Add CF-compliant metadata using ncdf4 package
      nc_file <- ncdf4::nc_open(nc_filename, write = TRUE)
      
      # Get variable name (should be the first variable in the file)
      var_name <- names(rast_i)
      if (is.null(var_name) || var_name == "") {
        var_name <- i
      }
      
      # Get metadata for this bioclimatic variable
      long_name <- bio_metadata$long_name[idx]
      units <- bio_metadata$units[idx]
      
      # Add global attributes
      ncdf4::ncatt_put(nc_file, 0, "title", 
                       paste("CHELSA Bioclimatic Variable", i, sep = " "))
      ncdf4::ncatt_put(nc_file, 0, "source", "CHELSA v.2.1 (Climatologies at high resolution for the earth land areas)")
      ncdf4::ncatt_put(nc_file, 0, "dataset_url", "https://chelsa-climate.org/")
      ncdf4::ncatt_put(nc_file, 0, "download_date", as.character(download_date))
      ncdf4::ncatt_put(nc_file, 0, "temporal_range", "1981-2010")
      ncdf4::ncatt_put(nc_file, 0, "Conventions", "CF-1.8")
      ncdf4::ncatt_put(nc_file, 0, "history", 
                       paste("Downloaded on", as.character(download_date), 
                             "and clipped to domain"))
      
      # Add variable attributes (long_name and units)
      ncdf4::ncatt_put(nc_file, 1, "long_name", long_name)
      ncdf4::ncatt_put(nc_file, 1, "units", units)
      ncdf4::ncatt_put(nc_file, 1, "standard_name", paste("bioclimatic_variable_", i, sep = ""))
      
      ncdf4::nc_close(nc_file)

    rm(rast_i)

  }

  rm(i)

    # release
      to_release <-
        list.files(path = file.path(temp_directory),
                   recursive = TRUE,
                   full.names = TRUE)


      to_release <-
        to_release[grepl(pattern = "CHELSA",
                         ignore.case = TRUE,
                         x = basename(to_release))]
      
      # Filter for NetCDF files only
      to_release <- to_release[grepl(pattern = "\\.nc$", x = to_release)]

 #       pb_upload(repo = "AdamWilsonLab/emma_envdata",
 #                 file = to_release,
 #                 tag = tag)

    # delete directory and contents
 #       unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)



  message("CHELSA climate files downloaded")
  return(Sys.Date())


} # end fx

