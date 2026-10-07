#' @title Migrate release assets below GitHub's 1,000-asset limit
#' @description Regenerates and publishes the EMMA STAC across separate release
#'   tags and migrates MODIS Terra and Aqua COGs to sensor-specific releases.
#' @keywords internal
source("R/upload_releases.R")
source("R/stac_functions.R")

repo <- "eco-emma/emma_envdata"
release_tags <- list(
  vi_modis_terra = "vi_modis_terra_raster",
  vi_modis_aqua = "vi_modis_aqua_raster",
  vi_viirs = "vi_viirs_raster",
  stac_root = "stac",
  stac_vi = "stac-vi",
  stac_burn = "stac-burn",
  stac_static = "stac-static"
)

token <- Sys.getenv("GITHUB_PAT")
if (token == "") token <- Sys.getenv("GITHUB_TOKEN")
if (token == "") {
  token <- trimws(
    system("gh auth token", intern = TRUE, ignore.stderr = TRUE)[[1]]
  )
}
if (!nzchar(token)) {
  stop("No GitHub token found (GITHUB_PAT, GITHUB_TOKEN, or gh CLI).")
}

modis_terra <- list.files(
  "data/target_outputs/modis_vi",
  pattern = "^vi_modis_terra_[0-9]{8}\\.tif$",
  full.names = TRUE
)
modis_aqua <- list.files(
  "data/target_outputs/modis_vi",
  pattern = "^vi_modis_aqua_[0-9]{8}\\.tif$",
  full.names = TRUE
)
viirs_tifs <- list.files(
  "data/target_outputs/viirs_vi",
  pattern = "^vi_viirs_(snpp|noaa20)_[0-9]{8}\\.tif$",
  full.names = TRUE
)

if (!length(modis_terra) || !length(modis_aqua)) {
  stop("Local MODIS Terra/Aqua COGs are required for the release migration.")
}

vi_stac <- generate_modis_vi_stac(
  tif_files = c(modis_terra, modis_aqua),
  viirs_tif_files = viirs_tifs,
  stac_dir = "data/stac/vi",
  gh_repo = repo,
  gh_release_tag_modis_terra = release_tags$vi_modis_terra,
  gh_release_tag_modis_aqua = release_tags$vi_modis_aqua,
  gh_release_tag_viirs = release_tags$vi_viirs,
  gh_stac_release_tag = release_tags$stac_vi,
  gh_stac_item_release_prefix = release_tags$stac_vi,
  gh_root_stac_release_tag = release_tags$stac_root,
  verbose = TRUE
)

burn_modis <- list.files(
  "data/target_outputs/burndates",
  pattern = "^burn_modis_[0-9]{6}\\.tif$",
  full.names = TRUE
)
burn_viirs <- list.files(
  "data/target_outputs/burndates",
  pattern = "^burn_viirs_[0-9]{6}\\.tif$",
  full.names = TRUE
)

burn_stac <- generate_burn_stac(
  modis_tif_files = burn_modis,
  viirs_tif_files = burn_viirs,
  recentburn_file = "data/target_outputs/fireage_current.tif",
  stac_dir = "data/stac/burn",
  gh_repo = repo,
  gh_stac_release_tag = release_tags$stac_burn,
  gh_root_stac_release_tag = release_tags$stac_root,
  verbose = TRUE
)

climate_files <- list.files(
  "data/target_outputs",
  pattern = "^CHELSA_bio[0-9]+_.*\\.tif$",
  full.names = TRUE
)

static_stac <- generate_static_layers_stac(
  domain_file = "data/target_outputs/domain.tif",
  domain_parquet = "data/target_outputs/domain.parquet",
  vegmap_file = "data/target_outputs/vegmap.tif",
  elevation = "data/target_outputs/elevation.tif",
  climate_files = climate_files,
  clouds = "data/target_outputs/clouds.tif",
  soil = "data/target_outputs/soils.tif",
  topo = "data/target_outputs/geodiversity.tif",
  stac_dir = "data/stac/static",
  gh_repo = repo,
  gh_stac_release_tag = release_tags$stac_static,
  gh_root_stac_release_tag = release_tags$stac_root,
  static_covariates_parquet =
    "data/target_outputs/static_covariates.parquet",
  verbose = TRUE
)

catalog <- generate_emma_stac_catalog(
  stac_base_dir = "data/stac",
  dataset_collections = list(
    vi = "data/stac/vi",
    burn = "data/stac/burn",
    static = "data/stac/static"
  ),
  dataset_release_tags = c(
    vi = release_tags$stac_vi,
    burn = release_tags$stac_burn,
    static = release_tags$stac_static
  ),
  root_release_tag = release_tags$stac_root,
  gh_repo = repo,
  verbose = TRUE
)

upload_to_github_release(
  files = modis_terra,
  repo = repo,
  release_tag = release_tags$vi_modis_terra,
  release_name = "Dynamic MODIS Terra VI Rasters (16-day composites)",
  overwrite = TRUE,
  verbose = TRUE
)
upload_to_github_release(
  files = modis_aqua,
  repo = repo,
  release_tag = release_tags$vi_modis_aqua,
  release_name = "Dynamic MODIS Aqua VI Rasters (16-day composites)",
  overwrite = TRUE,
  verbose = TRUE
)

vi_collection_file <- vi_stac[basename(vi_stac) == "vi_collection.json"]
vi_item_files <- vi_stac[grepl("^vi_[0-9]{8}\\.json$", basename(vi_stac))]
vi_item_years <- substr(basename(vi_item_files), 4L, 7L)
vi_item_decades <- paste0(substr(vi_item_years, 1L, 3L), "0s")

upload_to_github_release(
  files = vi_collection_file,
  repo = repo,
  release_tag = release_tags$stac_vi,
  release_name = "STAC - Vegetation Indices",
  overwrite = TRUE,
  verbose = TRUE
)
purrr::iwalk(split(vi_item_files, vi_item_decades), function(files, decade) {
  if (length(files) > 999L) {
    stop("VI STAC decade '", decade, "' exceeds 999 uploaded assets.")
  }
  upload_to_github_release(
    files = files,
    repo = repo,
    release_tag = paste0(release_tags$stac_vi, "-", decade),
    release_name = paste("STAC - Vegetation Indices", decade),
    overwrite = TRUE,
    verbose = TRUE
  )
})

stac_uploads <- list(
  burn = list(
    files = burn_stac,
    tag = release_tags$stac_burn,
    name = "STAC - Burned Area"
  ),
  static = list(
    files = static_stac,
    tag = release_tags$stac_static,
    name = "STAC - Static Environmental Layers"
  )
)

purrr::walk(stac_uploads, function(upload) {
  if (length(upload$files) > 999L) {
    stop("Release '", upload$tag, "' would exceed 999 uploaded assets.")
  }
  upload_to_github_release(
    files = upload$files,
    repo = repo,
    release_tag = upload$tag,
    release_name = upload$name,
    overwrite = TRUE,
    verbose = TRUE
  )
})

upload_to_github_release(
  files = catalog,
  repo = repo,
  release_tag = release_tags$stac_root,
  release_name = "STAC Catalog - Current",
  overwrite = TRUE,
  verbose = TRUE
)

message("STAC migration complete. Reload the root catalog in QGIS.")
