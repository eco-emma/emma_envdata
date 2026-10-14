# =============================================================================
# GSOD weather + stations → eco-emma/emma_envdata@weather_data
#
# Contract (plan §0.1 / §0.2):
#   Inputs:  protected_areas.gpkg from static_data (dissolved parks; EPSG:9221)
#   Harvest: SOUTH AFRICA stations with recent END year; within 100 km of parks;
#            GSOD years = last 5 calendar years (override via WEATHER_MIN_YEAR)
#   Outputs (tag weather_data):
#     weather.parquet — STNID, YEARMODA, TEMP (°C), PRCP (mm), NAME
#     stations.gpkg   — STNID, NAME, BEGIN, END, start_year, end_year, LON, LAT,
#                       geometry (WGS84)
#
# First publish: CCR (`Rscript R/publish_weather.R`). Dedicated GHA workflow
# publish-weather is workflow_dispatch only — never stacked with AppEEARS.
# =============================================================================

#' Default weather release tag
#' @keywords internal
.weather_release_tag <- function() {
  "weather_data"
}

#' Last-N calendar years window for GSOD harvest
#'
#' Default is five calendar years including the current year
#' (e.g. 2022–2026 when run in 2026). Override with env `WEATHER_MIN_YEAR`.
#'
#' @return Integer start year.
#' @keywords internal
.weather_min_year <- function() {
  env <- Sys.getenv("WEATHER_MIN_YEAR", unset = "")
  if (nzchar(env)) {
    return(as.integer(env))
  }
  as.integer(lubridate::year(Sys.Date()) - 4L)
}

#' Download one flat release asset by name
#'
#' Public URL first; authenticated API download on failure.
#'
#' @param file Asset basename (no path separators).
#' @param dest_dir Local directory.
#' @param repo Owner/repo.
#' @param tag Release tag.
#' @param overwrite Re-download when present?
#' @param token Optional GitHub token.
#' @return Absolute path to the downloaded file.
#' @export
download_weather_release_asset <- function(
    file,
    dest_dir,
    repo = "eco-emma/emma_envdata",
    tag = "static_data",
    overwrite = FALSE,
    token = NULL
) {
  if (grepl("[/\\\\]", file)) {
    stop(
      "Release assets must be flat names (no nested paths). Got: ", file,
      call. = FALSE
    )
  }
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(dest_dir, file)
  if (file.exists(dest) && !overwrite && file.size(dest) > 0) {
    return(normalizePath(dest, winslash = "/", mustWork = TRUE))
  }

  public_url <- sprintf(
    "https://github.com/%s/releases/download/%s/%s",
    repo, tag, utils::URLencode(file, reserved = TRUE)
  )
  ok <- tryCatch({
    utils::download.file(public_url, destfile = dest, mode = "wb", quiet = TRUE)
    file.exists(dest) && file.size(dest) > 0
  }, error = function(e) FALSE)

  if (!ok) {
    if (is.null(token) || !nzchar(token)) {
      token <- Sys.getenv(
        "GITHUB_PAT",
        unset = Sys.getenv("GITHUB_TOKEN", unset = "")
      )
    }
    if (!nzchar(token) && exists(".gh_token", mode = "function")) {
      token <- tryCatch(.gh_token(), error = function(e) "")
    }
    parts <- strsplit(repo, "/", fixed = TRUE)[[1]]
    rel <- gh::gh(
      "GET /repos/{owner}/{repo}/releases/tags/{tag}",
      owner = parts[1], repo = parts[2], tag = tag,
      .token = if (nzchar(token)) token else NULL
    )
    asset <- Filter(function(a) identical(a$name, file), rel$assets)
    if (length(asset) == 0L) {
      stop("Asset '", file, "' not found on ", repo, "@", tag, call. = FALSE)
    }
    headers <- c(Accept = "application/octet-stream")
    if (nzchar(token)) {
      headers <- c(headers, Authorization = paste("token", token))
    }
    resp <- httr::GET(
      asset[[1]]$url,
      httr::add_headers(.headers = headers),
      httr::write_disk(dest, overwrite = TRUE)
    )
    if (httr::http_error(resp) || !file.exists(dest) || file.size(dest) < 1) {
      stop(
        "Failed to download '", file, "' from ", repo, "@", tag,
        call. = FALSE
      )
    }
  }

  normalizePath(dest, winslash = "/", mustWork = TRUE)
}

