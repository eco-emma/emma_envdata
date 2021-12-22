#' @author Adam Wilson
#' @description Make a map of the domain



domain_map <- function(domain, remnant){
  tar_load(remnant_distance)
  tar_load(country)
  tar_load(domain)
  tar_load(vegmap)

  domain_rast = read_stars(remnant_distance,NA_value = 0)

  #fynbos=st_read("data/fynbos.gpkg")

  ggplot()+
#    geom_sf(data=za, fill=grey(0.9))+
    geom_sf(data=domain, fill=grey(0.8),col=NA)+
    geom_stars(data=domain_rast,na.rm=T)+
    geom_sf(data=country, fill=NA)+
    theme_void()+
    coord_sf(xlim = st_bbox(domain)[c("xmin","xmax")],ylim=st_bbox(domain)[c("ymin","ymax")])+
    scale_fill_viridis_c(na.value = NA,name="Distance to\nremnant edge\n(km)")+
    scale_color_manual(values = fill)

  }
