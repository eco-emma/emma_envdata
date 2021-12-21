#' @author Adam Wilson
#' @description Make a map of the domain



domain_map <- function(domain, remnant){

  tar_load(remnant_distance)
  tar_load(za)
  tar_load(domain)
  tar_load(vegmap)

  domain_rast = read_stars(remnant_distance,NA_value = 0) %>%
        mutate(core=ifelse(remnant_distance.tif>0,remnant_distance.tif/1000,NA))

  #fynbos=st_read("data/fynbos.gpkg")

  ggplot()+
#    geom_sf(data=za, fill=grey(0.9))+
    geom_sf(data=domain, fill=grey(0.8),col=NA)+
    geom_sf(data=fynbos, fill=grey(0.5),col=NA)+
    geom_stars(data= dplyr::select(domain_rast,core),na.rm=T)+
    geom_sf(data=za, fill=NA)+
    theme_void()+
    coord_sf(xlim = st_bbox(domain)[c("xmin","xmax")],ylim=st_bbox(domain)[c("ymin","ymax")])+
    scale_fill_viridis_c(na.value = NA,name="Distance to\nremnant edge (km)")+
    scale_color_manual(values = fill)

  }
