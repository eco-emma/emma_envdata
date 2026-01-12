# Rasterize Domain and Remnants

#' @title Rasterize domain with pixel IDs, remnants, and distance to remnants
#' @author Adam M. Wilson
#' @description Creates a multivariate NetCDF file with four variables: domain mask, pixel IDs, remnant indicators, and distance to nearest remnant. Each variable is written separately with maximum compression and CF-1.8 compliant metadata.
#' @param domain sf or SpatVector object defining the study area (typically from domain_define).
#' @param remnants_shp Path to remnant vegetation shapefile.
#' @param dx Numeric x-resolution in CRS units (default 250 m).
#' @param dy Numeric y-resolution in CRS units (default 250 m).
#' @param out_file Character path for output NetCDF file (default "data/raw/domain.nc").
#' @return Character path to the written NetCDF file.
#' @details Generates a raster template from domain bounding box, rasterizes domain and remnants, computes pixel IDs (sequential within domain) and Euclidean distance to nearest remnant (in km). Writes four variables (domain, pid, remnants, remnants_distance) to NetCDF with FORMAT=NC4, COMPRESS=DEFLATE, ZLEVEL=9, SHUFFLE=YES. Adds CF-compliant metadata via ncdf4 including long_name, units, CRS, history, and Conventions attributes.

domain_rasterize <- function(domain, remnants_shp, dx = 250, dy = 250, out_file = "data/raw/domain.nc") {

  # Generate raster version of domain
  domain_template <- st_as_stars(st_bbox(domain), dx = dx, dy = dy)

# rasterize domain
  domain_raster <- domain %>%
    st_as_sf() %>%
    st_rasterize(template = domain_template) %>%
    rast()


## Process remnants to add fields related to whether the cell is in a remnant and distance to remnant

# Load remnants file
  remnants <- st_read(remnants_shp) %>%
    janitor::clean_names() %>%
    st_transform(crs = crs(domain)) %>%
    st_crop(st_as_sfc(st_bbox(domain)))|>  #crop to domain box
    st_union() %>%
    st_make_valid()


  remnants_raster <- remnants %>%
    st_as_sf() |>
    mutate(remnant=1) %>%
    vect() %>%
    rasterize(x = .,
              y = domain_raster,
              field = "remnant",
              touches = T,
              cover = T)|>
    terra::mask(mask=domain_raster)

  remnants_distance <- remnants_raster |>
    terra::app(fun=function(x) ifelse(is.na(x),0,1)) |>
    terra::gridDist(target=1)/1000

  # Create pixel ID raster: 1:ncell where domain=1, NA elsewhere
  pid_raster <- domain_raster
  pid_values <- rep(NA, ncell(pid_raster))
  domain_cells <- which(!is.na(values(domain_raster)))
  pid_values[domain_cells] <- seq_along(domain_cells)
  values(pid_raster) <- pid_values

  # Prepare layers and units for per-variable write
  layers <- list(
    domain = domain_raster,
    pid = pid_raster,
    remnants = remnants_raster,
    remnants_distance = remnants_distance
  )
  units(layers$domain) <- "dimensionless"
  units(layers$pid) <- "dimensionless"
  units(layers$remnants) <- "dimensionless"
  units(layers$remnants_distance) <- "kilometers"

  # Write each variable separately to NetCDF with maximum compression
  terra::writeCDF(
    layers$domain,
    filename = out_file,
    varname = "domain",
    overwrite = TRUE,
    gdal = c("FORMAT=NC4", "COMPRESS=DEFLATE", "ZLEVEL=9", "SHUFFLE=YES")
  )
  terra::writeCDF(layers$pid, filename = out_file, varname = "pid", overwrite = FALSE, append = TRUE,
                  gdal = c("FORMAT=NC4", "COMPRESS=DEFLATE", "ZLEVEL=9", "SHUFFLE=YES"))
  terra::writeCDF(layers$remnants, filename = out_file, varname = "remnants", overwrite = FALSE, append = TRUE,
                  gdal = c("FORMAT=NC4", "COMPRESS=DEFLATE", "ZLEVEL=9", "SHUFFLE=YES"))
  terra::writeCDF(layers$remnants_distance, filename = out_file, varname = "remnants_distance", overwrite = FALSE, append = TRUE,
                  gdal = c("FORMAT=NC4", "COMPRESS=DEFLATE", "ZLEVEL=9", "SHUFFLE=YES"))

  # Add detailed CF-style metadata via ncdf4
  nc <- ncdf4::nc_open(out_file, write = TRUE)
  on.exit(ncdf4::nc_close(nc), add = TRUE)

  # Global attributes
  ncdf4::ncatt_put(nc, 0, "title", "Rasterized domain with remnants and distance")
  ncdf4::ncatt_put(nc, 0, "history", paste0("created: ", Sys.time()))
  ncdf4::ncatt_put(nc, 0, "crs", as.character(crs(domain_raster)))
  ncdf4::ncatt_put(nc, 0, "Conventions", "CF-1.8")

  # Variable-specific attributes
  attr_map <- list(
    domain = list(long_name = "Domain mask (1 = in domain, NA = outside)", units = "dimensionless"),
    pid = list(long_name = "Pixel ID for domain grid cells", units = "dimensionless"),
    remnants = list(long_name = "Remnant vegetation indicator (1 = remnant, NA = not remnant)", units = "dimensionless"),
    remnants_distance = list(long_name = "Distance to nearest remnant vegetation", units = "kilometers")
  )
  for (v in names(attr_map)) {
    if (v %in% names(nc$var)) {
      ncdf4::ncatt_put(nc, v, "long_name", attr_map[[v]]$long_name)
      ncdf4::ncatt_put(nc, v, "units", attr_map[[v]]$units)
    }
  }

  out_file
}