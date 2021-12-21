# Make Domain

#' @author Adam M. Wilson

#  Process 2018 Vegetation dataset to define project domain


#' @param vegmap is the domains of interest from the 2018 national vegetation map
#' @param vegmap_shp is the path to the 2018 national vegetation map - used to get national boundary
#' @param buffer size of domain buffer (in m)

domain_define <- function(vegmap, country){

  biomes = c("Fynbos")#,"Succulent Karoo")#,"Albany Thicket")


   vegmap_union=vegmap %>%
    filter(biome_18 %in%  biomes ) %>% #filter to list above
    st_union()   # union all polygons into one multipolygon, dissolving internal boundaries

  #buffer domain biomes
  vegmap_buffer= vegmap_union %>%
    st_simplify(dTolerance=500) %>%
    st_buffer(30000) %>%
    st_simplify(dTolerance=100)


  domain <-
    vegmap_buffer %>%
    st_intersection(st_transform(country,crs=st_crs(vegmap))) %>%  #only keep land areas of buffer - no ocean
    st_as_sf() %>%
    mutate(domain=1)

  # save the files

 # st_write(domain,dsn="data/domain.gpkg",append=F)

  return(domain)

}




