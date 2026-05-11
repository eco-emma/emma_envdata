#' Download vegetation map release and return shapefile path
#'
#' Downloads a zipped vegetation map from a GitHub release using piggyback,
#' unzips it into a local directory, and returns the path to the `.shp` file
#' for use in targets.
#'
#' @param repo character. GitHub repository in "owner/repo" format.
#' @param tag character. Release tag (e.g., "latest" or "v1.0.0").
#' @param file character. Name of the release asset file to download (e.g., "vegmap.zip").
#' @param local_dir character. Local directory to store the unzipped files.
#' @param shapefile_name character. Name of the shapefile to return (e.g., "NVM2024Final_IEM5_12_07012025.shp").
#'
#' @return character. Full path to the shapefile on disk.
#'
#' @details If the shapefile already exists at `local_dir`, no download
#' is performed. Otherwise, the zip file is downloaded via piggyback and extracted.
#'
#'
#' @importFrom piggyback pb_download
#' @importFrom utils unzip
#' @export
get_vegmap <- function(repo, tag, file, local_dir, shapefile_name) {
  dir.create(local_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Check if shapefile already exists in the expected location (with shapefile subdirectory)
  shp_file_correct <- file.path(local_dir, "shapefile", shapefile_name)
  
  if (!file.exists(shp_file_correct)) {
    message("Downloading vegmap from GitHub release using piggyback...")
    piggyback::pb_download(
      file = file,
      repo = repo,
      tag = tag,
      dest = local_dir,
      overwrite = FALSE
    )
    message("Unzipping vegmap...")
    list.files(local_dir,recursive = T)
    zip_file <- file.path(local_dir, file)
    utils::unzip(zip_file, exdir = local_dir)
    unlink(zip_file)
  }
  
  # Return the sf object 
  st_read(shp_file_correct)
}
