# Load all packages listed in DESCRIPTION file (quietly, suppressing startup messages)
load_description_packages <- function(description_file = "DESCRIPTION", quietly = TRUE, verbose = FALSE) {
  # Read DESCRIPTION file
  dcf <- read.dcf(description_file)
  
  # Extract Imports and Depends fields
  imports <- if ("Imports" %in% colnames(dcf)) dcf[1, "Imports"] else ""
  depends <- if ("Depends" %in% colnames(dcf)) dcf[1, "Depends"] else ""
  
  # Combine, split, and clean
  all_text <- paste(imports, depends, sep = ",")
  packages <- trimws(strsplit(all_text, ",")[[1]])
  
  # Remove version specifications (e.g., "ggplot2 (>= 3.0)" -> "ggplot2")
  packages <- sub("\\s*\\(.*\\).*", "", packages)
  
  # Remove empty strings and R itself
  packages <- packages[nzchar(packages) & packages != "R"]
  
  # Load each package with suppressed startup messages
  invisible(sapply(packages, function(pkg) {
    suppressPackageStartupMessages(
      library(pkg, character.only = TRUE, quietly = quietly)
    )
  }))
  
  if (verbose) message(paste("Loaded", length(packages), "packages from DESCRIPTION"))
  invisible(packages)
}
