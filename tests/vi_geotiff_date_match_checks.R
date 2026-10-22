#!/usr/bin/env Rscript
# Tests for AppEEARS VI GeoTIFF date matching + COG DOY guards.
# Run: Rscript tests/vi_geotiff_date_match_checks.R

source("R/vi_geotiff_date_match.R", local = FALSE)

fail <- 0L
check <- function(label, cond) {
  if (isTRUE(cond)) {
    message("OK  ", label)
  } else {
    message("FAIL ", label)
    fail <<- fail + 1L
  }
}

# --- basename date parse ----------------------------------------------------
check(
  "parse AppEEARS EVI timestamp",
  identical(
    parse_appeears_tif_date(
      "MOD13A1.061__500m_16_days_EVI_20000727T000000_aid0001.tif"
    ),
    as.Date("2000-07-27")
  )
)
check(
  "parse VIIRS DOY layer timestamp",
  identical(
    parse_appeears_tif_date(
      "VNP13A1.002__500_m_16_days_composite_day_of_the_year_20200913T000000_aid0001.tif"
    ),
    as.Date("2020-09-13")
  )
)
check(
  "bad name → NA",
  is.na(parse_appeears_tif_date("not_an_appeears_file.tif"))
)

# --- window filter (mixed pile) ---------------------------------------------
cd <- as.Date("2000-02-18")
mixed <- list(
  list(
    path = "MOD13A1.061__500m_16_days_EVI_20000218T000000_aid0001.tif",
    product = "terra",
    layer = "evi"
  ),
  list(
    path = "MYD13A1.061__500m_16_days_EVI_20000727T000000_aid0001.tif",
    product = "aqua",
    layer = "evi"
  ),
  list(
    path = "MYD13A1.061__500m_16_days_EVI_20000218T000000_aid0001.tif",
    product = "aqua",
    layer = "evi"
  )
)
filtered <- filter_appeears_tif_info_for_composite(
  mixed,
  composite_date = cd,
  composite_end = cd + 15L,
  verbose = FALSE
)
check("mixed pile drops Jul aqua", length(filtered) == 2L)
check(
  "no Jul date remains",
  !any(vapply(filtered, function(x) identical(x$file_date, as.Date("2000-07-27")), logical(1)))
)
picked <- pick_appeears_tif_layer(filtered, "aqua", "evi", composite_date = cd)
check(
  "pick aqua EVI is Feb not Jul",
  !is.null(picked) && identical(picked$file_date, as.Date("2000-02-18"))
)
empty_pick <- pick_appeears_tif_layer(filtered, "terra", "doy", composite_date = cd)
check("missing layer → NULL", is.null(empty_pick))

# --- DOY → date wrap --------------------------------------------------------
doy_dates <- .vi_doy_to_dates(c(360L, 5L), as.Date("2022-12-19"))
check(
  "Dec composite wraps Jan DOY to next year",
  identical(doy_dates[[2]], as.Date("2023-01-05"))
)

# --- synthetic COG DOY check (needs terra) ----------------------------------
if (requireNamespace("terra", quietly = TRUE)) {
  tmp <- tempfile("vi_cog_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  write_cog <- function(path, doy_vals, evi_vals = doy_vals) {
    # 2x2 tiny raster
    evi <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2)
    doy <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2)
    terra::values(evi) <- as.integer(evi_vals)
    terra::values(doy) <- as.integer(doy_vals)
    names(evi) <- "evi"
    names(doy) <- "doy"
    terra::writeRaster(c(evi, doy), path, overwrite = TRUE)
  }

  ok_cog <- file.path(tmp, "vi_modis_aqua_20200913.tif")
  # DOY ~ Sep 13–28
  write_cog(ok_cog, c(257L, 260L, 265L, 270L))
  check(
    "good Sep COG passes",
    isTRUE(vi_cog_doy_matches_composite(ok_cog, as.Date("2020-09-13")))
  )

  bad_cog <- file.path(tmp, "vi_modis_aqua_20000218.tif")
  # Jul–Aug template under Feb name
  write_cog(bad_cog, c(201L, 205L, 210L, 216L))
  check(
    "Jul DOY under Feb basename fails",
    isFALSE(vi_cog_doy_matches_composite(bad_cog, as.Date("2000-02-18")))
  )

  na_cog <- file.path(tmp, "vi_modis_aqua_20000305.tif")
  write_cog(na_cog, c(NA_integer_, NA_integer_, NA_integer_, NA_integer_))
  check(
    "all-NA placeholder passes",
    isTRUE(vi_cog_doy_matches_composite(na_cog, as.Date("2000-03-05")))
  )

  kept <- filter_vi_grid_cogs_for_upload(
    c(ok_cog, bad_cog, na_cog),
    strict = FALSE,
    verbose = FALSE
  )
  check(
    "upload filter drops bad keeps good+NA",
    identical(basename(kept), basename(c(ok_cog, na_cog)))
  )

  check(
    "assert stops on bad DOY rast",
    {
      r <- terra::rast(bad_cog)[["doy"]]
      inherits(
        tryCatch(
          assert_vi_doy_in_composite_window(
            r,
            composite_date = as.Date("2000-02-18"),
            sensor_label = "aqua"
          ),
          error = function(e) e
        ),
        "error"
      )
    }
  )
} else {
  message("SKIP terra-backed COG checks (terra not installed)")
}

if (fail > 0L) {
  stop(fail, " VI geotiff date-match check(s) failed", call. = FALSE)
}
message("All VI geotiff date-match checks passed.")