#' Resolve parks polygon path for the 100 km station filter
#'
#' Preference order: `WEATHER_PARKS_GPKG` env → local `parks_gpkg` → download
#' `protected_areas.gpkg` from `static_data`.
#'
#' @param parks_gpkg Optional local path.
#' @param work_dir Download directory when fetching from release.
#' @param repo Owner/repo for release download.
#' @param static_tag Tag hosting `protected_areas.gpkg`.
#' @param overwrite Re-download when present?
#' @return Absolute path to a parks GeoPackage.
#' @export
resolve_weather_parks_gpkg <- function(
    parks_gpkg = NULL,
    work_dir = "data/temp/weather",
    repo = "eco-emma/emma_envdata",
    static_tag = "static_data",
    overwrite = FALSE
) {
  env_path <- Sys.getenv("WEATHER_PARKS_GPKG", unset = "")
  if (nzchar(env_path)) {
    if (!file.exists(env_path)) {
      stop("WEATHER_PARKS_GPKG does not exist: ", env_path, call. = FALSE)
    }
    return(normalizePath(env_path, winslash = "/", mustWork = TRUE))
  }

  if (!is.null(parks_gpkg) && nzchar(parks_gpkg)) {
    if (!file.exists(parks_gpkg)) {
      stop("parks_gpkg does not exist: ", parks_gpkg, call. = FALSE)
    }
    return(normalizePath(parks_gpkg, winslash = "/", mustWork = TRUE))
  }

  message(
    "Downloading protected_areas.gpkg from ", repo, "@", static_tag,
    " (requires parks Phase B / CCR prime) ..."
  )
  download_weather_release_asset(
    file = "protected_areas.gpkg",
    dest_dir = work_dir,
    repo = repo,
    tag = static_tag,
    overwrite = overwrite
  )
}

#' Load NOAA ISD history (fresh CSV preferred; GSODR packaged fallback)
#'
#' Does **not** write into the GSODR package library (often read-only on CCR /
#' containers). Fresh CSV rows use FIPS `CTRY == "SF"` for South Africa.
#'
#' @param work_dir Directory for a temporary CSV download.
#' @return A tibble with at least STNID, NAME, LAT, LON, BEGIN, END,
#'   COUNTRY_NAME.
#' @keywords internal
.load_isd_history <- function(work_dir = "data/temp/weather") {
  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- file.path(work_dir, "isd-history.csv")
  station_url <- "https://www1.ncdc.noaa.gov/pub/data/noaa/isd-history.csv"

  freshened <- FALSE
  tryCatch({
    utils::download.file(station_url, destfile = csv_path, mode = "wb", quiet = TRUE)
    if (file.exists(csv_path) && file.size(csv_path) > 0) {
      freshened <- TRUE
    }
  }, error = function(e) {
    warning(
      "Could not refresh NOAA isd-history.csv; using GSODR packaged list. ",
      conditionMessage(e),
      call. = FALSE
    )
  })

  if (isTRUE(freshened)) {
    raw <- utils::read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE)
    names(raw) <- toupper(gsub(" ", "_", names(raw), fixed = TRUE))
    # NOAA columns: USAF, WBAN, STATION_NAME, CTRY, LAT, LON, BEGIN, END, ...
    if ("STATION_NAME" %in% names(raw)) {
      raw$NAME <- raw$STATION_NAME
    }
    if (!"NAME" %in% names(raw)) {
      stop("isd-history.csv missing station name column", call. = FALSE)
    }
    isd <- raw |>
      dplyr::mutate(
        WBAN = sprintf("%05d", as.integer(.data$WBAN)),
        USAF = as.character(.data$USAF),
        STNID = paste(.data$USAF, .data$WBAN, sep = "-"),
        BEGIN = as.character(.data$BEGIN),
        END = as.character(.data$END),
        COUNTRY_NAME = dplyr::if_else(
          .data$CTRY == "SF", "SOUTH AFRICA", as.character(.data$CTRY)
        )
      ) |>
      dplyr::filter(
        !is.na(.data$LAT), !is.na(.data$LON),
        .data$LAT != 0, .data$LON != 0,
        .data$LAT > -90, .data$LAT < 90,
        .data$LON > -180, .data$LON < 180
      ) |>
      dplyr::select(
        "STNID", "NAME", "LAT", "LON", "BEGIN", "END", "CTRY", "COUNTRY_NAME"
      )
    return(tibble::as_tibble(isd))
  }

  message("Proceeding with packaged GSODR isd_history.rda")
  env <- new.env(parent = emptyenv())
  load(system.file("extdata", "isd_history.rda", package = "GSODR"), envir = env)
  tibble::as_tibble(env$isd_history)
}

