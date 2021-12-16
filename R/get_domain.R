# Function to return domain information

#Define the regions we want (polygon if possible, bounding box otherwise)

#'@description This function gets a domain for use in rgee.  It preferentially looks for a shapefile, and failing that uses a boundinbox.
get_domain <- function(){

  if(file.exists("data/other_data/domain.shp")) {

    domain <- sf::read_sf("data/other_data/domain.shp")

    #Buffer the domain to get the object size down
    domain_buffered <- sf::st_buffer(x = domain,
                                     dist = 5000)

    sabb <- sf_as_ee(x = domain_buffered)
    sabb <- sabb$geometry()


  }else{


    ext <- readRDS(file = "data/other_data/domain_extent.RDS")

    sabb <- ee$Geometry$Rectangle(
      coords = ext,
      proj = "EPSG:4326",
      geodesic = FALSE
    )

    rm(ext)



  }

  return(sabb)

}

