## Process Vegmap to add field related to biome type

data_vegmap <- function(domain_raster,
                        vegmap_shp,
                        disagg_factor = 10,
                        out_file = "data/raw/vegmap.nc") {

  # Load domain raster (may be passed as file path or raster object)
  domain <- if (is.character(domain_raster)) {
    # If it's a file path, load the 'domain' variable from NetCDF
    rast(domain_raster, subds = "domain")
  } else {
    domain_raster
  }

  # Load and prep vegmap
  vegmap_sf <- st_read(vegmap_shp, quiet = TRUE) %>%
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

  # Create output file path (ensure directory exists)
  output_file <- out_file
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  
  # Get spatial extent and resolution for dimensions
  ext <- ext(multiband)
  dx <- res(multiband)[1]
  dy <- res(multiband)[2]
  
  x_vals <- seq(ext$xmin + dx/2, ext$xmax - dx/2, by = dx)
  y_vals <- seq(ext$ymax - dy/2, ext$ymin + dy/2, by = -dy)
  
  # Define dimensions with coordinate vectors
  dim_x <- ncdf4::ncdim_def(name = "easting", units = "meter", vals = x_vals, longname = "easting")
  dim_y <- ncdf4::ncdim_def(name = "northing", units = "meter", vals = y_vals, longname = "northing")
  
  # Define variables with compression level 9 for categorical data (storage as short integers)
  var_biome <- ncdf4::ncvar_def(
    name = "vegbiome",
    units = "dimensionless",
    dim = list(dim_x, dim_y),
    longname = "Biome ID (biomeid_18)",
    missval = -32768,
    prec = "short",
    compression = 9
  )
  
  var_bioregion <- ncdf4::ncvar_def(
    name = "vegbioregion",
    units = "dimensionless",
    dim = list(dim_x, dim_y),
    longname = "Bioregion ID (brgnid_18)",
    missval = -32768,
    prec = "short",
    compression = 9
  )
  
  var_vegtype <- ncdf4::ncvar_def(
    name = "vegtype",
    units = "dimensionless",
    dim = list(dim_x, dim_y),
    longname = "Vegetation type code (mapcode18)",
    missval = -32768,
    prec = "short",
    compression = 9
  )
  
  # Create NetCDF file with all variables
  unlink(output_file)
  nc <- ncdf4::nc_create(
    filename = output_file,
    vars = list(var_biome, var_bioregion, var_vegtype),
    force_v4 = TRUE
  )
  
  # Convert rasters to matrices, transpose to match dimension order, replace NAs with fill values
  biome_matrix <- t(as.matrix(biome_raster, wide = TRUE))
  biome_matrix <- as.integer(biome_matrix)
  biome_matrix[is.na(biome_matrix)] <- -32768

  bioregion_matrix <- t(as.matrix(bioregion_raster, wide = TRUE))
  bioregion_matrix <- as.integer(bioregion_matrix)
  bioregion_matrix[is.na(bioregion_matrix)] <- -32768

  vegtype_matrix <- t(as.matrix(vegtype_raster, wide = TRUE))
  vegtype_matrix <- as.integer(vegtype_matrix)
  vegtype_matrix[is.na(vegtype_matrix)] <- -32768
  
  # Write data to variables
  ncdf4::ncvar_put(nc, var_biome, biome_matrix)
  ncdf4::ncvar_put(nc, var_bioregion, bioregion_matrix)
  ncdf4::ncvar_put(nc, var_vegtype, vegtype_matrix)
  
  # Add global attributes
  ncdf4::ncatt_put(nc, 0, "title", "Vegetation Map - Biome, Bioregion, and Vegetation Type")
  ncdf4::ncatt_put(nc, 0, "source", "South Africa National Vegetation Map 2024")
  ncdf4::ncatt_put(nc, 0, "history", paste0("created: ", Sys.time()))
  ncdf4::ncatt_put(nc, 0, "crs", as.character(crs(multiband)))
  ncdf4::ncatt_put(nc, 0, "Conventions", "CF-1.8")
  ncdf4::ncatt_put(nc, 0, "lookup_table_json", jsonlite::toJSON(lookup_tbl, dataframe = "rows", auto_unbox = TRUE))
  
  # Add CRS variable for CF compliance and GIS compatibility
  crs_var <- ncdf4::ncvar_def("crs", "", list(), prec = "integer")
  nc <- ncdf4::ncvar_add(nc, crs_var)
  
  crs_wkt <- as.character(crs(multiband))
#  ncdf4::ncatt_put(nc, "crs", "grid_mapping_name", "albers_conical_equal_area")
  ncdf4::ncatt_put(nc, "crs", "crs_wkt", crs_wkt)
  ncdf4::ncatt_put(nc, "crs", "spatial_ref", crs_wkt)
  
  # Add geotransform for GDAL compatibility
  ncdf4::ncatt_put(nc, "crs", "GeoTransform", paste(ext$xmin, dx, 0, ext$ymax, 0, -dy))
  
  # Add grid_mapping to data variables
  ncdf4::ncatt_put(nc, "vegbiome", "grid_mapping", "crs")
  ncdf4::ncatt_put(nc, "vegbioregion", "grid_mapping", "crs")
  ncdf4::ncatt_put(nc, "vegtype", "grid_mapping", "crs")
  
  # Close file
  ncdf4::nc_close(nc)
  
  return(output_file)
}

if(F){
    test=rast(output_file)
    plot(test)
}