#' @author Adam Wilson
#' @description Make a map of the domain



domain_map <- function(domain, remnant){

  domain_rast = read_stars(remnant_distance,NA_value = 0)


ggplot(domain)+
    geom_sf()+
    geom_stars(data=domain_rast,na.rm=T)+
    theme_void()+
    scale_fill_viridis_c()
}
