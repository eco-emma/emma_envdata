#can you calculate the total area of the remaining remnants in the domain?
#Also, let's get the total area of protected areas in the domain. Let me now if you don't have that layer.

library(sf)
library(terra)
#Remnants

#load domain
targets::tar_load(domain)

#load remnants
remnants <- sf::read_sf("data/manual_download/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp")
remnants <- st_transform(x = remnants,
                         crs = st_crs(domain))


remnants <- st_crop(remnants, domain)

unique(remnants$NAME)
unique(remnants$BIOREGION)
unique(remnants$BIOME)



rem_union <- st_union(x = remnants,by_feature = FALSE)
plot(rem_union)

rem_int <-
st_intersection(x = rem_union,
                y = domain)

?st_intersection()


#crop remnants
?st_crop


plot(rem_int, col = "red")

st_area(rem_int)
st_area(domain)


#
sf::read_sf("scratch_code/SACAD_OR_2021_Q3.shp") %>%
  st_transform(x = .,
               crs = st_crs(domain)) %>%
  st_union(x = .,by_feature = FALSE) %>%
  st_intersection(x = ., y = domain) -> cons

cons
plot(domain[1])
plot(cons,add=TRUE,col="blue")

sf::read_sf("scratch_code/SAPAD_OR_2021_Q3.shp") %>%
  st_transform(x = .,
               crs = st_crs(domain)) %>%
  st_union(x = .,by_feature = FALSE) %>%
  st_intersection(x = ., y = domain) -> prot

plot(prot,add = TRUE, col = "green")

prot <- sf::read_sf("scratch_code/SAPAD_OR_2021_Q3.shp")

cp <- st_union(prot,cons)
plot(cp[1])

st_area(cons)*1e-6
st_area(prot)*1e-6
st_area(cp)*1e-6



plot(cons[1])
plot(prot[1])

