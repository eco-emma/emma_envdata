# Files that must be manually downloaded

# 2018 National Vegetation Map
# http://bgis.sanbi.org/SpatialDataset/Detail/1674

biomes=c("Fynbos","Succulent Karoo")#,"Albany Thicket","Azonal Vegetation")

vegmap_all=st_read("data/VEGMAP2018_AEA_16082019Final/NVM2018_AEA_V22_7_16082019_final.shp") %>%
  st_make_valid()

vegmap <- vegmap_all %>%
  janitor::clean_names() %>%
  filter(biome_18 %in%  biomes ) %>% #filter to list above
  st_make_valid()   #some polygons had errors - this fixes them

vegmap_union=vegmap %>%
  st_union()

vegmap_buffer= vegmap_union %>%
  st_buffer(10000)

vegmap_buffer_clip <-
  vegmap_buffer %>%
  st_intersection(vegmap_union)

domain=st_as_stars(st_bbox(vegmap), dx = 500, dy = 500)

vegmap_raster <- vegmap %>%
  dplyr::select(biomeid_18) %>%
  st_rasterize(template = domain)

plot(vegmap_raster)



vegmap_buffer_clip %>% plot()


