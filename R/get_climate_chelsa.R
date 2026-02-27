#' @title Download and process CHELSA climate data
#' @description Downloads CHELSA bioclimatic variables, clips to domain, and writes as NetCDF files
#' @author Brian Maitner & Adam Wilson
#' @param domain domain (sf polygon) used for masking
#' @param temp_directory Temporary working directory for downloads (default: "data/temp/raw_data/climate_chelsa/")
#' @param out_dir Output directory for NetCDF files (default: "data/target_outputs/")
#' @param cleanup Logical. If TRUE (default, for GitHub Actions), clean temp directory. If FALSE (local development), preserve cached files.
#' @param verbose Logical for progress messages
#' @return Character vector of output NetCDF file paths
#' @import terra
#' @import sf
#' @import ncdf4

get_climate_chelsa <- function(
    domain,
    temp_directory = "data/temp/raw_data/climate_chelsa/",
    out_dir = "data/target_outputs/",
    cleanup = TRUE,
    verbose = TRUE
) {

  # Ensure temp directory exists, clean only if cleanup mode enabled
  if (cleanup && dir.exists(temp_directory)) {
    unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)
  }
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # Adjust download timeout
  if (getOption('timeout') < 1000) {
    options(timeout = 1000)
  }

  # Transform domain to WGS84
  domain_tf <- domain %>%
    st_as_sf() %>%
    sf::st_transform(crs("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"))

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
  output_files <- character()

  for (idx in 1:nrow(bio_metadata)) {
    i <- bio_metadata$bio_name[idx]

    if (verbose) message("Processing ", i, " (", idx, "/", nrow(bio_metadata), ")")

    # Construct filename
    tif_filename <- file.path(temp_directory, paste("CHELSA_bio", sprintf("%02d", idx), 
                                                      "_1981-2010_V.2.1.tif", sep = ""))
    
    # Skip download if file already exists (when cleanup = FALSE, running locally)
    if (!cleanup && file.exists(tif_filename)) {
      if (verbose) message("  File already cached, skipping download: ", basename(tif_filename))
    } else {
      # Download the file
      if (verbose) message("  Downloading...")
      robust_download_file(
        url = paste("https://os.unil.cloud.switch.ch/chelsa02/chelsa/global/bioclim/", i, 
                    "/1981-2010/CHELSA_bio", sprintf("%02d", idx), "_1981-2010_V.2.1.tif", sep = ""),
        destfile = tif_filename,
        max_attempts = 10,
        sleep_time = 10
      )
    }

    # Load, crop, and mask
    rast_i <- terra::rast(tif_filename)
    domain_tf2=st_transform(domain_tf, st_crs(rast_i))
    rast_i <- terra::crop(x = rast_i, y = ext(domain_tf2))
    rast_i <- terra::mask(rast_i, mask = terra::vect(domain_tf2))

     # Check if raster has data after masking

    # Write as NetCDF with CF-compliant metadata
    nc_filename <- file.path(out_dir, paste("CHELSA_", i, "_1981-2010_V.2.1.nc", sep = ""))
    
    terra::writeCDF(x = rast_i,
                    filename = nc_filename,
                    overwrite = TRUE,
                    compression = 9)
    
    # Add CF-compliant metadata using ncdf4 package
    nc_file <- ncdf4::nc_open(nc_filename, write = TRUE)
    
    # Get variable name
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
                           "and clipped to domain. Processed using terra and ncdf4 R packages."))
    
    # Add variable attributes
    ncdf4::ncatt_put(nc_file, var_name, "long_name", long_name)
    ncdf4::ncatt_put(nc_file, var_name, "units", units)
    ncdf4::ncatt_put(nc_file, var_name, "standard_name", paste("bioclimatic_variable_", i, sep = ""))
    
    ncdf4::nc_close(nc_file)
    output_files <- c(output_files, nc_filename)
    
    rm(rast_i)
  }

  # Cleanup temp directory only if cleanup mode enabled
  if (cleanup) {
    unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)
  }

  if (verbose) message("CHELSA climate files processed to: ", out_dir)
  
  # Return output file paths for targets to track
  output_files

}

