#!/usr/bin/env Rscript
# Tests for VI grid COG delete mapping helpers.
# Run: Rscript tests/vi_grid_cog_delete_checks.R

source("R/vi_parquet_date_align.R", local = FALSE)
source("R/vi_geotiff_date_match.R", local = FALSE)
source("R/vi_grid_cog_delete.R", local = FALSE)

fail <- 0L
check <- function(label, cond) {
  if (isTRUE(cond)) {
    message("OK  ", label)
  } else {
    message("FAIL ", label)
    fail <<- fail + 1L
  }
}

modis <- vi_parquet_to_grid_assets("vi_modis_20000218.parquet")
check("MODIS → 2 sensor COGs", nrow(modis) == 2L)
check(
  "MODIS terra asset name",
  identical(modis$asset[[1]], "vi_modis_terra_20000218.tif")
)
check(
  "MODIS aqua release tag",
  identical(modis$release_tag[[2]], "vi_modis_aqua_raster")
)
check(
  "MODIS local dir",
  grepl("modis_vi/vi_modis_terra_20000218\\.tif$", modis$local_path[[1]])
)

viirs <- vi_parquet_to_grid_assets("vi_viirs_20120407.parquet")
check("VIIRS → 2 sensor COGs", nrow(viirs) == 2L)
check(
  "VIIRS snpp + noaa20 share tag",
  identical(unique(viirs$release_tag), "vi_viirs_raster")
)
check(
  "VIIRS asset names",
  identical(
    sort(viirs$asset),
    c("vi_viirs_noaa20_20120407.tif", "vi_viirs_snpp_20120407.tif")
  )
)

tmp <- tempfile(fileext = ".csv")
utils::write.csv(
  data.frame(
    file = c("vi_modis_20000218.parquet", "vi_modis_20000727.parquet"),
    status = c("misaligned", "ok"),
    stringsAsFactors = FALSE
  ),
  tmp,
  row.names = FALSE
)
from_audit <- vi_grid_assets_from_parquet_audit(tmp)
check("audit maps only flagged", nrow(from_audit) == 2L)
check("no survivor warning when flagged present", is.null(attr(from_audit, "csv_warning")))

tmp_ok <- tempfile(fileext = ".csv")
utils::write.csv(
  data.frame(
    file = "vi_modis_20000727.parquet",
    status = "ok",
    stringsAsFactors = FALSE
  ),
  tmp_ok,
  row.names = FALSE
)
survivors <- vi_grid_assets_from_parquet_audit(tmp_ok)
check("survivor CSV → 0 assets", nrow(survivors) == 0L)
check(
  "survivor CSV sets warning",
  is.character(attr(survivors, "csv_warning")) &&
    grepl("0 flagged", attr(survivors, "csv_warning"))
)

dates <- vi_grid_assets_from_dates("20000218", sensors = "modis")
check("dates helper MODIS-only", nrow(dates) == 2L && all(dates$dataset == "vi_modis"))

plan <- delete_vi_grid_assets(modis, dry_run = TRUE, verbose = FALSE)
check("dry-run deletes nothing", length(plan$remote_deleted) == 0L)

# Release-orphan filter (no GitHub): keep grids whose date lacks a parquet.
orphans <- vi_grid_assets_from_release_asset_lists(
  parquet_modis = c("vi_modis_20000727.parquet", "vi_modis_parquet_SHA256SUMS.txt"),
  parquet_viirs = c("vi_viirs_20120407.parquet"),
  grid_terra = c(
    "vi_modis_terra_20000727.tif",  # kept (has parquet)
    "vi_modis_terra_20000218.tif"   # orphan
  ),
  grid_aqua = c("vi_modis_aqua_20000218.tif"),
  grid_viirs = c(
    "vi_viirs_snpp_20120407.tif",   # kept
    "vi_viirs_noaa20_20120101.tif"  # orphan
  ),
  verbose = FALSE
)
check("orphan count", nrow(orphans) == 3L)
check(
  "orphan assets",
  identical(
    sort(orphans$asset),
    c(
      "vi_modis_aqua_20000218.tif",
      "vi_modis_terra_20000218.tif",
      "vi_viirs_noaa20_20120101.tif"
    )
  )
)
check(
  "kept dates not in orphan plan",
  !any(orphans$yyyymmdd %in% c("20000727", "20120407"))
)
check(
  "orphan reason",
  all(orphans$reason == "release_orphan")
)

if (fail > 0L) {
  stop(fail, " vi_grid_cog_delete check(s) failed", call. = FALSE)
}
message("All vi_grid_cog_delete checks passed.")
