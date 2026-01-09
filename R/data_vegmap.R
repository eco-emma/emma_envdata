## Process Vegmap to add field related to biome type

data_vegmap <- function(domain_raster, vegmap_shp, disagg_factor = 10) {

  # Load and prep vegmap
  vegmap_sf <- st_read(vegmap_shp, quiet = TRUE) %>%
    janitor::clean_names() %>%
    st_make_valid() %>%
    st_transform(st_crs(domain_raster)) %>%
    st_intersection(st_as_sfc(st_bbox(domain_raster)))|>  #crop to domain
    mutate(vegtype_id = as.numeric(factor(mapcode18))) #create numeric vegtype ID
  # Create fine template to reduce sliver effects, then modal aggregate back
  template_fine <- disagg(rast(domain_raster), disagg_factor)

  rasterize_modal <- function(field_name) {
    r_fine <- terra::rasterize(
      x = vect(vegmap_sf),
      y = template_fine,
      field = field_name,
      touches = TRUE
    )
    terra::aggregate(r_fine, disagg_factor, fun = "modal")
  }

  biome_raster      <- rasterize_modal("biomeid_18")
  bioregion_raster  <- rasterize_modal("brgnid_18")
  vegtype_raster    <- rasterize_modal("vegtype_id")

  # Combine into multiband raster
  multiband <- c(biome_raster, bioregion_raster, vegtype_raster)
  names(multiband) <- c("vegbiome", "vegbioregion", "vegtype")

  # Mask to domain (set to NA where domain_raster is NA)
  domain_mask <- !is.na(rast(domain_raster))
  multiband <- terra::mask(multiband, domain_mask, maskvalues = 0)

  # Per-band metadata
  attr(multiband[[1]], "long_name") <- "Biome ID (biomeid_18)"
  attr(multiband[[1]], "units")     <- "dimensionless"

  attr(multiband[[2]], "long_name") <- "Bioregion ID (brgnid_18)"
  attr(multiband[[2]], "units")     <- "dimensionless"

  attr(multiband[[3]], "long_name") <- "Vegetation type code (mapcode18)"
  attr(multiband[[3]], "units")     <- "dimensionless"

  # Lookup table for IDs -> names (stored as JSON for CF attributes)
  lookup_tbl <- vegmap_sf %>%
    st_drop_geometry() %>%
    dplyr::select(biomeid_18, brgnid_18, vegtype_id, mapcode18, name_18, biome_18, bioregion) %>%
    dplyr::rename(vegbiome = biomeid_18, vegbioregion = brgnid_18,vegtype=vegtype_id) %>%
    dplyr::distinct()

  attr(multiband, "lookup_table_json") <- jsonlite::toJSON(lookup_tbl, dataframe = "rows", auto_unbox = TRUE)
  attr(multiband, "date_generated")    <- as.character(Sys.time())
  attr(multiband, "crs")               <- as.character(crs(multiband))
  attr(multiband, "Conventions")       <- "CF-1.8"

  multiband
}

