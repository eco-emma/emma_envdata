# Make Domain

#' @author Adam M. Wilson

#  Process 2018 Vegetation dataset to define project domain


#' @param vegmap is the domains of interest from the 2018 national vegetation map
#' @param vegmap_shp is the path to the 2018 national vegetation map - used to get national boundary
#' @param buffer size of domain buffer (in m)

domain_define <- function(vegmap, country){

  require(smoothr)

  biomes = c("Fynbos")#,"Succulent Karoo")#,"Albany Thicket")


   vegmap_union=vegmap %>%
    filter(biome_18 %in%  biomes ) %>% #filter to list above
    st_union()   # union all polygons into one multipolygon, dissolving internal boundaries

  #buffer domain biomes
  vegmap_buffer= vegmap_union %>%
    st_simplify(dTolerance=500) %>%
    st_buffer(set_units(set_units(100,km),m)) #%>%

# v2<-  vegmap_buffer %>%
#     smooth(method = "ksmooth",smoothness=25)
#
# plot(vegmap_union);      plot(v2,add=T)

  domain <-
    vegmap_buffer %>%
    smooth(method = "ksmooth",smoothness=50) %>%
#    st_intersection(st_transform(country,crs=st_crs(vegmap))) %>%  #only keep land areas of buffer - no ocean
    st_as_sf() %>%
    mutate(domain=1) %>%
    st_make_valid() %>%
    st_transform(4326)

  # save the files
 st_write(domain,dsn="data/bioscape_domain.gpkg",append=F)
 file.remove("data/bioscape_domain.geojson"); st_write(domain,dsn="data/bioscape_domain.geojson",append=F)

  return(domain)

}




