#' @title Download NASADEM elevation via AppEEARS and resample to domain
#' @description Submits an AppEEARS area request for NASADEM elevation data
#' over the provided domain polygon, downloads, and resamples to domain grid.
#' @author EMMA Team
#' @param domain_vector A SpatVector or sf polygon defining the domain boundary
#' @param domain_raster A SpatRaster (domain.tif) defining the output grid and mask
#' @param temp_directory Temporary working directory for downloads
#' @param verbose Logical for progress messages
#' @return SpatRaster with elevation resampled to domain, with metadata

get_elevation <- function(
  domain_vector,
  domain_raster,
  temp_directory = "data/temp/raw_data/elevation_nasadem/",
  out_file = "data/raw/elevation_nasadem.nc",
  verbose = TRUE
) {


  # Ensure clean temp directory
  unlink(temp_directory, recursive = TRUE, force = TRUE)
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  # Clean terra temp
  terra_tmp <- file.path(getwd(), "data/temp/terra")
  unlink(terra_tmp, recursive = TRUE, force = TRUE)
  dir.create(terra_tmp, recursive = TRUE, showWarnings = FALSE)
  terraOptions(tempdir = terra_tmp, memfrac = 0.8)

  # Convert domain vector to sf, fix geometry, simplify, merge, and reproject to WGS84 (required by AppEEARS)
  domain_sf <- st_as_sf(domain_vector) %>%
    st_simplify(dTolerance = 100, preserveTopology = TRUE) %>%
    st_buffer(0) %>%
    st_make_valid() %>%
    st_transform(crs = 4326)%>%
    geojsonsf::sf_geojson(simplify = FALSE)%>%
    jsonlite::fromJSON()

#  if (!all(st_is_valid(st_as_sf(domain_sf)))) stop("Domain polygon still invalid after repair; inspect input geometry.")


  # Build AppEEARS request with proper structure
  req <- list(
    task_type = "area",
    task_name = paste0("NASADEM_", format(Sys.time(), "%Y%m%d%H%M%S")),
    params = list(
      dates = list(list(
        startDate = "02-11-2000",
        endDate = "02-11-2000"
      )),
      layers = list(list(
        product = "SRTMGL3_NC.003",
        layer = "SRTMGL3_DEM"
      )),
      output = list(
        format = list(type = "netcdf4"),
        projection = "native"
      ),
      geo = domain_sf
    )
  )

  # Submit and poll for completion
  if (verbose) message("Submitting AppEEARS task...")
  task <- appeears::rs_request(
    request = req, 
    user = Sys.getenv("EARTHDATA_USER"),
    path = temp_directory,
    transfer = FALSE,
    verbose = verbose
  )
  
  if (verbose) message("Task submitted: ", task$get_task_id())

  # Poll for completion using task object methods
  max_retries <- 60
  retry_count <- 10
  
  repeat {
    retry_count <- retry_count + 1
    task$update_status(verbose = FALSE)
    
    if (task$is_success()) {
      if (verbose) message("Task completed successfully")
      break
    }
    
    if (task$is_failed()) {
      stop("AppEEARS task failed")
    }
    
    if (retry_count >= max_retries) {
      stop("Task polling timed out after ", max_retries * 10, " seconds")
    }
    
    if (verbose) message("Task status: ", task$get_status(), " (", retry_count, "/", max_retries, ")")
    Sys.sleep(10)
  }

  # Download results
  if (verbose) message("Downloading files for task: ", task$get_task_id())
  task$download(verbose = verbose)
  
  # Load the NetCDF file
  nc_paths <- list.files(temp_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)
  if (length(nc_paths) == 0) {
    stop("No NetCDF files downloaded from AppEEARS")
  }

  if (verbose) message("Reading elevation data from: ", nc_paths[1])
  elev_raster <- terra::rast(nc_paths[grepl(nc_paths, pattern = "SRTMGL3_NC.003_90m_aid0001.nc")])

  # Ensure we have a SpatRaster template (accept path or raster)
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster

  # Project to domain CRS/grid (bilinear) and mask to domain
  if (verbose) message("Projecting elevation to domain CRS/grid")
  elev_on_grid <- terra::project(elev_raster, domain_template, method = "average")

  # Mask to domain (NA where domain is NA)
  mask_layer <- if ("domain" %in% names(domain_template)) domain_template[["domain"]] else domain_template
  elev_masked <- terra::mask(elev_on_grid, mask_layer)

  # Set metadata
  names(elev_masked) <- "elevation"
  units(elev_masked) <- "meters"

  metags(elev_masked) <- c(
    "elevation_long_name" = "NASADEM elevation above mean sea level",
    "elevation_source" = "NASADEM_HGT.001 via AppEEARS",
    "date_generated" = as.character(Sys.time()),
    "crs" = as.character(crs(elev_masked)),
    "Conventions" = "CF-1.8"
  )

  # Write NetCDF with compression and CF metadata
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, "elevation_nasadem.nc")
  unlink(out_file)

  ext_vals <- ext(elev_masked)
  dx <- res(elev_masked)[1]
  dy <- res(elev_masked)[2]
  x_vals <- seq(ext_vals$xmin + dx/2, ext_vals$xmax - dx/2, by = dx)
  y_vals <- seq(ext_vals$ymax - dy/2, ext_vals$ymin + dy/2, by = -dy)

  dim_x <- ncdf4::ncdim_def(name = "easting", units = "meter", vals = x_vals, longname = "easting")
  dim_y <- ncdf4::ncdim_def(name = "northing", units = "meter", vals = y_vals, longname = "northing")

  var_elev <- ncdf4::ncvar_def(
    name = "elevation",
    units = "meters",
    dim = list(dim_x, dim_y),
    longname = "NASADEM elevation above mean sea level",
    missval = -3.4e38,
    prec = "float",
    compression = 9
  )

  nc <- ncdf4::nc_create(filename = out_file, vars = list(var_elev), force_v4 = TRUE)

  elev_matrix <- t(as.matrix(elev_masked, wide = TRUE))
  elev_matrix[is.na(elev_matrix)] <- -3.4e38
  ncdf4::ncvar_put(nc, var_elev, elev_matrix)

  crs_wkt <- as.character(crs(elev_masked))
  crs_var <- ncdf4::ncvar_def("crs", "", list(), prec = "integer")
  nc <- ncdf4::ncvar_add(nc, crs_var)
  ncdf4::ncatt_put(nc, "crs", "crs_wkt", crs_wkt)
  ncdf4::ncatt_put(nc, "crs", "spatial_ref", crs_wkt)
  ncdf4::ncatt_put(nc, "crs", "GeoTransform", paste(ext_vals$xmin, dx, 0, ext_vals$ymax, 0, -dy))
  ncdf4::ncatt_put(nc, "elevation", "grid_mapping", "crs")

  ncdf4::ncatt_put(nc, 0, "title", "NASADEM elevation resampled to domain")
  ncdf4::ncatt_put(nc, 0, "source", "NASADEM_HGT.001 via AppEEARS")
  ncdf4::ncatt_put(nc, 0, "history", paste0("created: ", Sys.time()))
  ncdf4::ncatt_put(nc, 0, "Conventions", "CF-1.8")

  ncdf4::nc_close(nc)

  # Cleanup
  unlink(temp_directory, recursive = TRUE, force = TRUE)
  gc()
  unlink(terra_tmp, recursive = TRUE, force = TRUE)

  out_file
}




