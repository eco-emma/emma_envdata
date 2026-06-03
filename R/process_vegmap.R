## Process Vegmap to add field related to biome type

process_vegmap <- function(domain_raster,
                        vegmap_shp,
                        disagg_factor = 10) {

  # Load domain raster (may be file path or multi-band SpatRaster from tar_terra_rast)
  domain <- if (is.character(domain_raster)) {
    # If it's a file path, load the 'domain' variable from NetCDF
    rast(domain_raster, subds = "domain")
  } else {
    domain_raster[["domain"]]  # extract domain band from the 4-band domain_grid SpatRaster
  }

  # Load and prep vegmap (accepts sf object or file path)
  vegmap_sf <- if (inherits(vegmap_shp, "sf") || inherits(vegmap_shp, "sfc")) {
    vegmap_shp
  } else {
    st_read(vegmap_shp, quiet = TRUE)
  }
  vegmap_sf <- vegmap_sf %>%
    janitor::clean_names() %>%
    st_make_valid() %>%
    st_transform(st_crs(domain, proj = TRUE)) %>%
    st_intersection(st_as_sfc(st_bbox(domain))) |>  #crop to domain
    mutate(t_vegtypeid = as.numeric(factor(t_mapcode))) #create numeric vegtype ID

  # Create fine template to reduce sliver effects, then modal aggregate back
  template_fine <- disagg(domain, disagg_factor)

  rasterize_modal <- function(field_name) {
    r_fine <- terra::rasterize(
      x = vect(vegmap_sf),
      y = template_fine,
      field = field_name,
      touches = TRUE
    )
    aggregated <- terra::aggregate(r_fine, disagg_factor, fun = "modal")
    # Resample to exactly match domain grid (nearest neighbor for categorical)
    terra::resample(aggregated, domain, method = "near")
  }

  biome_raster      <- rasterize_modal("t_biomeid")
  bioregion_raster  <- rasterize_modal("t_brgnid")
  vegtype_raster    <- rasterize_modal("t_vegtypeid")

  # Combine into multiband raster
  multiband <- c(biome_raster, bioregion_raster, vegtype_raster)
  names(multiband) <- c("vegbiome", "vegbioregion", "vegtype")

  # Mask to domain (set to NA where domain is NA)
  domain_mask <- !is.na(domain)
  multiband <- terra::mask(multiband, domain_mask, maskvalues = 0)

  # Lookup table for IDs -> names 
  lookup_tbl <- vegmap_sf %>%
    st_drop_geometry() %>% 
    dplyr::select(t_biomeid, t_brgnid, t_vegtypeid, t_mapcode, t_name, t_biome, t_bioregio) %>%
    dplyr::rename(vegbiome = t_biomeid, vegbioregion = t_brgnid, vegtype = t_vegtypeid) %>%
    dplyr::distinct()

  # Store lookup table as JSON embedded in COG TIFF GDAL metadata
  # terra::metags() writes to TIFFTAG_GDAL_METADATA; survives COG round-trip
  terra::metags(multiband) <- c(
    vegtype_lut  = jsonlite::toJSON(lookup_tbl, dataframe = "rows", auto_unbox = TRUE),
    source       = "South Africa National Vegetation Map 2024",
    date_created = as.character(Sys.Date())
  )
  terra::metags(multiband, layer = 1) <- c(
    description = "Biome ID (biomeid_18)", units = "dimensionless"
  )
  terra::metags(multiband, layer = 2) <- c(
    description = "Bioregion ID (brgnid_18)", units = "dimensionless"
  )
  terra::metags(multiband, layer = 3) <- c(
    description = "Vegetation type ID (derived from mapcode18)", units = "dimensionless"
  )

  multiband
}

if(F){
    test=rast(output_file)
    plot(test)
}