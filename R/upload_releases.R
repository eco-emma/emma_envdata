#' @title List asset names in a GitHub release
#' @description Retrieves asset filenames for a release tag using the gh package
#'   directly (avoids piggyback API incompatibilities).
#' @param repo Repository in format "owner/repo"
#' @param release_tag Release tag string
#' @param token GitHub token
#' @return Character vector of asset file names, or character(0) on error
#' @keywords internal
.gh_release_asset_names <- function(repo, release_tag, token) {
  parts <- strsplit(repo, "/")[[1]]
  tryCatch({
    rel <- gh::gh(
      "GET /repos/{owner}/{repo}/releases/tags/{tag}",
      owner = parts[1], repo = parts[2], tag = release_tag,
      .token = token
    )
    if (length(rel$assets) == 0L) character(0)
    else vapply(rel$assets, function(a) a$name, character(1L))
  }, error = function(e) character(0))
}

#' @title Upload a single file to a GitHub release via the REST API
#' @description Posts a file to a release upload URL using httr, bypassing
#'   piggyback which has known column-selection errors against newer GitHub
#'   API response schemas.
#' @param file  Absolute or relative path to the file to upload
#' @param repo  Repository in format "owner/repo"
#' @param release_tag Release tag string
#' @param token GitHub token
#' @param overwrite Logical; delete existing asset before uploading?
#' @return Invisible TRUE on success, stops on HTTP error
#' @keywords internal
.gh_upload_release_asset <- function(file, repo, release_tag, token,
                                      overwrite = FALSE) {
  parts <- strsplit(repo, "/")[[1]]
  rel <- gh::gh(
    "GET /repos/{owner}/{repo}/releases/tags/{tag}",
    owner = parts[1], repo = parts[2], tag = release_tag,
    .token = token
  )

  # Optionally delete existing asset with the same name.
  # Wrap in tryCatch: if the DELETE fails (e.g., the token lacks write scope
  # for the org, which GitHub returns as 404 rather than 403), fall back to
  # `gh release upload --clobber` via the gh CLI which uses its own stored auth.
  if (overwrite && length(rel$assets) > 0L) {
    fname <- basename(file)
    asset_id_to_delete <- NULL
    for (asset in rel$assets) {
      if (identical(asset$name, fname)) {
        asset_id_to_delete <- asset$id
        break
      }
    }

    if (!is.null(asset_id_to_delete)) {
      delete_ok <- tryCatch({
        gh::gh(
          "DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}",
          owner = parts[1], repo = parts[2], asset_id = asset_id_to_delete,
          .token = token
        )
        TRUE
      }, error = function(e) {
        # DELETE failed (token may lack write scope; GitHub returns 404 for
        # unauthorized DELETE on public repos rather than 401/403).
        # Fall back to gh CLI --clobber which uses its own stored credentials.
        gh_bin <- Sys.which("gh")
        if (nzchar(gh_bin)) {
          exit_code <- system(
            paste(
              shQuote(gh_bin), "release", "upload", release_tag,
              shQuote(normalizePath(file, mustWork = FALSE)),
              "--repo", paste0(parts[1], "/", parts[2]),
              "--clobber"
            ),
            ignore.stdout = TRUE, ignore.stderr = FALSE
          )
          if (exit_code == 0L) {
            return("cli_uploaded")  # signal that gh CLI handled the upload
          }
        }
        stop("DELETE failed and gh CLI fallback unavailable: ", conditionMessage(e))
      })
      if (identical(delete_ok, "cli_uploaded")) return(invisible(TRUE))
    }

    # Re-fetch release so upload_url is fresh after any deletion
    rel <- gh::gh(
      "GET /repos/{owner}/{repo}/releases/tags/{tag}",
      owner = parts[1], repo = parts[2], tag = release_tag,
      .token = token
    )
  }

  upload_url <- sub("\\{\\?name,label\\}", "", rel$upload_url)
  resp <- httr::POST(
    url   = paste0(upload_url, "?name=", utils::URLencode(basename(file), reserved = TRUE)),
    httr::add_headers(Authorization = paste("token", token),
                      `Content-Type` = "application/octet-stream"),
    body    = httr::upload_file(file),
    httr::timeout(600)
  )
  httr::stop_for_status(resp)
  invisible(TRUE)
}

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
#' Requires gh and httr packages plus a GitHub token (GITHUB_PAT, GITHUB_TOKEN,
#' or gh CLI). Uses the GitHub REST API directly to avoid piggyback version
#' incompatibilities with newer GitHub API response schemas.
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
  

  # Ensure release exists (create it if needed) — use gh directly, not piggyback,
  # to avoid pb_new_release() API incompatibilities with newer GitHub response schemas.
  parts <- strsplit(repo, "/")[[1]]
  tryCatch({
    gh::gh(
      "POST /repos/{owner}/{repo}/releases",
      owner      = parts[1], repo = parts[2],
      tag_name   = release_tag,
      name       = release_name,
      prerelease = TRUE,
      .token     = token
    )
    if (verbose) message("\u2713 Created release '", release_tag, "'")
  }, error = function(e) {
    # Release already exists or commit doesn't exist yet — both are fine
    if (verbose) message("Using existing release '", release_tag, "'")
  })
  

  

  # List existing assets using gh package directly (piggyback pb_list has
  # incompatibilities with newer GitHub API response schemas).
  existing_names <- tryCatch({
    .gh_release_asset_names(repo, release_tag, token)
  }, error = function(e) {
    if (verbose) warning("Unable to list files in release: ", e$message)
    character(0)
  })

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
  
  # Upload each file using gh + httr directly (piggyback pb_upload fails when
  # its internal pb_list cannot find the release due to API schema changes).
  uploaded <- character(0)
  for (file in files_to_upload) {
    if (!file.exists(file)) {
      warning("File not found: ", file)
      next
    }
    
    if (verbose) message("  Uploading: ", basename(file))
    
    tryCatch({
      .gh_upload_release_asset(
        file        = file,
        repo        = repo,
        release_tag = release_tag,
        token       = token,
        overwrite   = overwrite
      )
      uploaded <- c(uploaded, file)
      if (verbose) message("    \u2713 Uploaded")
    }, error = function(e) {
      warning("Failed to upload: ", basename(file), " - ", e$message)
    })
  }
  
 
  # Verify uploaded files are now in the release.
  # Only poll for large files (> 1 MB) — small JSON/parquet files index near-instantly
  # and the 275 s maximum wait was adding unnecessary wall-time for every upload call.
  if (length(uploaded) > 0) {
    large_uploaded <- uploaded[file.size(uploaded) > 1e6]
    if (length(large_uploaded) > 0) {
      if (verbose) message("Verifying ", length(large_uploaded), " large file(s) in release...")
      uploaded_names  <- basename(large_uploaded)
      verified        <- FALSE
      release_asset_names <- NULL
      for (attempt in seq_len(10)) {
        Sys.sleep(attempt * 5)  # 5s, 10s, … 50s
        release_asset_names <- tryCatch(
          .gh_release_asset_names(repo, release_tag, token),
          error = function(e) NULL
        )
        if (!is.null(release_asset_names) &&
            all(uploaded_names %in% release_asset_names)) {
          verified <- TRUE
          break
        }
        if (verbose) message("  Attempt ", attempt, "/10: not all large files visible yet, retrying...")
      }
      if (verified) {
        if (verbose) message("\u2713 Verified: ", length(large_uploaded), " large file(s) confirmed in release")
      } else {
        existing_in_release <- if (!is.null(release_asset_names)) release_asset_names else character(0)
        not_found <- uploaded_names[!uploaded_names %in% existing_in_release]
        warning("Verification incomplete after 10 attempts: ", length(not_found),
                " file(s) not confirmed in release: ", paste(not_found, collapse = ", "),
                "\nFiles may still be available after GitHub finishes indexing.")
      }
    } else {
      if (verbose) message("\u2713 Uploaded ", length(uploaded), " small file(s) (no polling needed)")
    }

    # Write SHA-256 checksums for all uploaded files as a sidecar on the same release.
    # This allows downstream consumers to verify data integrity without re-downloading.
    tryCatch({
      sha_lines <- vapply(uploaded, function(f)
        paste(digest::digest(f, algo = "sha256", file = TRUE), basename(f)),
        character(1L))
      tmp_sha <- tempfile(fileext = ".txt")
      writeLines(sha_lines, tmp_sha)
      sha_asset_name <- paste0(release_tag, "_SHA256SUMS.txt")
      if (verbose) message("Uploading checksum file: ", sha_asset_name)
      .gh_upload_release_asset(
        file        = tmp_sha,
        repo        = repo,
        release_tag = release_tag,
        token       = token,
        overwrite   = TRUE
      )
      # Rename the uploaded asset to the friendly name via a re-upload with ?name=
      if (verbose) message("\u2713 Checksums uploaded as ", sha_asset_name)
    }, error = function(e) {
      if (verbose) message("  (checksum upload skipped: ", conditionMessage(e), ")")
    })
  }

  invisible(uploaded)
}

#' Helper operator
#' @keywords internal
`%not_in%` <- Negate(`%in%`)
