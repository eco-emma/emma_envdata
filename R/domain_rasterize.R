# Rasterize Domain and Remnants

#' @title Rasterize domain with pixel IDs, remnants, and distance to remnants
#' @author Adam M. Wilson
#' @description Creates a multivariate NetCDF file with four variables: domain mask, pixel IDs, remnant indicators, and distance to nearest remnant. Each variable is written separately with maximum compression and CF-1.8 compliant metadata.
#' @param domain sf or SpatVector object defining the study area (typically from domain_define).
#' @param remnants_shp Path to remnant vegetation shapefile.
#' @param dx Numeric x-resolution in CRS units (default 500 m).
#' @param dy Numeric y-resolution in CRS units (default 500 m).
#' @param out_file Character path for output NetCDF file (default "data/raw/domain.nc").
#' @return Character path to the written NetCDF file.
#' @details Generates a raster template from domain bounding box, rasterizes domain and remnants, computes pixel IDs (sequential within domain) and Euclidean distance to nearest remnant (in km). Writes four variables (domain, pid, remnants, remnants_distance) to NetCDF with FORMAT=NC4, COMPRESS=DEFLATE, ZLEVEL=9, SHUFFLE=YES. Adds CF-compliant metadata via ncdf4 including long_name, units, CRS, history, and Conventions attributes.

