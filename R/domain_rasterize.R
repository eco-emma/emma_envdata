# Rasterize Domain and Remnants

#' @title Rasterize domain with pixel IDs, remnants, and distance to remnants
#' @author Adam M. Wilson
#' @description Creates a multivariate NetCDF file with four variables: domain mask, pixel IDs, remnant indicators, and distance to nearest remnant. Each variable is written separately with maximum compression and CF-1.8 compliant metadata.
#' @param domain_boundary sf or SpatVector object defining the study area (typically from domain_define).
#' @param remnants Path to remnant vegetation shapefile.
#' @param dx Numeric x-resolution in CRS units (default 500 m).
#' @param dy Numeric y-resolution in CRS units (default 500 m).
#' @param out_file Deprecated (removed). Output is now returned as a SpatRaster.
#' @return SpatRaster with 4 INT4S bands: pid, domain, remnants, remnants_distance.
#' @details Generates a raster template from domain bounding box, rasterizes domain and remnants, computes pixel IDs (sequential within domain) and Euclidean distance to nearest remnant (in km). Returns a 4-band SpatRaster with names and GDAL metadata embedded in the TIFF IFD (survives COG round-trip via geotargets::tar_terra_rast()).

domain_rasterize <- function(domain_boundary, remnants, dx = 500, dy = 500) {

  # Generate raster template and rasterize domain with terra (touches = TRUE)
  # Use ext()+res= form for compatibility with older terra versions (<1.7-39)
  bb <- sf::st_bbox(sf::st_transform(domain_boundary, crs = terra::crs(terra::vect(domain_boundary))))
  domain_template <- terra::rast(
    xmin = bb["xmin"], xmax = bb["xmax"],
    ymin = bb["ymin"], ymax = bb["ymax"],
    resolution = c(dx, dy),
    crs = terra::crs(terra::vect(domain_boundary))
  )

 # domain_raster <- domain_boundary %>%

  domain_raster <- domain_boundary %>%
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
  remnants <- remnants %>%
    janitor::clean_names() %>%
    st_transform(crs = crs(domain_raster)) %>%
    st_crop(st_as_sfc(st_bbox(domain_raster)))  #crop to domain box
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

  # distance() computes distance from each NA cell to nearest non-NA cell.
  # Set remnant cells to 1 and non-remnant (but in-domain) cells to NA so
  # distance() returns distance-to-nearest-remnant for every domain pixel.
  remnants_distance <- terra::ifel(!is.na(remnants_raster), 1, NA) |>
    terra::distance() |>
    terra::mask(mask=domain_raster) #set to NA outside domain


  # Create pixel ID raster: 1:ncell where domain=1, NA elsewhere
  pid_raster <- domain_raster
  pid_values <- rep(NA, ncell(pid_raster))
  domain_cells <- which(!is.na(values(domain_raster)))
  pid_values[domain_cells] <- seq_along(domain_cells)
  values(pid_raster) <- pid_values

  # Stack bands in order: pid, domain, remnants, remnants_distance
  # Round before integer coercion: remnants_distance is float (metres), others already integers
  r <- c(
    terra::as.int(pid_raster),
    terra::as.int(domain_raster),
    terra::as.int(terra::round(remnants_raster)),
    terra::as.int(terra::round(remnants_distance))
  )
  names(r) <- c("pid", "domain", "remnants", "remnants_distance")

  # Embed metadata in TIFF IFD via GDAL XML (survives COG round-trip)
  terra::metags(r) <- c(
    date_created = as.character(Sys.Date()),
    source       = "domain_rasterize",
    description  = "500m model grid: domain mask, pixel IDs, remnant cover, remnant distance"
  )
  terra::metags(r, layer = 1) <- c(
    description = "Unique pixel ID (sequential within domain)",
    units       = "dimensionless"
  )
  terra::metags(r, layer = 2) <- c(
    description = "Domain mask (1 = in domain)",
    units       = "boolean"
  )
  terra::metags(r, layer = 3) <- c(
    description = "Remnant natural vegetation cover (0-100%)",
    units       = "percent"
  )
  terra::metags(r, layer = 4) <- c(
    description = "Distance to nearest remnant vegetation",
    units       = "metres"
  )

  r
}