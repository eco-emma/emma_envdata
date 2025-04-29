# Make Domain

#' @author Brian S. Maitner

#  Process 2018 Vegetation dataset into a raster with MODIS specs


#' @param vegmap_shp path to the 2018 national vegetation map shapefile
#' @param template_release path information to template release.
#' @param temp_directory temporary directory.  will be deleted.
#' @param sleep_time amount of time (in seconds) to pause after a Github query. Defaults to 10.

process_release_biome_raster <- function(template_release,
                                         vegmap_shp,
                                         domain,
                                         temp_directory = "data/temp/raw_data/vegmap_raster/",
                                         sleep_time = 10){

  # Ensure directory is empty if it exists

  if(dir.exists(file.path(temp_directory))){
    unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
  }

  # make a directory if one doesn't exist yet

  if(!dir.exists(file.path(temp_directory))){
    dir.create(file.path(temp_directory), recursive = TRUE)
  }

  # get template raster

    robust_pb_download(file = template_release$file,
                       dest = temp_directory,
                       repo = template_release$repo,
                       tag = template_release$tag,
                       max_attempts = 10,
                       sleep_time = sleep_time)

  # load template

    template <- terra::rast(file.path(temp_directory, template_release$file))

  # load vegmap

    vegmap_za <- st_read(vegmap_shp) %>%
      janitor::clean_names() %>%
      st_make_valid() %>%
      st_transform(crs = crs(template))

  #transform domain
    domain %>% st_transform(crs = crs(template)) -> domain

  #crop vegmap to save size?

    vegmap_za %>%
    st_intersection(y = domain) -> vegmap_za

  # rasterize vegmap

    # Note: the Github version of exactextractr could do this more simply using exactextractr::coverage_fraction()

    n <- 10 #number of subcells to use for aggregation

    template <- disagg(rast(template), n) #break raster into smaller one

    #r <- disagg(template, n) #break raster into smaller one: this is more memory-intense

    r <- rasterize(x = vect(vegmap_za),
                   y =  template,
                   field = "biome_18") #rasterize at fine resolution

    out_rast <- aggregate(r, n, "modal") #re-aggregate using modal  biome

  # save output version

    writeRaster(x = out_rast,
                filename = file.path(temp_directory,"biome_raster_modis_proj.tif"),
                overwrite=TRUE)

  # upload transformed version

    pb_upload(file = file.path(temp_directory,"biome_raster_modis_proj.tif"),
              repo = "AdamWilsonLab/emma_envdata",
              tag = "processed_static",
              name = "biome_raster_modis_proj.tif")

    pb_upload(file = file.path(temp_directory,"biome_raster_modis_proj.tif.aux.xml"),
              repo = "AdamWilsonLab/emma_envdata",
              tag = "processed_static",
              name = "biome_raster_modis_proj.tif.aux.xml")

    # cleanup

    unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)

    # End functions

      message("Finished rasterizing vegmap")
      return(as.character(Sys.Date()))


}




