#' @title List asset names in a GitHub release
#' @description Retrieves asset filenames for a release tag using the gh package
#'   directly (avoids piggyback API incompatibilities). Pages the release
#'   assets endpoint — \code{GET .../releases/tags/\{tag\}} embeds at most ~30
#'   assets, which is wrong for large parquet releases.
#' @param repo Repository in format "owner/repo"
#' @param release_tag Release tag string
#' @param token GitHub token
#' @param strict If TRUE, errors propagate; if FALSE (default), return
#'   \code{character(0)} on failure (missing tag, network, etc.).
#' @return Character vector of asset file names
#' @keywords internal
.gh_release_asset_names <- function(repo, release_tag, token, strict = FALSE) {
  parts <- strsplit(repo, "/")[[1]]
  tryCatch({
    rel <- gh::gh(
      "GET /repos/{owner}/{repo}/releases/tags/{tag}",
      owner = parts[1], repo = parts[2], tag = release_tag,
      .token = token
    )
    assets <- gh::gh(
      "GET /repos/{owner}/{repo}/releases/{release_id}/assets",
      owner = parts[1], repo = parts[2], release_id = rel$id,
      per_page = 100,
      .token = token,
      .limit = Inf
    )
    if (length(assets) == 0L) {
      return(character(0))
    }
    # gh::gh may return a single asset as an unnamed list, or a list of assets.
    if (!is.null(assets$name) && is.character(assets$name)) {
      return(assets$name)
    }
    vapply(assets, function(a) a$name, character(1L))
  }, error = function(e) {
    if (isTRUE(strict)) {
      stop(conditionMessage(e), call. = FALSE)
    }
    character(0)
  })
}

#' @title Fetch remote SHA-256 checksums for a release's assets
#' @description Downloads and parses the "{release_tag}_SHA256SUMS.txt" sidecar
#'   written by \code{upload_to_github_release()} so callers can compare local
#'   file content against what's already on the release, instead of assuming
#'   "overwrite" means "reupload everything".
#' @param repo Repository in format "owner/repo"
#' @param release_tag Release tag string
#' @param token GitHub token
#' @return Named character vector of SHA-256 hashes keyed by asset basename,
#'   or character(0) if the sidecar is missing or unreadable.
#' @keywords internal
.gh_release_remote_checksums <- function(repo, release_tag, token) {
  parts <- strsplit(repo, "/")[[1]]
  sha_asset_name <- paste0(release_tag, "_SHA256SUMS.txt")
  tryCatch({
    rel <- gh::gh(
      "GET /repos/{owner}/{repo}/releases/tags/{tag}",
      owner = parts[1], repo = parts[2], tag = release_tag,
      .token = token
    )
    # Page assets — embedded rel$assets is capped at ~30 names.
    assets <- gh::gh(
      "GET /repos/{owner}/{repo}/releases/{release_id}/assets",
      owner = parts[1], repo = parts[2], release_id = rel$id,
      per_page = 100,
      .token = token,
      .limit = Inf
    )
    if (length(assets) == 0L) return(character(0))
    if (!is.null(assets$name) && is.character(assets$name)) {
      assets <- list(assets)
    }
    asset <- Filter(function(a) identical(a$name, sha_asset_name), assets)
    if (length(asset) == 0L) return(character(0))
    resp <- httr::GET(
      url = asset[[1]]$url,
      httr::add_headers(Authorization = paste("token", token),
                        Accept = "application/octet-stream"),
      httr::timeout(60)
    )
    if (httr::status_code(resp) != 200L) return(character(0))
    lines <- strsplit(httr::content(resp, as = "text", encoding = "UTF-8"), "\n")[[1]]
    lines <- trimws(lines[nzchar(trimws(lines))])
    if (length(lines) == 0L) return(character(0))
    fields <- strsplit(lines, "\\s+")
    hashes <- vapply(fields, `[[`, character(1L), 1L)
    fnames <- vapply(fields, function(x) x[length(x)], character(1L))
    stats::setNames(hashes, fnames)
  }, error = function(e) character(0))
}

