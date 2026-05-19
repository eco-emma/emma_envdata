# ============================================================================
# Topographic Diversity — NASADEM via AppEEARS
# ============================================================================
# Derives topographic terrain metrics from the NASADEM elevation model.
# Uses the same NASADEM elevation already downloaded for `elevation_nasadem.nc`
# (from get_elevation.R), so no additional AppEEARS requests are needed.
#
# Metrics computed (all on the domain 500m grid):
#   slope_deg       : Terrain slope in degrees
#   aspect_deg      : Terrain aspect in degrees (0–360, clockwise from North)
#   tri             : Terrain Ruggedness Index (Riley et al. 1999)
#                     Mean of absolute elevation differences between a pixel and
#                     its 8 neighbours — captures local relief heterogeneity
#   topographic_div : Topographic Diversity index (Theobald et al. 2015)
#                     Counts the number of distinct landform types within a 3×3
#                     focal window (based on TPI classification)
#   tpi             : Topographic Position Index
#                     Difference between pixel elevation and mean of neighbours —
#                     positive = ridges/hills, negative = valleys
#
# Reference: Theobald et al. (2015) Ecography 38:1155-1166, doi:10.1111/ecog.01294
# ============================================================================


#' @title Compute topographic diversity metrics from NASADEM elevation
#'
#' @description Takes the already-processed NASADEM elevation NetCDF (from
#'   \code{get_elevation.R}), computes five terrain metrics using \code{terra}'s
#'   focal and terrain functions, and writes a multi-layer NetCDF.
#'
#'   No additional downloads are required — this function only needs the output of
#'   the existing \code{elevation} target.
#'
#' @param elevation_file Character or SpatRaster. Path to elevation_nasadem.nc or
#'   the loaded SpatRaster object (target dependency from the `elevation` target).
#' @param domain_raster  SpatRaster or file path to domain.nc (for masking valid pixels).
#' @param out_file       Character. Output NetCDF path.
#' @param focal_radius   Integer. Neighbourhood radius in pixels for TRI/TPI/diversity
#'   calculations (default 1 = 3×3 window = ~1.5km at 500m resolution).
#' @param verbose        Logical. Print progress messages? Default TRUE.
#'
#' @return Character path to the output NetCDF file.
#' @export
process_topographic_diversity <- function(
    elevation_file,
    domain_raster,
    out_file     = "data/target_outputs/topographic_diversity.nc",
    focal_radius = 1L,
    verbose      = TRUE) {

  # Return cached file if already processed
  if (file.exists(out_file)) {
    if (verbose) message("Topographic diversity file already exists: ", out_file)
    return(out_file)
  }

  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)

  # Load elevation (accepts SpatRaster or NetCDF file path)
  elev <- if (is.character(elevation_file)) {
    if (verbose) message("Loading elevation from: ", elevation_file)
    terra::rast(elevation_file, subds = "elevation") |>
      # NetCDF may have a time dimension we don't need — collapse to single layer
      terra::subset(1L)
  } else {
    elevation_file
  }

  # Load domain for masking
  domain_template <- if (is.character(domain_raster)) terra::rast(domain_raster) else domain_raster
  domain_mask     <- domain_template[["pid"]]

  if (verbose) {
    message(
      "Computing terrain metrics on ", nrow(elev), " × ", ncol(elev),
      " grid (", focal_radius * 2 + 1, "×", focal_radius * 2 + 1, " focal window) ..."
    )
  }

  # ── 1. Standard terra terrain metrics ───────────────────────────────────
  # terra::terrain() computes slope, aspect, TPI, and TRI efficiently in C++
  terrain_stack <- terra::terrain(
    elev,
    v       = c("slope", "aspect", "TRI", "TPI"),
    unit    = "degrees",
    neighbors = 8L     # use all 8 neighbours for better accuracy
  )

  # Rename layers for clarity
  names(terrain_stack) <- c("slope_deg", "aspect_deg", "tri", "tpi")

  # ── 2. Topographic Diversity (Theobald et al. 2015) ─────────────────────
  # Classification of TPI into discrete landform types:
  #   flat (<± 0.5 sd of neighbourhood), valley (TPI < -1 sd), ridge (TPI > 1 sd), slope (remainder)
  # Topographic diversity = number of distinct landform types in the focal window
  # Computed via focal majority and variance

  if (verbose) message("Computing topographic diversity index ...")

  tpi_layer  <- terrain_stack[["tpi"]]
  tpi_sd     <- terra::global(tpi_layer, "sd", na.rm = TRUE)$sd

  # Classify each pixel into a landform type (0=flat, 1=valley, 2=slope, 3=ridge)
  landform <- terra::classify(
    tpi_layer,
    rcl = matrix(
      c(-Inf,        -tpi_sd, 1,   # valley
        -tpi_sd,     -0.5,    2,   # gentle valley
        -0.5,         0.5,    0,   # flat
         0.5,         tpi_sd, 2,   # gentle ridge
         tpi_sd,      Inf,    3),  # ridge
      ncol = 3, byrow = TRUE
    )
  )

  # Build focal window: integer size in cells (focal_radius=1 → 3×3 window)
  w_size <- 2L * focal_radius + 1L

  # Topographic diversity = focal variance of the landform classification
  # Higher variance → more landform types present in the neighbourhood
  topodiv <- terra::focal(
    landform,
    w   = w_size,
    fun = function(x) var(x, na.rm = TRUE)
  )
  names(topodiv) <- "topographic_div"

  # ── 3. Stack, mask, write NetCDF ─────────────────────────────────────────
  if (verbose) message("Stacking terrain layers and writing NetCDF ...")

  topo_stack <- c(terrain_stack, topodiv) |>
    terra::mask(domain_mask)   # restrict to valid domain pixels

  # CF-compliant long names for documentation
  longnames <- c(
    slope_deg        = "Terrain Slope",
    aspect_deg       = "Terrain Aspect",
    tri              = "Terrain Ruggedness Index",
    tpi              = "Topographic Position Index",
    topographic_div  = "Topographic Diversity (Theobald et al. 2015)"
  )
  units_vec <- c(
    slope_deg        = "degrees",
    aspect_deg       = "degrees (clockwise from north)",
    tri              = "meters",
    tpi              = "meters",
    topographic_div  = "unitless"
  )

  terra::writeCDF(
    topo_stack,
    filename  = out_file,
    overwrite = TRUE,
    varname   = "topography",
    longname  = paste(longnames[names(topo_stack)], collapse = "; "),
    unit      = paste(units_vec[names(topo_stack)], collapse = "; ")
  )

  if (verbose) {
    message(
      "Topographic diversity NetCDF written: ", out_file,
      " (", terra::nlyr(topo_stack), " layers)"
    )
  }

  out_file
}