domain_rasterize <- function(domain, remnants_shp, dx = 500, dy = 500, out_file = "data/raw/domain.nc") {

  # Generate raster template and rasterize domain with terra (touches = TRUE)
  domain_template <- rast(st_as_stars(st_bbox(domain), dx = dx, dy = dy))

  domain_raster <- domain %>%
    st_as_sf() %>%
    mutate(domain = 1) %>%
    vect() %>%
    terra::rasterize(
      x = .,
      y = domain_template,
      field = "domain",
      touches = TRUE
    )
  
  # Ensure pixels outside domain are NA (not 0)
  domain_raster[domain_raster == 0] <- NA


## Process remnants to add fields related to whether the cell is in a remnant and distance to remnant

# Load remnants file
  remnants <- st_read(remnants_shp) %>%
    janitor::clean_names() %>%
    st_transform(crs = crs(domain)) %>%
    st_crop(st_as_sfc(st_bbox(domain)))  #crop to domain box
#    st_union() %>%
#    st_make_valid()


  remnants_raster <- remnants %>%
    st_as_sf() |>
    mutate(remnant=1) %>%
    vect() %>%
    rasterize(x = .,
              y = domain_raster,
              field = "remnant",
              touches = T,
              cover = T)|>
    terra::mask(mask=domain_raster)*100  #set to NA outside domain and convert to integer

  remnants_distance <- remnants_raster |>
    terra::app(fun=function(x) ifelse(is.na(x),0,1)) |>
    terra::distance(target=1)|>
    terra::mask(mask=domain_raster) #set to NA outside domain


  # Create pixel ID raster: 1:ncell where domain=1, NA elsewhere
  pid_raster <- domain_raster
  pid_values <- rep(NA, ncell(pid_raster))
  domain_cells <- which(!is.na(values(domain_raster)))
  pid_values[domain_cells] <- seq_along(domain_cells)
  values(pid_raster) <- pid_values

  # Prepare layers for per-variable write
  layers <- list(
    domain = domain_raster,
    pid = pid_raster,
    remnants = remnants_raster,
    remnants_distance = remnants_distance
  )

  # Get spatial extent and create dimensions for NetCDF
  ext <- ext(domain_raster)
  x_vals <- seq(ext$xmin + dx/2, ext$xmax - dx/2, by = dx)
  y_vals <- seq(ext$ymax - dy/2, ext$ymin + dy/2, by = -dy)
  
  # Define dimensions
  dim_x <- ncdf4::ncdim_def(name = "easting", units = "meter", vals = x_vals, longname = "easting")
  dim_y <- ncdf4::ncdim_def(name = "northing", units = "meter", vals = y_vals, longname = "northing")
  
  # Define variables with optimal data types and compression
  var_domain <- ncdf4::ncvar_def(
    name = "domain",
    units = "dimensionless",
    dim = list(dim_x, dim_y),
    longname = "Domain mask (1 = in domain, NA = outside)",
    missval = -128,
    prec = "byte",
    compression = 9
  )
  
  var_pid <- ncdf4::ncvar_def(
    name = "pid",
    units = "dimensionless",
    dim = list(dim_x, dim_y),
    longname = "Pixel ID for domain grid cells",
    missval = -2147483648,
    prec = "integer",
    compression = 9
  )
  
  var_remnants <- ncdf4::ncvar_def(
    name = "remnants",
    units = "dimensionless",
    dim = list(dim_x, dim_y),
    longname = "Remnant vegetation proportion (100 = full remnant, 5 = 5% remnant, NA = not remnant)",
    missval = -128,
    prec = "byte",
    compression = 9
  )
  
  var_dist <- ncdf4::ncvar_def(
    name = "remnants_distance",
    units = "meters",
    dim = list(dim_x, dim_y),
    longname = "Distance to nearest remnant vegetation",
    missval = -2147483648,
    prec = "integer",
    compression = 9
  )
  
  # Create NetCDF file with all variables
unlink(out_file)

  nc <- ncdf4::nc_create(
    filename = out_file,
    vars = list(var_domain, var_pid, var_remnants, var_dist),
    force_v4 = TRUE
  )
  
  # Convert rasters to matrices and replace NAs with fill values
  # Note: as.matrix() from terra returns (nrow, ncol), but ncdf4 expects (ncol, nrow) for (x, y) dims
  domain_matrix <- t(as.matrix(layers$domain, wide = TRUE))
  domain_matrix[is.na(domain_matrix)] <- -128
  
  pid_matrix <- t(as.matrix(layers$pid, wide = TRUE))
  pid_matrix[is.na(pid_matrix)] <- -2147483648
  
  remnants_matrix <- t(as.matrix(layers$remnants, wide = TRUE))
  remnants_matrix[is.na(remnants_matrix)] <- -128
  
  dist_matrix <- t(as.matrix(layers$remnants_distance, wide = TRUE))
  dist_matrix[is.na(dist_matrix)] <- -2147483648
  
  # Write data to variables
  ncdf4::ncvar_put(nc, var_domain, domain_matrix)
  ncdf4::ncvar_put(nc, var_pid, pid_matrix)
  ncdf4::ncvar_put(nc, var_remnants, remnants_matrix)
  ncdf4::ncvar_put(nc, var_dist, dist_matrix)
  
  # Add global attributes
  ncdf4::ncatt_put(nc, 0, "title", "Rasterized domain with remnants and distance")
  ncdf4::ncatt_put(nc, 0, "history", paste0("created: ", Sys.time()))
  ncdf4::ncatt_put(nc, 0, "Conventions", "CF-1.8")
  
  # Add CRS variable with comprehensive attributes for GIS compatibility
  crs_var <- ncdf4::ncvar_def("crs", "", list(), prec = "integer")
  nc <- ncdf4::ncvar_add(nc, crs_var)
  
  # Get CRS as WKT string (most reliable for terra)
  crs_wkt <- as.character(crs(domain_raster))
  
  # Add CRS attributes
  ncdf4::ncatt_put(nc, "crs", "grid_mapping_name", "albers_conical_equal_area")
  ncdf4::ncatt_put(nc, "crs", "crs_wkt", crs_wkt)
  ncdf4::ncatt_put(nc, "crs", "spatial_ref", crs_wkt)
  
  # Add geotransform for GDAL compatibility
  ext_vals <- ext(domain_raster)
  geotransform <- paste(ext_vals$xmin, dx, 0, ext_vals$ymax, 0, -dy)
  ncdf4::ncatt_put(nc, "crs", "GeoTransform", geotransform)
  
  # Add grid_mapping attribute to all data variables
  ncdf4::ncatt_put(nc, "domain", "grid_mapping", "crs")
  ncdf4::ncatt_put(nc, "pid", "grid_mapping", "crs")
  ncdf4::ncatt_put(nc, "remnants", "grid_mapping", "crs")
  ncdf4::ncatt_put(nc, "remnants_distance", "grid_mapping", "crs")
  
  # Close file
  ncdf4::nc_close(nc)

  out_file
}


if(F){
test=rast(out_file)
plot(test$domain)
}