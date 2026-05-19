#' Generate a manifest of all targets from the live pipeline store
#'
#' Reads metadata from the targets store via \code{targets::tar_meta()} and
#' writes a JSON summary of every stem target — name, format, size in bytes,
#' last-run timestamp, runtime in seconds, and any error/warning strings.
#' Useful for auditing what is in each GitHub release and when it last ran.
#'
#' @param out_file Character. Output path for the JSON manifest file.
#' @return Character path to the written JSON file.
#' @export
#'
generate_release_manifest <- function(
  out_file = "data/target_outputs/TARGET_MANIFEST.json"
) {

  meta <- targets::tar_meta(fields = c("name", "type", "format", "bytes", "time", "seconds", "error", "warnings"))

  # Keep only stem targets (exclude branches, patterns, and pipeline internals)
  stems <- meta[!is.na(meta$type) & meta$type == "stem", ]

  # Convert POSIXct to ISO-8601 string for JSON portability
  stems$time <- format(stems$time, "%Y-%m-%dT%H:%M:%SZ")

  # Replace NA with NULL-friendly empty string for clean JSON
  stems[is.na(stems)] <- ""

  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(stems, path = out_file, pretty = TRUE, auto_unbox = TRUE)

  out_file
}
