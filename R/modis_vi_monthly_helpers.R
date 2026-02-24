#' @title Generate 16-day window sequences for MODIS VI downloads
#' @description Creates a data frame of all 16-day windows to download based on a date range.
#' MODIS uses a fixed 16-day composite cycle starting from 2000-02-18.
#' @param start_date Start date (YYYY-MM-DD), default 2000-02-18 (MODIS Terra start)
#' @param end_date End date (YYYY-MM-DD), default today
#' @return Data frame with columns: window_start, window_end, date_str (YYYYMMDD format)
#' @export
generate_16day_sequence <- function(start_date = "2000-02-18", end_date = NULL) {
  if (is.null(end_date)) {
    end_date <- Sys.Date()
  }
  
  start_date <- as.Date(start_date)
  end_date <- as.Date(end_date)
  
  # Generate all 16-day window starts from MODIS Terra start date
  # MODIS composites are 16 days apart, fixed cycle
  window_starts <- seq(start_date, end_date, by = 16)
  window_ends <- window_starts + 15
  
  # Trim last window if it extends past end_date
  valid_idx <- window_starts <= end_date
  
  data.frame(
    window_start = window_starts[valid_idx],
    window_end = pmin(window_ends[valid_idx], end_date),
    date_str = format(window_starts[valid_idx], "%Y%m%d"),
    row.names = NULL
  )
}


#' @title Identify missing 16-day windows from output directory
#' @description Compares generated 16-day window sequence with existing output files
#' @param output_dir Directory containing 16-day window NetCDF files (format: modis_vi_YYYYMMDD_16d.nc)
#' @param start_date Start date for sequence (YYYY-MM-DD)
#' @param end_date End date for sequence (YYYY-MM-DD), default is today
#' @return Data frame of windows that haven't been downloaded yet
#' @export
identify_missing_windows <- function(output_dir, start_date = "2000-02-18", end_date = NULL) {
  
  # Create full 16-day window sequence
  all_windows <- generate_16day_sequence(start_date, end_date)
  
  # Check which ones already exist
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  existing_files <- list.files(output_dir, pattern = "^modis_vi_\\d{8}_16d\\.nc$")
  
  if (length(existing_files) == 0) {
    return(all_windows)
  }
  
  # Extract date_str from existing files
  existing_dates <- existing_files %>%
    gsub("^modis_vi_", "", .) %>%
    gsub("_16d\\.nc$", "", .)
  
  # Return only missing windows
  missing <- all_windows[!all_windows$date_str %in% existing_dates, ]
  
  if (nrow(missing) == 0) {
    message("All 16-day windows already exist in ", output_dir)
    return(data.frame())
  }
  
  missing
}



#' @title Create 16-day window index of MODIS VI files
#' @description Creates a parquet file mapping 16-day windows to their corresponding data files
#' @param output_dir Directory containing 16-day window NetCDF files
#' @param summary_file Path to output parquet summary file
#' @param verbose Logical for progress messages
#' @return Path to summary parquet file (invisibly)
#' @export
create_modis_vi_window_index <- function(output_dir, summary_file = NULL, verbose = TRUE) {
  
  files <- list.files(output_dir, pattern = "^modis_vi_\\d{8}_16d\\.nc$", full.names = TRUE)
  
  # Check for skip markers (windows with no data)
  skip_files <- list.files(output_dir, pattern = "^modis_vi_\\d{8}_16d\\.skip$", full.names = TRUE)
  if (verbose && length(skip_files) > 0) {
    message("Found ", length(skip_files), " skipped windows (no data available)")
  }
  
  if (length(files) == 0) {
    if (verbose) message("No 16-day MODIS VI files found in ", output_dir)
    file_info <- data.frame(
      file_name = character(0),
      date_str = character(0),
      file_path = character(0),
      file_size_mb = numeric(0),
      created_date = as.POSIXct(character(0)),
      window_date = as.Date(character(0))
    )
  } else {
    # Extract metadata
    file_info <- data.frame(
      file_name = basename(files),
      date_str = gsub("^modis_vi_|_16d\\.nc$", "", basename(files)),
      file_path = files,
      file_size_mb = file.size(files) / (1024^2),
      created_date = file.info(files)$mtime,
      stringsAsFactors = FALSE
    )
    
    # Parse date_str to date
    file_info$window_date <- as.Date(file_info$date_str, format = "%Y%m%d")
    
    # Sort by window date
    file_info <- file_info[order(file_info$window_date), ]
  }
  
  # Write parquet (even if empty) and return the path
  if (!is.null(summary_file)) {
    dir.create(dirname(summary_file), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(file_info, summary_file)
    if (verbose) message("Written 16-day window index to: ", summary_file, " (", nrow(file_info), " windows with data)")
    invisible(summary_file)
  } else {
    stop("summary_file must be provided")
  }
}

