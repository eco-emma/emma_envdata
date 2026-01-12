#' Download vegetation map release and return shapefile path
#'
#' Downloads a zipped vegetation map from a GitHub release, unzips it
#' into a local directory, and returns the path to the `.shp` file
#' for use in targets.
#'
#' @param release_url character. URL to the GitHub release asset (zip file).
#' @param local_dir character. Local directory to store the unzipped files.
#' @param shapefile_name character. Name of the shapefile to return (e.g., "NVM2024Final_IEM5_12_07012025.shp").
#'
#' @return character. Full path to the shapefile on disk.
#'
#' @details If the shapefile already exists at `local_dir`, no download
#' is performed. Otherwise, the zip file is downloaded and extracted.
#'
#'
#' @importFrom utils download.file unzip
#' @export
download_vegmap_release <- function(release_url, local_dir, shapefile_name) {
  dir.create(local_dir, recursive = TRUE, showWarnings = FALSE)
  shp_file <- file.path(local_dir, shapefile_name)
  if (!file.exists(shp_file)) {
    zip_file <- file.path(local_dir, "vegmap.zip")
    message("Downloading vegmap from GitHub release...")
    utils::download.file(release_url, zip_file, mode = "wb")
    message("Unzipping vegmap...")
    utils::unzip(zip_file, exdir = local_dir)
    unlink(zip_file)
  }
  stringr::str_replace(shp_file, "NVM2024/","NVM2024/shapefile/") # fixes path issue
}
