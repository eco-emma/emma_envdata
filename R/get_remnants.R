#' Download RLE 2021 remnants shapefile from GitHub release
#'
#' Downloads the RLE 2021 Remnants shapefile from a GitHub release using
#' piggyback, unzips it into a local directory, and returns the loaded sf
#' object.
#'
#' @param repo character. GitHub repository in "owner/repo" format.
#' @param tag character. Release tag for the manual-data release.
#' @param local_dir character. Local directory to store the unzipped shapefile.
#'
#' @return sf object. The loaded RLE 2021 remnants polygon dataset.
#'
#' @details If the shapefile already exists at \code{local_dir}, no download
#' is performed. Otherwise the zip is downloaded via piggyback and extracted.
#'
#' @importFrom piggyback pb_download
#' @importFrom utils unzip
#' @importFrom sf st_read
#' @export
get_remnants <- function(
    repo      = "eco-emma/emma_envdata",
    tag       = "manual-data",
    local_dir = "data/manual_download/RLE_2021_Remnants"
) {
  shp_file <- file.path(local_dir, "RLE_Terr_2021_June2021_Remnants_ddw.shp")

  if (!file.exists(shp_file)) {
    message("Downloading RLE 2021 remnants from GitHub release '", tag, "'...")
    dir.create(local_dir, recursive = TRUE, showWarnings = FALSE)
    download.file("https://github.com/eco-emma/emma_envdata/releases/download/manual-data/RLE_2021_Remnants.zip",
      destfile= file.path(local_dir, "RLE_2021_Remnants.zip"), mode = "wb")
    zip_file <- file.path(local_dir, "RLE_2021_Remnants.zip")
    utils::unzip(zip_file, exdir = local_dir)
    unlink(zip_file)
  }

  sf::st_read(shp_file)
}
