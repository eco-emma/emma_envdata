# Define buffered project domain

#' @author Adam M. Wilson
#' @description Build a smoothed, buffered domain polygon from the 2018 vegetation map and country boundary, then write it to GeoParquet.
#' @param vegmap The vegetation map sf object.
#' @param country The country boundary sf object.
#' @return The domain polygon sf object.
#' @details Filters to target biomes, unions polygons, simplifies (500 m), buffers (50 km), smooths (ksmooth, smoothness=120), intersects with country, and writes to GeoParquet.

domain_define <- function(vegmap, country){

  biomes = c("Fynbos")#,"Succulent Karoo")#,"Albany Thicket")


   vegmap_union = vegmap |>
    janitor::clean_names() |>
    dplyr::filter(t_biome %in%  biomes ) |> #filter to list above
    st_union()   # union all polygons into one multipolygon, dissolving internal boundaries
  
vegmap_buffer = vegmap_union |>
  st_simplify(dTolerance=500) |>
  st_buffer(50000) |>
  smoothr::smooth(method="ksmooth",smoothness=120) #|>

country= country |>
  st_transform(crs=st_crs(vegmap_buffer)) 
  
  domain <-
    vegmap_buffer |>
    st_intersection(st_transform(country,crs=st_crs(vegmap_union))) |>  #only keep land areas of buffer - no ocean
    st_as_sf() |>
    dplyr::mutate(domain=1)

  # Reproject to the canonical project CRS (Albers Equal Area, matching AVIRIS-NG NetCDF).
  # Using explicit WKT instead of st_crs(9221) to avoid PROJ database dependency.
  # Parameters match BioSCape EPSG:9221 (Hartebeesthoek94 / ZAF BSU Albers 25E):
  #   lat_0=-30, lon_0=25, std parallels -22/-38, FE=1400000, FN=1300000, WGS84 ellipsoid.
  project_crs <- 'PROJCRS["unnamed",
    BASEGEOGCRS["Ellipse Based",
        DATUM["Ellipse Based",
            ELLIPSOID["Unnamed",6378137,298.257223562997,
                LENGTHUNIT["metre",1,
                    ID["EPSG",9001]]]],
        PRIMEM["Greenwich",0,
            ANGLEUNIT["degree",0.0174532925199433,
                ID["EPSG",9122]]]],
    CONVERSION["unnamed",
        METHOD["Albers Equal Area",
            ID["EPSG",9822]],
        PARAMETER["Latitude of false origin",-30,
            ANGLEUNIT["degree",0.0174532925199433],
            ID["EPSG",8821]],
        PARAMETER["Longitude of false origin",25,
            ANGLEUNIT["degree",0.0174532925199433],
            ID["EPSG",8822]],
        PARAMETER["Latitude of 1st standard parallel",-22,
            ANGLEUNIT["degree",0.0174532925199433],
            ID["EPSG",8823]],
        PARAMETER["Latitude of 2nd standard parallel",-38,
            ANGLEUNIT["degree",0.0174532925199433],
            ID["EPSG",8824]],
        PARAMETER["Easting at false origin",1400000,
            LENGTHUNIT["metre",1],
            ID["EPSG",8826]],
        PARAMETER["Northing at false origin",1300000,
            LENGTHUNIT["metre",1],
            ID["EPSG",8827]]],
    CS[Cartesian,2],
        AXIS["easting",east,
            ORDER[1],
            LENGTHUNIT["metre",1,
                ID["EPSG",9001]]],
        AXIS["northing",north,
            ORDER[2],
            LENGTHUNIT["metre",1,
                ID["EPSG",9001]]]]'

  domain <- domain |>
    st_transform(crs = project_crs) |>
    st_simplify(dTolerance = 100, preserveTopology = TRUE) |>
    st_buffer(0) |>
    st_make_valid() |> 
    terra::vect() # convert to SpatVector for faster processing and compatibility with terra functions and tar_terra_vect()

  return(domain)

}