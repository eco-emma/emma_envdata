# Define buffered project domain

#' @author Adam M. Wilson
#' @description Build a smoothed, buffered domain polygon from the 2018 vegetation map and country boundary, then write it to GeoParquet.
#' @param vegmap The vegetation map sf object.
#' @param country The country boundary sf object.
#' @return The domain polygon sf object.
#' @details Filters to target biomes, unions polygons, simplifies (500 m), buffers (50 km), smooths (ksmooth, smoothness=120), intersects with country, and writes to GeoParquet.

domain_define <- function(vegmap, country){

  biomes = c("Fynbos")#,"Succulent Karoo")#,"Albany Thicket")


   vegmap_union=vegmap %>%
    janitor::clean_names() %>%
    filter(t_biome %in%  biomes ) %>% #filter to list above
    st_union()   # union all polygons into one multipolygon, dissolving internal boundaries
  
vegmap_buffer = vegmap_union %>%
  st_simplify(dTolerance=500) %>%
  st_buffer(50000) %>%
  smoothr::smooth(method="ksmooth",smoothness=120) #%>%

country= country %>%
  st_transform(crs=st_crs(vegmap_buffer)) 
  
  domain <-
    vegmap_buffer %>%
    st_intersection(st_transform(country,crs=st_crs(vegmap_union))) %>%  #only keep land areas of buffer - no ocean
    st_as_sf() %>%
    mutate(domain=1)

  
  return(domain)

}