#' @title Validate STAC catalog asset links
#'
#' @description Walks the local STAC catalog tree (catalog.json → collections →
#'   items) and performs an HTTP HEAD request against every asset HREF that
#'   begins with \code{https://}. Writes a JSON report summarising which links
#'   resolved (HTTP 200) and which did not.  Issues a \code{warning()} when any
#'   broken links are found but does \emph{not} stop execution, so the pipeline
#'   continues and the report can be inspected in CI artifacts.
#'
#' @param catalog_json Character. Path to the local \code{catalog.json}.
#' @param report_file  Character. Path where the JSON validation report is
#'   written.
#' @param verbose Logical. Print progress messages?
#'
#' @return Character path to the written \code{report_file}.
#' @export
validate_stac_links <- function(
    catalog_json = "data/stac/catalog.json",
    report_file  = "data/stac/validation_report.json",
    verbose      = TRUE) {

  results <- list()

  # Recursively walk the STAC tree; visit each JSON file once (track visited
  # paths to avoid infinite loops from circular self/root links).
  visited <- character(0)

  walk_item <- function(json_path) {
    # Normalise so we can de-duplicate regardless of ./relative prefix
    json_path <- normalizePath(json_path, mustWork = FALSE)
    if (json_path %in% visited || !file.exists(json_path)) return()
    visited <<- c(visited, json_path)

    obj <- tryCatch(jsonlite::read_json(json_path), error = function(e) NULL)
    if (is.null(obj)) return()

    # ── Check every asset href in this document ───────────────────────────
    if (!is.null(obj$assets)) {
      for (key in names(obj$assets)) {
        href <- obj$assets[[key]]$href
        if (!is.null(href) && grepl("^https://", href)) {
          status <- tryCatch({
            r <- httr::HEAD(href, httr::timeout(15))
            httr::status_code(r)
          }, error = function(e) NA_integer_)

          ok <- !is.na(status) && status == 200L
          results[[length(results) + 1L]] <<- list(
            source = basename(json_path),
            asset  = key,
            href   = href,
            status = status,
            ok     = ok
          )
          if (verbose && !ok)
            message("  \u26a0 BROKEN [", status, "]: ", key, " -> ", href)
        }
      }
    }

    # ── Recurse into child / item links (skip root/self/parent back-links) ─
    for (lnk in obj$links) {
      if (!is.null(lnk$rel) && lnk$rel %in% c("child", "item")) {
        child_path <- file.path(dirname(json_path), lnk$href)
        walk_item(child_path)
      }
    }
  }

  if (verbose) message("Validating STAC asset links from: ", catalog_json)
  walk_item(catalog_json)

  n_total  <- length(results)
  n_broken <- sum(!vapply(results, `[[`, logical(1), "ok"))

  report <- list(
    validated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    total        = n_total,
    broken       = n_broken,
    items        = results
  )

  dir.create(dirname(report_file), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(report, report_file, pretty = TRUE, auto_unbox = TRUE)

  if (n_broken > 0L) {
    warning(
      "STAC validation: ", n_broken, "/", n_total,
      " asset link(s) are broken. See: ", report_file
    )
  } else if (verbose) {
    message("STAC validation: all ", n_total, " link(s) OK.")
  }

  report_file
}
