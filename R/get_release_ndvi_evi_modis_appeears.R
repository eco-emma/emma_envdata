#' @title Download MODIS NDVI and EVI via AppEEARS and publish monthly NetCDF
#' @description Submits an AppEEARS area request for MOD13A1.061 NDVI, EVI, and QA
#' over the provided domain and date range, downloads NetCDF outputs, splits to 
#' monthly NetCDF files, and uploads them to GitHub Releases.
#' @author EMMA Team
#' @param temp_directory Temporary working directory for downloads and intermediate files.
#' @param tag Release tag to upload monthly NetCDFs to (e.g., "raw_ndvi_evi_modis_nc").
#' @param domain An `sf` polygon defining the area of interest.
#' @param sleep_time Seconds to sleep between uploads to avoid rate limiting.
#' @param start_date Optional ISO date (YYYY-MM-DD). If NULL, inferred from existing releases.
#' @param end_date Optional ISO date (YYYY-MM-DD). Defaults to `Sys.Date()`.
#' @param earthdata_user NASA Earthdata username. Defaults to `Sys.getenv("EARTHDATA_USER")`.
#' @param earthdata_password NASA Earthdata password. Defaults to `Sys.getenv("EARTHDATA_PASSWORD")`.
#' @param max_layers Maximum number of monthly files to process in one run. NULL for all.
#' @param verbose Logical for progress messages.
#' @return Character string of the latest YYYY-MM successfully uploaded, or NULL if nothing new.
get_release_ndvi_evi_modis_appeears <- function(
  temp_directory = "data/temp/raw_data/ndvi_evi_modis/",
  tag = "raw_ndvi_evi_modis_nc",
  domain,
  sleep_time = 1,
  start_date = NULL,
  end_date = as.character(Sys.Date()),
  earthdata_user = Sys.getenv("EARTHDATA_USER"),
  earthdata_password = Sys.getenv("EARTHDATA_PASSWORD"),
  max_layers = NULL,
  verbose = TRUE
) {

  # Package checks
  required_pkgs <- c("appeears", "terra", "sf", "piggyback", "lubridate", "jsonlite", "dplyr")
  missing <- required_pkgs[!sapply(required_pkgs, requireNamespace, quietly = TRUE)]
  if (length(missing)) {
    stop("Required packages missing: ", paste(missing, collapse = ", "))
  }

  if (earthdata_user == "") {
    stop("EARTHDATA_USER not found. Set EARTHDATA_USER env var and configure ~/.netrc with password.")
  }

  # Ensure clean temp directory
  if (dir.exists(temp_directory)) {
    unlink(temp_directory, recursive = TRUE, force = TRUE)
  }
  dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)

  # Ensure release exists
  tryCatch(
    piggyback::pb_new_release(repo = "AdamWilsonLab/emma_envdata", tag = tag),
    error = function(e) {
      if (verbose) message("Release ", tag, " already exists")
    }
  )

  # Determine start_date from existing release assets
  released_files <- piggyback::pb_list(repo = "AdamWilsonLab/emma_envdata")
  existing_nc <- released_files[released_files$tag == tag & grepl("\\.nc$", released_files$file_name), , drop = FALSE]

  parse_month_from_name <- function(x) {
    m <- sub(".*([0-9]{4}-[0-9]{2})\\.nc$", "\\1", x)
    if (grepl("^[0-9]{4}-[0-9]{2}$", m)) return(m) else return(NA_character_)
  }

  if (is.null(start_date)) {
    months_done <- vapply(existing_nc$file_name, parse_month_from_name, character(1))
    months_done <- months_done[!is.na(months_done)]
    if (length(months_done) == 0) {
      start_date <- "2000-02-18" # MODIS Terra start
    } else {
      last_month <- max(months_done)
      start_date <- as.character(lubridate::ceiling_date(as.Date(paste0(last_month, "-01")), unit = "month"))
    }
  }

  if (verbose) message("AppEEARS NDVI+EVI request from ", start_date, " to ", end_date)

  # Authentication via ~/.netrc (automatically used by appeears package)
  if (verbose) message("Using EARTHDATA_USER: ", earthdata_user)

  # Ensure domain is in WGS84
  dom <- domain
  if (!sf::st_is_longlat(dom)) {
    if (is.na(sf::st_crs(dom))) stop("'domain' must have a valid CRS.")
    dom <- sf::st_transform(dom, 4326)
  }
  aoi_path <- file.path(temp_directory, "aoi.geojson")
  suppressWarnings(sf::st_write(dom, aoi_path, driver = "GeoJSON", delete_dsn = TRUE, quiet = TRUE))
  aoi_json <- jsonlite::read_json(aoi_path, simplifyVector = FALSE)

  # Resolve layer names dynamically (include composite Day of Year for exact acquisition date)
  ndvi_layer <- "500m_16_days_NDVI"
  evi_layer <- "500m_16_days_EVI"
  qa_layer <- "500m_16_days_VI_Quality"
  doy_layer <- "Day_of_Year_1km"
  
  try({
    lyr <- appeears::rs_layers("MOD13A1.061")
    cand_cols <- intersect(c("Layer", "Name", "layer", "name"), names(lyr))
    if (length(cand_cols)) {
      vals <- unlist(lapply(cand_cols, function(cc) lyr[[cc]]))
      ndvi_cand <- vals[grepl("NDVI", vals, ignore.case = TRUE)][1]
      evi_cand <- vals[grepl("EVI", vals, ignore.case = TRUE)][1]
      qa_cand <- vals[grepl("VI.*Quality|Quality", vals, ignore.case = TRUE)][1]
      doy_cand <- vals[grepl("Day[_ ]?of[_ ]?Year|composite.*day", vals, ignore.case = TRUE)][1]
      if (!is.na(ndvi_cand)) ndvi_layer <- ndvi_cand
      if (!is.na(evi_cand)) evi_layer <- evi_cand
      if (!is.na(qa_cand)) qa_layer <- qa_cand
      if (!is.na(doy_cand)) doy_layer <- doy_cand
    }
  }, silent = TRUE)

  if (verbose) message("Using layers: ", ndvi_layer, ", ", evi_layer, ", ", qa_layer, ", ", doy_layer)

  # Build request payload - NDVI, EVI, and QA in one request
  req <- list(
    task_type = "area",
    task_name = paste0("emma_ndvi_evi_", format(Sys.time(), "%Y%m%d%H%M%S")),
    params = list(
      dates = list(start = as.character(start_date), end = as.character(end_date)),
      layers = list(
        list(product = "MOD13A1.061", layer = ndvi_layer),
        list(product = "MOD13A1.061", layer = evi_layer),
        list(product = "MOD13A1.061", layer = qa_layer),
        list(product = "MOD13A1.061", layer = doy_layer)
      ),
      output = list(format = "netcdf4", projection = "native"),
      geo = aoi_json
    )
  )

  # Submit and poll
  task <- appeears::rs_request(request = req)
  if (verbose) message("Submitted AppEEARS task: ", task$task_id)

  repeat {
    st <- appeears::rs_status(task$task_id)
    if (isTRUE(tolower(st$status) %in% c("done", "complete", "completed"))) break
    if (isTRUE(tolower(st$status) %in% c("error", "failed"))) stop("AppEEARS task failed.")
    Sys.sleep(30)
    if (verbose) message("Waiting... status: ", st$status)
  }

  # Download and unzip
  dl_paths <- appeears::rs_download(task_id = task$task_id, path = temp_directory)
  zips <- list.files(temp_directory, pattern = "\\.zip$", full.names = TRUE, recursive = TRUE)
  if (length(zips)) {
    for (z in zips) utils::unzip(z, exdir = temp_directory)
  }

  # Collect NetCDFs
  nc_paths <- list.files(temp_directory, pattern = "\\.nc$", full.names = TRUE, recursive = TRUE)
  if (length(nc_paths) == 0) {
    if (verbose) message("No NetCDF files downloaded.")
    return(invisible(NULL))
  }

  # Split into monthly files
  write_monthly_netcdf <- function(nc_file, out_dir) {
    r <- terra::rast(nc_file)
    tt <- try(terra::time(r), silent = TRUE)
    if (inherits(tt, "try-error") || is.null(tt) || length(tt) == 0) {
      out <- file.path(out_dir, sprintf("ndvi_evi_MOD13A1_%s.nc", format(as.Date(end_date), "%Y-%m")))
      terra::writeCDF(r, filename = out, overwrite = TRUE)
      return(out)
    }
    months <- unique(format(as.Date(tt), "%Y-%m"))
    outs <- character(0)
    for (m in months) {
      idx <- which(format(as.Date(tt), "%Y-%m") == m)
      if (length(idx) == 0) next
      r_m <- r[[idx]]
      out <- file.path(out_dir, sprintf("ndvi_evi_MOD13A1_%s.nc", m))
      terra::writeCDF(r_m, filename = out, overwrite = TRUE)
      outs <- c(outs, out)
    }
    outs
  }

  monthly_files <- unique(unlist(lapply(nc_paths, write_monthly_netcdf, out_dir = temp_directory)))
  monthly_files <- monthly_files[file.exists(monthly_files)]
  if (length(monthly_files) == 0) {
    if (verbose) message("No monthly NetCDF files prepared.")
    return(invisible(NULL))
  }

  # Apply max_layers limit
  if (!is.null(max_layers) && length(monthly_files) > max_layers) {
    if (verbose) message("Limiting to ", max_layers, " files")
    monthly_files <- monthly_files[1:max_layers]
  }

  # Skip duplicates
  existing_names <- existing_nc$file_name
  to_upload <- monthly_files[!basename(monthly_files) %in% existing_names]
  if (length(to_upload) == 0) {
    if (verbose) message("Releases already up to date")
    latest <- vapply(existing_names, parse_month_from_name, character(1))
    return(invisible(max(latest[!is.na(latest)])))
  }

  # Upload
  for (f in to_upload) {
    Sys.sleep(sleep_time)
    piggyback::pb_upload(file = f, repo = "AdamWilsonLab/emma_envdata", tag = tag)
    if (verbose) message("Uploaded ", basename(f))
  }

  latest_month <- max(sub(".*([0-9]{4}-[0-9]{2})\\.nc$", "\\1", basename(to_upload)))
  unlink(temp_directory, recursive = TRUE, force = TRUE)
  invisible(latest_month)
}
