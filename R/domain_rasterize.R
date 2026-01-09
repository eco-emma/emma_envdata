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
  
  # Set units (preserved through cache with terra_preserve_metadata = "zip")
  units(multiband_raster) <- c("dimensionless", "1", "dimensionless", "kilometers")

  # Add metadata using metags (preserved in GeoTIFF)
  metags(multiband_raster) <- c(
    "domain_long_name" = "Domain mask (1 = in domain, NA = outside)",
    "pid_long_name" = "Pixel ID for domain grid cells",
    "remnants_long_name" = "Remnant vegetation indicator (1 = remnant, NA = not remnant)",
    "remnants_distance_long_name" = "Distance to nearest remnant vegetation (km)",
    "date_generated" = as.character(Sys.time()),
    "crs" = as.character(crs(multiband_raster))
  )

  multiband_raster
}



# library(geoarrow)
# # Convert raster stack to points
# domain_points <- terra::as.points(domain_raster)|> 
# sf::st_as_sf() |>
# filter(domain==1)

# # Write GeoParquet
# arrow::write_parquet(domain_points, "domain.parquet")




