#Process domain

library(sf)
library(dplyr)
library(units)
library(terra)


#' @author Adam Wilson & Brian Maitner
#' @description This code cleans up the RLE Remnants file to yield a simpler polygon that we can use as a domain.
#' @param remnants_shp The file location of the remnants shapefile.  Defaults to "data/RLE_2021_Remnants/RLE_Terr_2021_June2021_Remnants_ddw.shp"
#' @param template_release path to raster file to use as a template for reprojection

domain_remnants_release <- function(domain,
                                    remnants_shp,
                                    template_release,
                                    temp_directory = "data/temp/remnants",
                                    out_file = "remnants.tif",
                                    out_tag = "processed_static") {

  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }


  # Define which biome(s) to keep
    biome_keep <- c("Fynbos")

  # get template
    robust_pb_download(file = template_release$file,
                       dest = file.path(temp_directory),
                       repo = template_release$repo,
                       tag = template_release$tag,
                       overwrite = TRUE,
                       max_attempts = 10,
                       sleep_time = 10)

    template <- rast(file.path(temp_directory,template_release$file))

  # Load in a domain template in the MODIS projection
    domain_template <- st_as_stars(rast(template))

  # reproject domain to match the template
  domain <- domain %>%
    st_transform(crs = crs(rast(template)))


  # Load remnants file
  # remnants <- st_read(remnants_shp) %>%
  #   janitor::clean_names() %>%
  #   filter(biome %in% biome_keep ) %>% #filter to list above
  #   st_make_valid() %>%    #some polygons had errors - this fixes them
  #   st_combine() %>%
  #   st_cast(to = "POLYGON") %>%
  #   st_as_sf() %>%
  #   dplyr::mutate(area = units::set_units(st_area(.),km^2))
  #

  # Load remnants file
  remnants <- st_read(remnants_shp) %>%
    janitor::clean_names() %>%
    st_transform(crs = crs(domain)) %>%
    filter(biome %in% biome_keep ) %>% #filter to list above
    st_make_valid()


  domain_raster <- domain %>%
    dplyr::select(domain) %>%
    st_rasterize(template = domain_template, values = NA_real_)

  remnants_raster <- remnants %>%
    mutate(remnant=1) %>%
    vect() %>%
    rasterize(x = .,
              y = rast(domain_template),
              field = "remnant",
              touches = T,
              cover = T)

  writeRaster(remnants_raster,
              file = file.path(temp_directory,out_file),
              overwrite = T)

  pb_upload(file = file.path(temp_directory,out_file),
            repo = template_release$repo,
            tag = out_tag)

  file_md <- list(repo = template_release$repo,
                  tag = out_tag,
                  file = out_file)

  #cleanup
   unlink(x = temp_directory, recursive = TRUE, force = TRUE)

  #end

  return(file_md)

}

domain_distance_release <- function(remnants_release,
                                    out_file="remnant_distance.tif",
                                    temp_directory = "data/temp/remnants",
                                    out_tag = "processed_static"
                                    ){

  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }

  #get the raster
    robust_pb_download(file = remnants_release$file,
                       dest = file.path(temp_directory),
                       repo = remnants_release$repo,
                       tag = remnants_release$tag,
                       overwrite = TRUE,
                       max_attempts = 10,
                       sleep_time = 10)

  # errors thrown in this chunk when running on github, but don't seem to break anything, so...meh.
  distance_raster <-
    rast(file.path(temp_directory,remnants_release$file)) %>%
    terra::app(fun=function(x) ifelse(is.na(x),1,NA)) %>%
    terra::gridDistance()/1000
    #terra::distance(grid=T)/1000


  writeRaster(distance_raster,
              file = file.path(temp_directory,out_file),
              overwrite = T)

  #release
    pb_upload(file = file.path(temp_directory,out_file),
              repo = remnants_release$repo,
              tag = out_tag)

  #get md
    file_md <- list(repo = remnants_release$repo,
                    tag = out_tag,
                    file = out_file)

  #cleanup
  unlink(x = temp_directory, recursive = TRUE, force = TRUE)

  #end

  return(file_md)

}
