# Lightweight tests for list_release_inventory() (pending-branch upload trap).
# Run: Rscript tests/upload_inventory_checks.R

source("R/upload_releases.R", local = FALSE)

fail <- 0L
check <- function(label, cond) {
  if (isTRUE(cond)) {
    message("OK  ", label)
  } else {
    message("FAIL ", label)
    fail <<- fail + 1L
  }
}

tmp <- tempfile("upload_inventory_")
dir.create(tmp)
on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

# Product-shaped files + noise that must not be uploaded
writeLines("a", file.path(tmp, "vi_viirs_20120407.parquet"))
writeLines("b", file.path(tmp, "vi_viirs_20260921.parquet"))
writeLines("skip", file.path(tmp, "vi_viirs_20120407.parquet.skip"))
writeLines("cog", file.path(tmp, "vi_viirs_snpp_20120407.tif"))
writeLines("other", file.path(tmp, "readme.txt"))

pattern <- "^vi_viirs_[0-9]{8}\\.parquet$"

inv <- list_release_inventory(tmp, pattern)
check("lists only matching parquets", length(inv) == 2L)
check(
  "basenames are dated parquets",
  identical(
    basename(inv),
    c("vi_viirs_20120407.parquet", "vi_viirs_20260921.parquet")
  )
)

# Branch slice (current pending only) + full disk inventory
branch_only <- file.path(tmp, "vi_viirs_20260921.parquet")
inv2 <- list_release_inventory(tmp, pattern, also = branch_only)
check("also= does not shrink inventory", length(inv2) == 2L)

# also= can surface a matching path; non-matching / missing / .skip dropped
ghost <- file.path(tmp, "vi_viirs_19990101.parquet")
skip_path <- file.path(tmp, "vi_viirs_20120407.parquet.skip")
tif_path <- file.path(tmp, "vi_viirs_snpp_20120407.tif")
inv3 <- list_release_inventory(
  tmp,
  pattern,
  also = c(branch_only, ghost, skip_path, tif_path, NA_character_, "")
)
check("drops missing / skip / non-matching also=", length(inv3) == 2L)

# Missing directory → empty (plus any existing also=)
inv4 <- list_release_inventory(
  file.path(tmp, "no_such_dir"),
  pattern,
  also = branch_only
)
check("missing dir uses also= only", identical(inv4, branch_only))

# Grid pattern keeps sensor COGs, not parquets
grid_pat <- "^vi_viirs_(snpp|noaa20)_[0-9]{8}\\.tif$"
writeLines("n20", file.path(tmp, "vi_viirs_noaa20_20120407.tif"))
grids <- list_release_inventory(tmp, grid_pat)
check("grid inventory is sensor COGs only", length(grids) == 2L)
check(
  "grid basenames",
  identical(
    basename(grids),
    c("vi_viirs_noaa20_20120407.tif", "vi_viirs_snpp_20120407.tif")
  )
)

if (fail > 0L) {
  stop(fail, " upload inventory check(s) failed", call. = FALSE)
}
message("All upload inventory checks passed.")
