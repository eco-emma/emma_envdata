# Rasterize Domain

#' @author Adam M. Wilson

#  Rasterize domain to common grid to define the raster domain

#' @param domain vector file of study domain
#' @param dx x resolution
#' @param dy y resolution

domain_rasterize <- function(domain, remnants_shp, dx = 250, dy = 250) {

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
    st_make_valid()


  remnants_raster <- remnants %>%
    mutate(remnant=1) %>%
    vect() %>%
    rasterize(x = .,
              y = domain_raster,
              field = "remnant",
              touches = T,
              cover = T)

  remnants_distance <- remnants_raster |>
    terra::app(fun=function(x) ifelse(is.na(x),0,1)) |>
    terra::gridDist(target=1)/1000



  # Create pixel ID raster: 1:ncell where domain=1, NA elsewhere
  pid_raster <- domain_raster
  pid_values <- rep(NA, ncell(pid_raster))
  domain_cells <- which(!is.na(values(domain_raster)))
  pid_values[domain_cells] <- seq_along(domain_cells)
  values(pid_raster) <- pid_values

  # Combine into multiband raster
  multiband_raster <- c(domain_raster, pid_raster, remnants_raster, remnants_distance)
  
  # Set layer names
  names(multiband_raster) <- c("domain", "pid", "remnants", "remnants_distance")
  
  # Add CF-compliant metadata for each layer
  # Layer 1: domain
  attr(multiband_raster[[1]], "long_name") <- "Domain mask (1 = in domain, NA = outside)"
  attr(multiband_raster[[1]], "units") <- "dimensionless"
  
  # Layer 2: pid
  attr(multiband_raster[[2]], "long_name") <- "Pixel ID for domain grid cells"
  attr(multiband_raster[[2]], "units") <- "1"
  
  # Layer 3: remnants
  attr(multiband_raster[[3]], "long_name") <- "Remnant vegetation indicator (1 = in remnant, NA = outside)"
  attr(multiband_raster[[3]], "units") <- "dimensionless"
  
  # Layer 4: remnants_distance
  attr(multiband_raster[[4]], "long_name") <- "Distance to nearest remnant"
  attr(multiband_raster[[4]], "units") <- "kilometers"
  
  # Global attributes
  attr(multiband_raster, "date_generated") <- as.character(Sys.time())
  attr(multiband_raster, "crs") <- as.character(crs(multiband_raster))
  attr(multiband_raster, "Conventions") <- "CF-1.8"

  multiband_raster
}



# library(geoarrow)
# # Convert raster stack to points
# domain_points <- terra::as.points(domain_raster)|> 
# sf::st_as_sf() |>
# filter(domain==1)

# # Write GeoParquet
# arrow::write_parquet(domain_points, "domain.parquet")




