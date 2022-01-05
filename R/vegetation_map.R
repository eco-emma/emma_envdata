# Make Domain

#' @author Adam M. Wilson

#  Process 2018 Vegetation dataset to define project domain

#' @param vegmap_shp is the path to the vegetation shapefile
#' @biomes list of biomes to keep

get_vegmap <- function(vegmap_shp,  biomes = c("Fynbos","Succulent Karoo","Albany Thicket")){

  # Must manually download the following and put in the raw_data folder
  # 2018 National Vegetation Map
  # http://bgis.sanbi.org/SpatialDataset/Detail/1674

  vegmap_za=st_read(vegmap_shp) %>%
    janitor::clean_names() %>%
    st_make_valid()

  vegmap <- vegmap_za %>%
    filter(biome_18 %in%  biomes ) %>% #filter to list above
    st_make_valid()   #some polygons had errors - this fixes them

#  st_write(vegmap,dsn = "data/vegmap.gpkg",append=F)

  return(vegmap)

  }


