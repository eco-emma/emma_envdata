library(tidyverse)
library(sf)
library(units)
library(stars)


proj="PROJCS['AEA_RSA_WGS84',GEOGCS['GCS_WGS_1984',DATUM['D_WGS_1984',SPHEROID['WGS_1984',6378137.0,298.257223563]],PRIMEM['Greenwich',0.0],UNIT['Degree',0.0174532925199433]],PROJECTION['Albers'],PARAMETER['False_Easting',0.0],PARAMETER['False_Northing',0.0],PARAMETER['Central_Meridian',25.0],PARAMETER['Standard_Parallel_1',-24.0],PARAMETER['Standard_Parallel_2',-33.0],PARAMETER['Latitude_Of_Origin',0.0],UNIT['Meter',1.0]]"


remnants_raw <- st_read("data/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp") %>%
  janitor::clean_names()

#Biomes
biomes <- unique(remnants_raw$biome)

biome_keep <- c("Fynbos","Succulent Karoo","Albany Thicket")

remnants <- remnants_raw %>%
  filter(biome %in% biome_keep ) %>% #filter to list above
  st_make_valid()   #some polygons had errors - this fixes them

# add area of each remnant
remnants$area <- st_area(remnants) %>%
  units::set_units(km^2)


remnants_union <- remnants %>%
  st_union() %>% # union first to combine adjacent units
  filter(area > set_units( 1, km^2))

domain=st_as_stars(st_bbox(remnants), dx = 0.00415, dy = 0.00415)

remnants_raster <- remnants %>%
  st_rasterize(template = domain )

plot(remnants_raster)

st_write(remnants,"data/remnants.gpkg",delete_dsn = T)
st_write(remnants_union,"data/remnants_union.gpkg",delete_dsn = T)

st_bbox(remnants)