#' Select South Africa GSOD stations within 100 km of dissolved parks
#'
#' Ecological rule (plan §0.1): COUNTRY SOUTH AFRICA; END year ≥ previous
#' calendar year; within `st_buffer(parks, dist = 100000)` then spatial filter.
#'
#' @param parks_sf sf parks (any projected CRS with metre units preferred).
#' @param work_dir Temp dir for ISD refresh.
#' @return sf stations in WGS84 with start_year / end_year columns.
#' @export
get_weather_stations <- function(parks_sf, work_dir = "data/temp/weather") {
  isd_history <- .load_isd_history(work_dir = work_dir)

  prev_year <- as.integer(lubridate::year(Sys.Date()) - 1L)

  stations <- isd_history |>
    dplyr::filter(.data$COUNTRY_NAME == "SOUTH AFRICA") |>
    tidyr::separate(
      col = "END",
      into = c("end_year", "end_month", "end_day"),
      sep = c(4, 6, 8),
      remove = FALSE
    ) |>
    tidyr::separate(
      col = "BEGIN",
      into = c("start_year", "start_month", "start_day"),
      sep = c(4, 6, 8),
      remove = FALSE
    ) |>
    dplyr::mutate(
      start_year = as.integer(.data$start_year),
      end_year = as.integer(.data$end_year)
    ) |>
    dplyr::filter(.data$end_year >= prev_year)

  stations_sf <- sf::st_as_sf(
    stations,
    coords = c("LON", "LAT"),
    remove = FALSE,
    crs = "WGS84"
  )

  # 100 km buffer needs a projected CRS with metre units (parks SoT = EPSG:9221).
  parks_proj <- sf::st_make_valid(parks_sf)
  if (isTRUE(sf::st_is_longlat(parks_proj))) {
    parks_proj <- sf::st_transform(parks_proj, 9221)
  }
  parks_buf <- parks_proj |>
    sf::st_buffer(dist = 100000) |>
    sf::st_union() |>
    sf::st_transform(sf::st_crs(stations_sf))

  stations_sf |>
    sf::st_filter(parks_buf) |>
    sf::st_make_valid()
}

#' Robust GSOD download with year-window adjustment
#'
#' @param years Integer vector of years.
#' @param station GSOD STNID.
#' @param max_attempts Retry budget.
#' @param sleep_time Seconds between attempts.
#' @return data.frame/data.table of GSOD rows, or an error object / NULL.
#' @export
robust_get_GSOD <- function(
    years,
    station,
    max_attempts = 10L,
    sleep_time = 1
) {
  years <- sort(unique(as.integer(years)))
  years <- years[!is.na(years)]
  if (!length(years)) {
    return(NULL)
  }

  n_attempts <- 1L
  out_data <- NULL

  while (n_attempts <= max_attempts) {
    message(
      "attempt ", n_attempts, " of ", max_attempts,
      " to download GSOD data for station ", station,
      " years ", min(years), "-", max(years)
    )

    out_data <- tryCatch(
      GSODR::get_GSOD(years = years, station = station),
      error = function(e) e
    )

    if (inherits(out_data, c("data.table", "data.frame"))) {
      if (nrow(out_data) > 0) {
        return(out_data)
      }
      message("Empty dataframe downloaded, retrying")
    }

    # Permanent year-window mismatch: adjust once instead of burning retries.
    # GSODR: "This station, …, only provides data for years 2024 to 2024."
    if (inherits(out_data, "error")) {
      msg <- conditionMessage(out_data)
      m <- regexec("years ([0-9]{4}) to ([0-9]{4})", msg)
      r <- regmatches(msg, m)[[1]]
      if (length(r) == 3L) {
        avail <- as.integer(r[2]):as.integer(r[3])
        new_years <- intersect(years, avail)
        if (!length(new_years)) {
          message(
            "No overlapping GSOD years for station ", station,
            " (available ", min(avail), "-", max(avail), "); skipping"
          )
          return(out_data)
        }
        if (!identical(new_years, years)) {
          message(
            "Adjusting GSOD years for station ", station, " to ",
            min(new_years), "-", max(new_years)
          )
          years <- new_years
          n_attempts <- n_attempts + 1L
          next
        }
      }
    }

    if (n_attempts == max_attempts) {
      message(
        "Reached maximum download attempts for station ", station,
        ", giving up."
      )
    }

    n_attempts <- n_attempts + 1L
    Sys.sleep(sleep_time)
  }

  out_data
}

