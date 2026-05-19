#' @title Upload files to GitHub release
#' @description Creates/updates a GitHub release with specified files.
#' Skips files that already exist in the release.
#' @param files Character vector of file paths to upload
#' @param repo Repository in format "owner/repo"
#' @param release_tag Release tag (e.g., "static_current", "data_modis_vi_current")
#' @param release_name Human-readable release name (e.g., "Static Data - Current")
#' @param verbose Logical for messages
#' @return Character vector of uploaded file paths (invisibly)
#' @details
#' Requires piggyback package and GITHUB_TOKEN environment variable.
#' Uses piggyback::pb_upload() which requires gh CLI or authentication.
#' @export
upload_to_github_release <- function(
  files,
  repo,
  release_tag,
  release_name = release_tag,
  verbose = TRUE,
  overwrite = FALSE,
  ...  #include to allow for targets dependencies without affecting function behavior
) {
  
  
  # Handle NA or empty inputs
  if (length(files) == 0 || all(is.na(files))) {
    if (verbose) message("No files to upload")
    return(invisible(character(0)))
  }
  
  # Remove NA values
  files <- files[!is.na(files)]

  
  if (length(files) == 0) {
    if (verbose) message("No files to upload (all were NA)")
    return(invisible(character(0)))
  }
  
  # Check for GitHub token (GITHUB_PAT preferred, GITHUB_TOKEN as fallback, then gh CLI)
  token <- Sys.getenv("GITHUB_PAT")
  if (token == "") token <- Sys.getenv("GITHUB_TOKEN")
  if (token == "") {
    token <- tryCatch(
      trimws(system("gh auth token", intern = TRUE, ignore.stderr = TRUE)[[1]]),
      error = function(e) ""
    )
    if (!is.na(token) && nchar(token) > 0) {
      if (verbose) message("Using GitHub token from 'gh auth token'")
    } else {
      token <- ""
      warning("No GitHub token found (GITHUB_PAT, GITHUB_TOKEN, or gh CLI). Upload will likely fail.")
    }
  }


  # Filter to files that exist
  files <- files[file.exists(files)]
  if (length(files) == 0) {
    message("No files found to upload")
    return(invisible(character(0)))
  }
  

  # Ensure release exists (create it if needed)
  tryCatch({
    piggyback::pb_new_release(
      repo = repo,
      tag = release_tag,
      .token = token
    )
    if (verbose) message("\u2713 Created release '", release_tag, "'")
  }, warning = function(w) {
    # "already exists" warning from piggyback — release is present, which is fine
    if (verbose) message("Using existing release '", release_tag, "'")
  }, error = function(e) {
    if (verbose) message("Using existing release '", release_tag, "'")
  })
  

  

  # List existing files in release
  # pb_list returns NULL if empty (not an error) or a dataframe if files exist
  existing <- tryCatch({
    piggyback::pb_list(
      repo = repo,
      tag = release_tag,
      .token = token
    )
  }, error = function(e) {
    if (verbose) warning("Unable to list files in release: ", e$message)
    data.frame()
  })
  existing_names <- if (!is.null(existing) && nrow(existing) > 0) existing$file_name else character(0)

  # Deduplicate files (branched targets may return same path from multiple branches)
  files <- files[!duplicated(basename(files))]

  # Filter to files that don't already exist (unless overwrite = TRUE)
  if (overwrite) {
    files_to_upload <- files
  } else {
    files_to_upload <- files[basename(files) %not_in% existing_names]
  }

  if (length(files_to_upload) == 0) {
    if (verbose) message("All files already in release '", release_tag, "'")
    return(invisible(character(0)))
  }
  
  if (verbose) {
    message("Uploading ", length(files_to_upload), " files to release '", release_tag, "'")
  }
  
  # Upload each file
  uploaded <- character(0)
  for (file in files_to_upload) {
    if (!file.exists(file)) {
      warning("File not found: ", file)
      next
    }
    
    if (verbose) message("  Uploading: ", basename(file))
    
    tryCatch({
      piggyback::pb_upload(
        file = file,
        repo = repo,
        tag = release_tag,
        .token = token,
        overwrite = overwrite,
        show_progress = verbose
      )
      
      uploaded <- c(uploaded, file)
      if (verbose) message("    ✓ Uploaded")
    }, error = function(e) {
      warning("Failed to upload: ", basename(file), " - ", e$message)
    })
  }
  
 
  # Verify uploaded files are now in the release (retry up to 5x to allow GitHub API indexing)
  if (length(uploaded) > 0) {
    if (verbose) message("Verifying uploaded files in release...")

    uploaded_names <- basename(uploaded)
    verified <- FALSE
    release_files <- NULL
    for (attempt in seq_len(10)) {
      Sys.sleep(attempt * 5)  # 5s, 10s, 15s, ... 50s  (total ≤ 275s)
      release_files <- tryCatch(
        piggyback::pb_list(repo = repo, tag = release_tag, .token = token),
        error = function(e) NULL
      )
      if (!is.null(release_files) && nrow(release_files) > 0 &&
          all(uploaded_names %in% release_files$file_name)) {
        verified <- TRUE
        break
      }
      if (verbose) message("  Attempt ", attempt, "/10: not all files visible yet, retrying...")
    }

    if (verified) {
      if (verbose) message("\u2713 Verified: All ", length(uploaded), " files confirmed in release")
    } else {
      existing_in_release <- if (!is.null(release_files) && nrow(release_files) > 0)
        release_files$file_name else character(0)
      not_found <- uploaded_names[!uploaded_names %in% existing_in_release]
      warning("Verification incomplete after 5 attempts: ", length(not_found),
              " file(s) not confirmed in release: ", paste(not_found, collapse = ", "),
              "\nFiles may still be available after GitHub finishes indexing.")
    }
  }
  
  invisible(uploaded)
}

#' Helper operator
#' @keywords internal
`%not_in%` <- Negate(`%in%`)
