#Process domain

library(sf)
library(dplyr)
library(units)
#library(tidyverse)


#' @author Brian Maitner, using code from Adam and Jasper.
#' @description This code cleans up the RLE Remnants file to yield a simpler polygon that we can use as a domain.
#' @param remnants_file The file location of the remnants shapefile.  Defaults to "data/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp"
#' @param


process_domain <- function(remnants_file = "data/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp") {
  
  domain_files <- list.files("data/other_data/")
  if( length(grep(pattern = "domain.shp", x = domain_files)) > 0 &
      length(grep(pattern = "domain_extent.RDS", x = domain_files)) > 0
  ) {
    
    message("Domain and extent found, skipping processing.")
    return(invisible(NULL))
    
  }
  
  # V1
  
  # Load remnants file
  remnants_raw <- st_read("data/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp") %>%
    janitor::clean_names()
  
  # Define which biome(s) to keep
  biome_keep <- c("Fynbos")
  
  remnants <- remnants_raw %>%
    filter(biome %in% biome_keep ) %>% #filter to list above
    st_make_valid()   #some polygons had errors - this fixes them
  
  # add area of each remnant
  remnants$area <- st_area(remnants) %>%
    units::set_units(km^2)
  
  # Filter remnants by size and take the union
  remnants_union <- remnants %>%
    filter(area > units::set_units( 1, km^2)) %>%
    st_union()
  
  #Write output as something that can be imported into gee
  
    #rgee can take in sf or raster files using sf_as_ee or raster_as_ee
  
    st_write(obj = remnants_union,dsn = "data/other_data/domain.shp")
    saveRDS(object = st_bbox(obj = remnants_union),
            file = "data/other_data/domain_extent.RDS")
    
  
  # V2
  
  # st_read("data/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp") %>%
  #   st_union() %>% 
  #   st_cast(to = "POLYGON") %>% 
  #   st_as_sf() %>%
  #   dplyr::mutate(Area = st_area(.)) %>% 
  #   dplyr::filter(Area > set_units(1000000, m^2)) %>%
  #   st_write("remnants_merged1km.gpkg")
  # 
  # 
  
  
  message("Finished processing domain")
  return(invisible(NULL))
  
  
  
}