#' @title Resolve a GitHub token for release uploads
#' @return Non-empty token string, or stops if none is available
#' @keywords internal
.gh_upload_token <- function(verbose = TRUE) {
  token <- Sys.getenv("GITHUB_PAT")
  if (!nzchar(token)) token <- Sys.getenv("GITHUB_TOKEN")
  if (!nzchar(token)) {
    token <- tryCatch(
      trimws(system("gh auth token", intern = TRUE, ignore.stderr = TRUE)[[1]]),
      error = function(e) ""
    )
    if (is.na(token)) token <- ""
    if (nzchar(token) && verbose) {
      message("Using GitHub token from 'gh auth token'")
    }
  }
  if (!nzchar(token)) {
    stop(
      "No GitHub token found (GITHUB_PAT, GITHUB_TOKEN, or gh CLI). ",
      "On CCR: export GITHUB_PAT from ~/.Renviron or run `gh auth login`, ",
      "then re-run inside Apptainer.",
      call. = FALSE
    )
  }
  token
}

#' @title True if a release tag exists and is readable with the token
#' @keywords internal
.gh_release_exists <- function(repo, release_tag, token) {
  parts <- strsplit(repo, "/")[[1]]
  tryCatch({
    gh::gh(
      "GET /repos/{owner}/{repo}/releases/tags/{tag}",
      owner = parts[1], repo = parts[2], tag = release_tag,
      .token = token
    )
    TRUE
  }, error = function(e) FALSE)
}

#' @title Ensure a GitHub release tag exists (create if missing)
#' @description GET first; POST create on miss; gh CLI fallback; hard-stop if
#'   the tag is still missing. Never treats create failure as "already exists".
#' @keywords internal
.ensure_github_release <- function(repo, release_tag, release_name, token,
                                   verbose = TRUE) {
  parts <- strsplit(repo, "/")[[1]]
  if (.gh_release_exists(repo, release_tag, token)) {
    if (verbose) message("Using existing release '", release_tag, "'")
    return(invisible(TRUE))
  }

  create_err <- NULL
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
    create_err <<- conditionMessage(e)
  })

  if (.gh_release_exists(repo, release_tag, token)) {
    return(invisible(TRUE))
  }

  # API create failed and tag still missing — try gh CLI (often has org SSO /
  # write scope when a stale GITHUB_PAT in the environment does not).
  gh_bin <- Sys.which("gh")
  if (nzchar(gh_bin)) {
    if (verbose) {
      message(
        "API create failed for '", release_tag, "'",
        if (!is.null(create_err)) paste0(" (", create_err, ")"),
        "; trying `gh release create`..."
      )
    }
    args <- c(
      "release", "create", release_tag,
      "--repo", repo,
      "--title", release_name,
      "--notes", paste("Release", release_tag),
      "--prerelease"
    )
    exit_code <- system2(gh_bin, args, stdout = TRUE, stderr = TRUE)
    status <- attr(exit_code, "status")
    if (is.null(status)) status <- 0L
    if (status == 0L && .gh_release_exists(repo, release_tag, token)) {
      if (verbose) message("\u2713 Created release '", release_tag, "' via gh CLI")
      return(invisible(TRUE))
    }
  }

  stop(
    "Could not create or read GitHub release '", release_tag, "' on ", repo, ". ",
    "Tag is still missing after API",
    if (nzchar(gh_bin)) "/gh-CLI",
    " create. ",
    if (!is.null(create_err)) paste0("API error: ", create_err, " "),
    "Check token scopes (contents:write) and org SSO authorization for eco-emma.",
    call. = FALSE
  )
}

