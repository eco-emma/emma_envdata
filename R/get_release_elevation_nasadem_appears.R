#Code for extracting elevation data from google earth engine

#' @author Brian Maitner
#' @description This function will download NASADEM elevation data if it isn't present, and (invisibly) return a NULL if it is present
#' @import rgee
#' @param directory directory to save data in. Defaults to "data/raw_data/elevation_nasadem/"
#' @param domain domain (spatialpolygons* object) used for masking
get_release_elevation_nasadem <- function(temp_directory = "data/temp/raw_data/elevation_nasadem/",
                                          tag = "raw_static",
                                          domain){

  API_URL = 'https://appeears.earthdatacloud.nasa.gov/api/'


  # Make a directory if one doesn't exist yet

  if(!dir.exists(temp_directory)){
    dir.create(temp_directory,recursive = TRUE)
  }


  library(sf)
  library(httr)
  library(jsonlite)
  library(lubridate)

  # Helper to read .netrc credentials
  read_netrc <- function(machine = "appeears.earthdatacloud.nasa.gov", netrc_path = "~/.netrc") {
    lines <- readLines(path.expand(netrc_path))
    start <- grep(paste("machine", machine), lines)
    if (length(start) == 0) stop("Machine not found in .netrc")
    chunk <- lines[start:min(start+2, length(lines))]
    login <- sub(".*login\\s+", "", grep("login", chunk, value = TRUE))
    password <- sub(".*password\\s+", "", grep("password", chunk, value = TRUE))
    list(username = login, password = password)
  }

  download_nasadem_nc_from_sf <- function(aoi_sf, out_file = "nasadem.nc", netrc_path = "~/.netrc") {
    # Authenticate using .netrc file
    auth_response <- POST(
      url = "https://appeears.earthdatacloud.nasa.gov/api/login",
      #config = httr::config(netrc = TRUE, netrc_file = "~/.netrc"),
      set_cookies("LC" = "cookies")
    )
    str(auth_response)

    response <- GET(files[i], write_disk(filename, overwrite = TRUE), progress(),
                    config(netrc = TRUE, netrc_file = netrc), set_cookies("LC" = "cookies"))


    response <- httr::POST(
      url = "https://appeears.earthdatacloud.nasa.gov/api/task",
      body = jsonlite::toJSON(request_body, auto_unbox = TRUE),
      config = httr::config(netrc = TRUE, netrc_file = "~/.netrc"),
  httr::content_type_json()
)

    if (status_code(auth_response) != 200) {
      stop("Authentication failed. Check your .netrc file.")
    }

    token <- content(auth_response)$token

    # Transform AOI to WGS84 if needed
    if (sf::st_crs(aoi_sf)$epsg != 4326) {
      aoi_sf <- sf::st_transform(aoi_sf, crs = 4326)
    }

    # Extract coordinates
    coords <- st_coordinates(st_geometry(st_union(aoi_sf)))[, 1:2]
    coords <- as.matrix(coords)
    coords <- coords[!duplicated(coords), ]
    coords_list <- lapply(seq_len(nrow(coords)), function(i) unname(as.numeric(coords[i, ])))

    # Close polygon if needed
    if (!all.equal(coords_list[[1]], coords_list[[length(coords_list)]])) {
      coords_list[[length(coords_list) + 1]] <- coords_list[[1]]
    }

    # Build request
    request_body <- list(
      task_type = "area",
      task_name = paste0("NASADEM_", Sys.Date()),
      params = list(
        dates = list(list(startDate = "2020-01-01", endDate = "2020-01-01")),
        layers = list(list(layer = "NASADEM-HGT", product = "NASADEM_HGT.001")),
        output = list(format = "netCDF4"),
        geo = list(
          type = "Feature",
          properties = new.env(),
          geometry = list(
            type = "Polygon",
            coordinates = list(coords_list)
          )
        )
      )
    )

    # Submit task
    submit_response <- POST(
      url = "https://appeears.earthdatacloud.nasa.gov/api/task",
      body = toJSON(request_body, auto_unbox = TRUE),
      add_headers(Authorization = paste("Bearer", token)),
      content_type_json()
    )

    if (status_code(submit_response) != 200) {
      stop("Failed to submit task.")
    }

    task_id <- content(submit_response)$task_id
    message("Task submitted: ", task_id)

    # Poll for completion
    repeat {
      Sys.sleep(10)
      status_response <- GET(paste0("https://appeears.earthdatacloud.nasa.gov/api/status/", task_id),
                             add_headers(Authorization = paste("Bearer", token)))
      status <- content(status_response)$status
      message("Task status: ", status)
      if (status == "done") break
      if (status == "failed") stop("Task failed.")
    }

    # Get download URL
    bundle_response <- GET(paste0("https://appeears.earthdatacloud.nasa.gov/api/bundle/", task_id),
                           add_headers(Authorization = paste("Bearer", token)))
    files <- content(bundle_response)$files
    nc_file_url <- files[[which(sapply(files, function(f) grepl("\\.nc$", f$file_name)))]]$url

    # Download the file
    GET(nc_file_url, write_disk(out_file, overwrite = TRUE),
        add_headers(Authorization = paste("Bearer", token)))

    message("Download complete: ", out_file)
  }


}#end fx