#' Download GSOD for selected stations and bind to one tibble
#'
#' Default year window is the last five calendar years (plan E3 assignment).
#'
#' @param stations sf from \code{get_weather_stations()}.
#' @param work_dir Per-station parquet scratch directory.
#' @param min_year First year to request (default \code{.weather_min_year()}).
#' @param max_attempts Passed to \code{robust_get_GSOD()}.
#' @param sleep_time Passed to \code{robust_get_GSOD()}.
#' @return Tibble with at least STNID, YEARMODA, TEMP, PRCP, NAME.
#' @export
harvest_gsod_weather <- function(
    stations,
    work_dir = "data/temp/weather/gsod",
    min_year = .weather_min_year(),
    max_attempts = 10L,
    sleep_time = 1
) {
  if (identical(Sys.getenv("EMMA_CI_LIGHT"), "1")) {
    message("EMMA_CI_LIGHT=1: skipping GSOD station downloads; empty weather")
    return(tibble::tibble(
      STNID = character(),
      YEARMODA = as.Date(character()),
      TEMP = numeric(),
      PRCP = numeric(),
      NAME = character()
    ))
  }

  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
  # Clear prior per-station shards so a partial re-run cannot mix years.
  old <- list.files(work_dir, pattern = "^gsod_.*\\.parquet$", full.names = TRUE)
  if (length(old)) {
    unlink(old)
  }

  this_year <- as.integer(lubridate::year(Sys.Date()))
  min_year <- as.integer(min_year)
  message(
    "Harvesting GSOD for ", nrow(stations), " stations, years ",
    min_year, "-", this_year
  )

  # Stateful network download with per-station side effects — loop is intentional.
  for (i in seq_len(nrow(stations))) {
    station_i <- stations$STNID[[i]]
    message(
      "Downloading data for ", station_i, ": station ", i,
      " of ", nrow(stations)
    )

    yr_start <- max(as.integer(stations$start_year[[i]]), min_year, na.rm = TRUE)
    if (is.na(yr_start) || yr_start > this_year) {
      message(
        "Skipping station ", station_i, ": no years in [",
        min_year, ", ", this_year, "]"
      )
      next
    }

    data_i <- robust_get_GSOD(
      years = yr_start:this_year,
      station = station_i,
      max_attempts = max_attempts,
      sleep_time = sleep_time
    )

    if (!inherits(data_i, "data.frame") || nrow(data_i) < 1) {
      next
    }

    keep <- intersect(
      c("STNID", "YEARMODA", "TEMP", "PRCP", "NAME"),
      names(data_i)
    )
    arrow::write_parquet(
      as.data.frame(data_i)[, keep, drop = FALSE],
      sink = file.path(
        work_dir,
        paste0("gsod_", gsub("[^A-Za-z0-9_-]", "_", station_i), ".parquet")
      ),
      compression = "gzip"
    )
  }

  gsod_files <- list.files(
    work_dir,
    pattern = "^gsod_.*\\.parquet$",
    full.names = TRUE
  )
  if (!length(gsod_files)) {
    warning("No GSOD parquet files downloaded; returning empty weather tibble")
    return(tibble::tibble(
      STNID = character(),
      YEARMODA = as.Date(character()),
      TEMP = numeric(),
      PRCP = numeric(),
      NAME = character()
    ))
  }

  weather <- arrow::open_dataset(gsod_files) |>
    dplyr::collect()

  # Ensure contract columns exist even if a station shard omitted NAME.
  needed <- c("STNID", "YEARMODA", "TEMP", "PRCP", "NAME")
  for (col in setdiff(needed, names(weather))) {
    weather[[col]] <- NA
  }
  weather <- weather[, needed, drop = FALSE]
  gc()
  tibble::as_tibble(weather)
}

#' Write stations.gpkg (WGS84) for the weather_data release
#'
#' @param stations sf from \code{get_weather_stations()}.
#' @param out_file Destination GeoPackage path.
#' @return Absolute path to \code{out_file}.
#' @export
write_stations_gpkg <- function(
    stations,
    out_file = "data/target_outputs/stations.gpkg"
) {
  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  out_stations <- sf::st_transform(stations, 4326)
  keep_cols <- intersect(
    c("STNID", "NAME", "BEGIN", "END", "start_year", "end_year", "LON", "LAT"),
    names(out_stations)
  )
  out_stations <- out_stations[, keep_cols]

  if (file.exists(out_file)) {
    unlink(out_file)
  }
  sf::st_write(out_stations, dsn = out_file, delete_dsn = TRUE, quiet = TRUE)
  normalizePath(out_file, winslash = "/", mustWork = TRUE)
}

