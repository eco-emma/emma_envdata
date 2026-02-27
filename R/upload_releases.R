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
  
  # Check for GITHUB_TOKEN
  token <- Sys.getenv("GITHUB_TOKEN")
  if (token == "") {
    message("GITHUB_TOKEN environment variable not set. Upload may fail.")
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
    if (verbose) message("✓ Created release '", release_tag, "'")
  }, error = function(e) {
    # Release likely already exists, which is fine
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
  existing_names <- ifelse(nrow(existing) > 0, existing$file_name, character(0))

  # Filter to files that don't already exist
  files_to_upload <- files[basename(files) %not_in% existing_names]
  
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
        show_progress = verbose
      )
      
      uploaded <- c(uploaded, file)
      if (verbose) message("    ✓ Uploaded")
    }, error = function(e) {
      warning("Failed to upload: ", basename(file), " - ", e$message)
    })
  }
  
 
  # Verify uploaded files are now in the release
  if (length(uploaded) > 0) {
    if (verbose) message("Verifying uploaded files in release...")
    
    Sys.sleep(1)  # Brief pause to ensure files are indexed
    
    tryCatch({
      release_files <- piggyback::pb_list(
        repo = repo,
        tag = release_tag,
        .token = token
      )
      
      uploaded_names <- basename(uploaded)
      if (!is.null(release_files) && nrow(release_files) > 0) {
        verified <- uploaded_names %in% release_files$file_name
        
        if (all(verified)) {
          if (verbose) message("✓ Verified: All ", length(uploaded), " files confirmed in release")
        } else {
          not_found <- uploaded_names[!verified]
          stop("Verification failed: ", length(not_found), " file(s) not found in release: ",
               paste(not_found, collapse = ", "))
        }
      } else {
        stop("Verification failed: Could not list files in release after upload")
      }
    }, error = function(e) {
      stop("Could not verify uploads: ", e$message)
    })
  }
  
  invisible(uploaded)
}

#' Helper operator
#' @keywords internal
`%not_in%` <- Negate(`%in%`)