#' @title Upload a single file to a GitHub release via the REST API
#' @description Posts a file to a release upload URL using httr, bypassing
#'   piggyback which has known column-selection errors against newer GitHub
#'   API response schemas. Falls back to `gh release upload` when the REST
#'   upload fails (same pattern as the DELETE/clobber path).
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
  # httr::RETRY + explicit secondary-rate-limit backoff mirrors the pattern in
  # R/tar_release_storage.R so a burst of uploads doesn't exhaust the
  # installation token's REST rate limit.
  resp <- httr::RETRY(
    verb  = "POST",
    url   = paste0(upload_url, "?name=", utils::URLencode(basename(file), reserved = TRUE)),
    httr::add_headers(Authorization = paste("token", token),
                      `Content-Type` = "application/octet-stream"),
    body    = httr::upload_file(file),
    httr::timeout(600),
    times = 3, terminate_on = c(400, 401, 404, 422)
  )
  status <- httr::status_code(resp)
  if (status == 429L ||
      (status == 403L &&
       grepl("rate limit",
             tryCatch(httr::content(resp, "text", encoding = "UTF-8"), error = function(e) ""),
             ignore.case = TRUE))) {
    message("  Secondary rate limit hit — sleeping 60s before continuing")
    Sys.sleep(60L)
    stop("Rate-limited uploading ", basename(file), " — will retry on next run")
  }
  if (status >= 200L && status < 300L) {
    return(invisible(TRUE))
  }

  # REST upload failed (auth/scope/404). Fall back to gh CLI, which often has
  # working credentials when GITHUB_PAT is stale or lacks org SSO.
  api_err <- tryCatch(
    paste0(status, " ", httr::content(resp, "text", encoding = "UTF-8")),
    error = function(e) as.character(status)
  )
  gh_bin <- Sys.which("gh")
  if (nzchar(gh_bin)) {
    clobber <- if (isTRUE(overwrite)) "--clobber" else NULL
    exit_code <- system2(
      gh_bin,
      c(
        "release", "upload", release_tag,
        normalizePath(file, mustWork = TRUE),
        "--repo", repo,
        clobber
      ),
      stdout = TRUE,
      stderr = TRUE
    )
    status_cli <- attr(exit_code, "status")
    if (is.null(status_cli)) status_cli <- 0L
    if (status_cli == 0L) return(invisible(TRUE))
    stop(
      "REST upload failed (", api_err, ") and gh CLI upload failed for ",
      basename(file), ": ", paste(exit_code, collapse = " "),
      call. = FALSE
    )
  }
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
  
  token <- .gh_upload_token(verbose = verbose)

  # Filter to files that exist
  files <- files[file.exists(files)]
  if (length(files) == 0) {
    message("No files found to upload")
    return(invisible(character(0)))
  }

  # Ensure release exists — hard-fail if create/read fails (do not swallow as
  # "Using existing release"; that caused CCR publish to exit 0 with 0 assets
  # while vi_viirs_parquet stayed 404).
  .ensure_github_release(
    repo = repo,
    release_tag = release_tag,
    release_name = release_name,
    token = token,
    verbose = verbose
  )

  # List existing assets using gh package directly (piggyback pb_list has
  # incompatibilities with newer GitHub API response schemas).
  existing_names <- .gh_release_asset_names(
    repo, release_tag, token, strict = TRUE
  )

  # Deduplicate files (branched targets may return same path from multiple branches)
  files <- files[!duplicated(basename(files))]

  # Filter to files that don't already exist (unless overwrite = TRUE).
  # When overwrite = TRUE, only reupload files whose content actually changed
  # (compared against the release's SHA256SUMS.txt sidecar) rather than
  # blindly deleting+reposting every historical file on every run — this was
  # the main driver of installation-level API rate-limit errors.
  if (overwrite) {
    remote_hashes <- .gh_release_remote_checksums(repo, release_tag, token)
    local_hashes  <- vapply(files, function(f) digest::digest(f, algo = "sha256", file = TRUE),
                            character(1L))
    names(local_hashes) <- basename(files)
    needs_upload <- vapply(names(local_hashes), function(nm) {
      is.na(remote_hashes[nm]) || !identical(unname(remote_hashes[nm]), unname(local_hashes[nm]))
    }, logical(1L))
    files_to_upload <- files[needs_upload]
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
  # Large batches throttle between requests to avoid tripping GitHub's
  # secondary rate limit, which otherwise silently fails most of the batch.
  throttle <- length(files_to_upload) > 50L
  upload_batch <- function(file_list) {
    ok <- character(0)
    failed <- character(0)
    for (file in file_list) {
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
        ok <- c(ok, file)
        if (verbose) message("    \u2713 Uploaded")
      }, error = function(e) {
        failed <<- c(failed, file)
        warning("Failed to upload: ", basename(file), " - ", e$message)
      })
      if (throttle) Sys.sleep(0.5)
    }
    list(ok = ok, failed = failed)
  }

  first_pass <- upload_batch(files_to_upload)
  uploaded   <- first_pass$ok

  # Retry once after a backoff — most first-pass failures are transient
  # secondary-rate-limit hits rather than permanent errors.
  still_failed <- first_pass$failed
  if (length(still_failed) > 0L) {
    if (verbose) message(
      "Retrying ", length(still_failed),
      " failed upload(s) after 30s backoff..."
    )
    Sys.sleep(30L)
    retry_pass <- upload_batch(still_failed)
    uploaded   <- c(uploaded, retry_pass$ok)
    still_failed <- retry_pass$failed
  }

  if (length(still_failed) > 0L) {
    stop(
      length(still_failed), " file(s) failed to upload to '", release_tag,
      "' after retry: ",
      paste(basename(utils::head(still_failed, 20L)), collapse = ", "),
      if (length(still_failed) > 20L) " ..." else "",
      ". Succeeded: ", length(uploaded), "/", length(files_to_upload), ".",
      call. = FALSE
    )
  }

  if (length(files_to_upload) > 0L && length(uploaded) == 0L) {
    stop(
      "Upload to '", release_tag, "' reported 0 successes for ",
      length(files_to_upload), " file(s). Check token scopes and release tag.",
      call. = FALSE
    )
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
      sha_lines <- vapply(files, function(f)
        paste(digest::digest(f, algo = "sha256", file = TRUE), basename(f)),
        character(1L))
      sha_asset_name <- paste0(release_tag, "_SHA256SUMS.txt")
      # basename(tmp_sha) is used as the uploaded asset name, so it must
      # already be sha_asset_name (a bare tempfile() name was uploaded as-is before).
      tmp_sha <- file.path(tempdir(), sha_asset_name)
      writeLines(sha_lines, tmp_sha)
      if (verbose) message("Uploading checksum file: ", sha_asset_name)
      .gh_upload_release_asset(
        file        = tmp_sha,
        repo        = repo,
        release_tag = release_tag,
        token       = token,
        overwrite   = TRUE
      )
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

#' @title List local files belonging to a product release
#' @description Scans \code{dir} for files matching \code{pattern} and unions
#'   them with optional target-returned paths in \code{also}. Upload targets
#'   must use this (not only dynamic-branch outputs): \code{*_pending} filters
#'   to composites/months missing from the *raster* release, so branched
#'   parquet/grid targets only return the current slice. Historical files that
#'   already exist on disk would otherwise never be offered to
#'   \code{upload_to_github_release()}, which then diffs against release assets
#'   and uploads only missing/changed files.
#' @param dir Directory to scan (relative or absolute)
#' @param pattern Regex matched against basenames (\code{list.files} pattern)
#' @param also Optional character vector of additional paths (e.g. from a
#'   branched target). Establishes the targets dependency when passed through
#'   from \code{_targets.R}. NA, empty, missing, and \code{*.skip} paths are
#'   dropped; remaining paths must match \code{pattern} on the basename.
#' @param verbose Logical; message inventory size when TRUE
#' @return Sorted unique character vector of existing file paths
#' @export
list_release_inventory <- function(dir, pattern, also = character(0),
                                   verbose = FALSE) {
  on_disk <- character(0)
  if (length(dir) == 1L && is.character(dir) && nzchar(dir) && dir.exists(dir)) {
    on_disk <- list.files(dir, pattern = pattern, full.names = TRUE)
  }

  also <- as.character(also)
  also <- also[!is.na(also) & nzchar(also) & !grepl("\\.skip$", also)]
  also <- also[file.exists(also)]
  if (length(also) > 0L && length(pattern) == 1L && nzchar(pattern)) {
    also <- also[grepl(pattern, basename(also))]
  }

  files <- sort(unique(c(on_disk, also)))
  if (isTRUE(verbose)) {
    message(
      "list_release_inventory: ", length(files), " file(s) under ",
      if (length(dir) == 1L) dir else "?",
      " matching /", pattern, "/"
    )
  }
  files
}
