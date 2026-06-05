#' @title Combine all static environmental layers into a single geoparquet
#' @description Joins all static covariates (remnants, elevation, climate,
#'   clouds, soil, topography, vegmap) onto the domain pixel grid and writes
#'   a single geoparquet file. One row per 500m domain pixel; point geometry
#'   in the domain CRS (Albers Equal Area, South Africa).
#' @param domain_parquet Path to domain.parquet (pid + point geometry).
#' @param domain_raster Path to domain.nc (provides remnants + remnants_distance).
#' @param elevation Path to elevation_nasadem.nc.
#' @param climate_files Character vector of CHELSA bioclimatic NC file paths
#'   (BIO1–BIO19; 1981–2010 climatology).
#' @param clouds_nc Path to clouds_wilson.nc (mean annual cloudiness +
#'   seasonality).
#' @param soil Path to soil_soilgrids.nc (SOC, clay, sand, pH, bulk density;
#'   0–30 cm depth-weighted means).
#' @param topo Path to topographic_diversity.nc (slope, aspect, TRI, TPI,
#'   topographic diversity index).
#' @param vegmap Path to vegmap.nc (vegbiome, vegbioregion, vegtype).
#' @param out_file Output geoparquet file path.
#' @param verbose Logical; print progress messages.
#' @return Character path to the written geoparquet file.

combine_static_layers_to_geoparquet <- function(
  domain_parquet   = "data/target_outputs/domain.parquet",
  domain_raster,
  elevation,
  climate_files,
  clouds,
  soil,
  topo,
  vegmap,
  out_file         = "data/target_outputs/static_covariates.parquet",
  verbose          = TRUE
) {

  # Load domain geoparquet: one row per 500m pixel; pid + point geometry
  # (Albers Equal Area projection, South Africa)
  if (verbose) message("Loading domain spatial reference: ", domain_parquet)
  domain_sf <- sfarrow::st_read_parquet(domain_parquet)
  if (verbose) message("Domain: ", nrow(domain_sf), " pixels")

  # Convert to SpatVector for terra::extract() lookups
  domain_vect <- terra::vect(domain_sf)

  # Helper: extract raster values at domain pixel centres and drop the ID
  # column that terra adds (we rely on row-order alignment, not ID matching)
  extract_vals <- function(rast_obj) {
    terra::extract(rast_obj, domain_vect, bind = FALSE) |>
      dplyr::select(-ID)
  }

  # ── Domain-derived static layers ──────────────────────────────────────────
  # remnants: % cover of natural vegetation remnants per 500m pixel
  # remnants_distance: Euclidean distance to nearest remnant pixel (m)
  if (verbose) message("Extracting remnants and distance-to-remnant layers ...")
  domain_rast <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  domain_vals <- extract_vals(domain_rast[[c("remnants", "remnants_distance")]])

  # ── Elevation (NASADEM, resampled to 500m grid, metres a.s.l.) ────────────
  if (verbose) message("Extracting elevation ...")
  elev_vals <- elevation |> extract_vals()

  # ── Climate: CHELSA BIO1–BIO19 (1981–2010 reference period) ───────────────
  # One NC file per bioclimatic variable; stacked here for a single extract pass
  if (verbose) message(
    "Extracting CHELSA climate (", length(climate_files), " variables) ..."
  )
  climate_vals <- terra::rast(climate_files) |> extract_vals() #need rast because of multiple files

  # ── Cloud cover: Wilson MODCF (mean annual cloudiness + seasonality) ───────
  if (verbose) message("Extracting cloud cover ...")
  cloud_vals <- clouds |> extract_vals()

  # ── Soil properties: SoilGrids v2 (0–30 cm depth-weighted means) ──────────
  # Properties: SOC (g/kg), clay (g/kg), sand (g/kg), pH (×10), bulk density
  if (verbose) message("Extracting soil properties ...")
  soil_vals <- soil |> extract_vals()

  # ── Topographic diversity (slope_deg, aspect_deg, TRI, TPI, topodiv) ───────
  # Derived from NASADEM at 500m; focal radius = 1 pixel
  if (verbose) message("Extracting topographic diversity ...")
  topo_vals <- topo |> extract_vals()

  # ── Vegetation map: NVM2024 (biome, bioregion, vegtype) ───────────────────
  if (verbose) message("Extracting vegetation map ...")
  veg_vals <- vegmap |> extract_vals()

  # ── Assemble all covariates and write geoparquet ───────────────────────────
  n_cov <- ncol(domain_vals) + ncol(elev_vals) + ncol(climate_vals) +
    ncol(cloud_vals) + ncol(soil_vals) + ncol(topo_vals) + ncol(veg_vals)
  if (verbose) message(
    "Assembling ", nrow(domain_sf), " pixels × ", n_cov, " covariates ..."
  )

  static_sf <- domain_sf |>
    dplyr::bind_cols(
      domain_vals,
      elev_vals,
      climate_vals,
      cloud_vals,
      soil_vals,
      topo_vals,
      veg_vals
    )

  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  sfarrow::st_write_parquet(static_sf, out_file)

  if (verbose) message("Static covariates geoparquet written: ", out_file)
  out_file
}