#' Write weather.parquet for the weather_data release
#'
#' @param weather Tibble from \code{harvest_gsod_weather()}.
#' @param out_file Destination parquet path.
#' @return Absolute path to \code{out_file}.
#' @export
write_weather_parquet <- function(
    weather,
    out_file = "data/target_outputs/weather.parquet"
) {
  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  needed <- c("STNID", "YEARMODA", "TEMP", "PRCP", "NAME")
  for (col in setdiff(needed, names(weather))) {
    weather[[col]] <- NA
  }
  arrow::write_parquet(
    weather[, needed, drop = FALSE],
    sink = out_file,
    compression = "gzip"
  )
  normalizePath(out_file, winslash = "/", mustWork = TRUE)
}

#' Build weather.parquet + stations.gpkg (no upload)
#'
#' @param out_dir Product output directory.
#' @param work_dir Scratch directory.
#' @param parks_gpkg Optional local parks path; else download from static_data.
#' @param repo Owner/repo.
#' @param static_tag Tag for protected_areas.gpkg.
#' @param min_year First GSOD year (default last 5 calendar years).
#' @param overwrite_inputs Re-download parks gpkg?
#' @param verbose Progress messages?
#' @return Named character vector of product paths.
#' @export
build_weather_products <- function(
    out_dir = "data/target_outputs",
    work_dir = "data/temp/weather",
    parks_gpkg = NULL,
    repo = "eco-emma/emma_envdata",
    static_tag = "static_data",
    min_year = .weather_min_year(),
    overwrite_inputs = FALSE,
    verbose = TRUE
) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)

  parks_path <- resolve_weather_parks_gpkg(
    parks_gpkg = parks_gpkg,
    work_dir = work_dir,
    repo = repo,
    static_tag = static_tag,
    overwrite = overwrite_inputs
  )
  if (verbose) {
    message("Using parks: ", parks_path)
  }

  parks_sf <- sf::st_read(parks_path, quiet = TRUE)
  if (nrow(parks_sf) < 1) {
    stop("protected_areas.gpkg has zero features: ", parks_path, call. = FALSE)
  }

  if (verbose) {
    message("Selecting stations (SOUTH AFRICA, recent END, 100 km of parks) ...")
  }
  stations <- get_weather_stations(parks_sf = parks_sf, work_dir = work_dir)
  if (verbose) {
    message("Selected ", nrow(stations), " stations")
  }
  if (nrow(stations) < 1) {
    stop(
      "No stations within 100 km of parks; check protected_areas.gpkg",
      call. = FALSE
    )
  }

  if (verbose) {
    message("Harvesting GSOD (min_year=", min_year, ") ...")
  }
  weather <- harvest_gsod_weather(
    stations = stations,
    work_dir = file.path(work_dir, "gsod"),
    min_year = min_year
  )
  if (verbose) {
    message("Weather rows: ", nrow(weather))
  }

  stations_out <- write_stations_gpkg(
    stations,
    out_file = file.path(out_dir, "stations.gpkg")
  )
  weather_out <- write_weather_parquet(
    weather,
    out_file = file.path(out_dir, "weather.parquet")
  )

  c(weather = weather_out, stations = stations_out)
}

#' Build weather products and optionally upload to `weather_data`
#'
#' Prefer CCR for the first publish. The same function is GHA-capable via
#' workflow_dispatch (`publish-weather`).
#'
#' @param upload Upload via \code{upload_to_github_release()}?
#' @param weather_tag Release tag (default `weather_data`).
#' @param ... Passed to \code{build_weather_products()}.
#' @return Named character vector of product paths.
#' @export
publish_weather_products <- function(
    out_dir = "data/target_outputs",
    work_dir = "data/temp/weather",
    parks_gpkg = NULL,
    repo = "eco-emma/emma_envdata",
    static_tag = "static_data",
    weather_tag = .weather_release_tag(),
    min_year = .weather_min_year(),
    upload = TRUE,
    overwrite_inputs = FALSE,
    verbose = TRUE
) {
  files <- build_weather_products(
    out_dir = out_dir,
    work_dir = work_dir,
    parks_gpkg = parks_gpkg,
    repo = repo,
    static_tag = static_tag,
    min_year = min_year,
    overwrite_inputs = overwrite_inputs,
    verbose = verbose
  )

  if (isTRUE(upload)) {
    if (verbose) {
      message(
        "Uploading weather products to ", repo, "@", weather_tag,
        " (overwrite if checksum changed) ..."
      )
    }
    upload_to_github_release(
      files = unname(files),
      repo = repo,
      release_tag = weather_tag,
      release_name = "Weather (GSOD) + stations",
      overwrite = TRUE,
      verbose = verbose
    )
  }

  files
}
