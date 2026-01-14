# Define buffered project domain

#' @author Adam M. Wilson
#' @description Build a smoothed, buffered domain polygon from the 2018 vegetation map and country boundary, then write it to GeoParquet.
#' @param vegmap_shp Path to the vegetation map shapefile (e.g., VEGMAP2018).
#' @param country Path to the country boundary GeoParquet file.
#' @return Character path to the written GeoParquet file (`data/raw/domain.parquet`).
#' @details Filters to target biomes, unions polygons, simplifies (500 m), buffers (50 km), smooths (ksmooth, smoothness=120), intersects with country, and writes to GeoParquet.

domain_define <- function(vegmap_shp, country){

  # Always read country from a parquet path
  if (!is.character(country)) {
    stop("country must be a path to a GeoParquet file")
  }
  country <- sfarrow::st_read_parquet(country)

  biomes = c("Fynbos")#,"Succulent Karoo")#,"Albany Thicket")


   vegmap_union=st_read(vegmap_shp) %>%
    janitor::clean_names() %>%
    filter(t_biome %in%  biomes ) %>% #filter to list above
    st_union()   # union all polygons into one multipolygon, dissolving internal boundaries
  
vegmap_buffer = vegmap_union %>%
  st_simplify(dTolerance=500) %>%
  st_buffer(50000) %>%
  smooth(method="ksmooth",smoothness=120) #%>%

country= st_as_sf(country) %>%
  st_transform(crs=st_crs(vegmap_buffer)) 
  
  domain <-
    vegmap_buffer %>%
    st_intersection(st_transform(country,crs=st_crs(vegmap_union))) %>%  #only keep land areas of buffer - no ocean
    st_as_sf() %>%
    mutate(domain=1)

  # Write to GeoParquet
  out_file <- "data/raw/domain.parquet"
  sfarrow::st_write_parquet(domain, out_file)
  
  return(out_file)

}