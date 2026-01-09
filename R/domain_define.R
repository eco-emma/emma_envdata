# Make Domain

#' @author Adam M. Wilson

#  Process 2018 Vegetation dataset to define project domain


#' @param vegmap is the domains of interest from the 2018 national vegetation map
#' @param buffer size of domain buffer (in m)

domain_define <- function(vegmap_shp, country){

  biomes = c("Fynbos","Succulent Karoo")#,"Albany Thicket")


   vegmap_union=st_read(vegmap_shp) %>%
    st_as_sf() %>%
    filter(biome_18 %in%  biomes ) %>% #filter to list above
    st_union()   # union all polygons into one multipolygon, dissolving internal boundaries

  #buffer domain biomes
  vegmap_buffer= vegmap_union %>%
    st_simplify(dTolerance=500) %>%
    st_buffer(50000) %>%
    st_simplify(dTolerance=100)

# Further clean up the buffered domain
# library(smoothr)
# vegmap_buffer <- vegmap_union %>%
#   fill_holes(set_units(100, km^2))|>
# #  st_simplify(dTolerance=500) %>%
#   drop_crumbs(set_units(100, km^2)) |>
#   smooth(method = "chaikin", refinements = 5)  # or method = "ksmooth"
#   st_buffer(1000000)|>
# #  st_buffer(-1000000) |>
#   st_simplify(dTolerance=100)|>
#   st_make_valid()



country= st_as_sf(country) %>%
    st_transform(crs=st_crs(vegmap_buffer))

  domain <-
    vegmap_buffer %>%
    st_intersection(st_transform(country,crs=st_crs(vegmap))) %>%  #only keep land areas of buffer - no ocean
    st_as_sf() %>%
    mutate(domain=1) |>
    vect()


  return(domain)

}