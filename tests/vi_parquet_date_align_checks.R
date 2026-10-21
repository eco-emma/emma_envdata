# Tests for VI parquet filename vs content-date alignment.
# Run: Rscript tests/vi_parquet_date_align_checks.R

source("R/vi_parquet_date_align.R", local = FALSE)

fail <- 0L
check <- function(label, cond) {
  if (isTRUE(cond)) {
    message("OK  ", label)
  } else {
    message("FAIL ", label)
    fail <<- fail + 1L
  }
}

tmp <- tempfile("vi_align_")
dir.create(tmp)
on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

# --- name parsing -----------------------------------------------------------
check(
  "parse modis file date",
  identical(
    parse_vi_parquet_file_date("vi_modis_20200913.parquet"),
    as.Date("2020-09-13")
  )
)
check(
  "parse viirs sensor",
  identical(parse_vi_parquet_sensor("data/x/vi_viirs_20120407.parquet"), "viirs")
)
check(
  "bad name → NA date",
  is.na(parse_vi_parquet_file_date("vi_modis_grid_20200913.tif"))
)
check(
  "release tag modis",
  identical(vi_parquet_release_tag("vi_modis_20000218.parquet"), "vi_modis_parquet")
)

# --- synthetic parquets -----------------------------------------------------
write_toy <- function(path, dates, values = seq_along(dates)) {
  arrow::write_parquet(
    data.frame(
      pid = as.integer(seq_along(dates)),
      date = as.integer(as.Date(dates) - as.Date("1970-01-01")),
      sensor = 1L,
      value = as.integer(values)
    ),
    sink = path,
    compression = "gzip"
  )
}

ok_path <- file.path(tmp, "vi_modis_20200913.parquet")
# September composite: mostly September DOYs inside the window
write_toy(
  ok_path,
  as.Date("2020-09-13") + c(0L, 2L, 5L, 8L, 10L, 12L, 14L, 15L)
)

bad_path <- file.path(tmp, "vi_modis_20200913_bad.parquet")
# Wrong basename month simulation: file named Sep but dates are Jul–Aug
# (use a correctly named file with wrong content instead)
bad_named <- file.path(tmp, "vi_modis_20000913.parquet")
write_toy(
  bad_named,
  as.Date(c(
    "2000-07-20", "2000-07-28", "2000-08-05", "2000-08-12",
    "2000-08-18", "2000-08-20", "2000-08-22", "2000-08-25"
  )),
  values = c(100L, 110L, 120L, 130L, 140L, 150L, 160L, 170L)
)

# Duplicate of bad_named values under another year/filename
dup_path <- file.path(tmp, "vi_modis_20100914.parquet")
write_toy(
  dup_path,
  as.Date(c(
    "2010-07-20", "2010-07-28", "2010-08-05", "2010-08-12",
    "2010-08-18", "2010-08-20", "2010-08-22", "2010-08-25"
  )),
  values = c(100L, 110L, 120L, 130L, 140L, 150L, 160L, 170L)
)

check(
  "aligned September file passes",
  isTRUE(vi_parquet_content_matches_file_date(ok_path))
)
check(
  "Jul–Aug content under September name fails",
  isFALSE(vi_parquet_content_matches_file_date(bad_named))
)

s_ok <- vi_parquet_date_summary(ok_path, hash_values = TRUE)
check("ok status", identical(s_ok$status, "ok"))
check("ok aligned flag", isTRUE(s_ok$aligned))

s_bad <- vi_parquet_date_summary(bad_named, hash_values = TRUE)
check("misaligned status", identical(s_bad$status, "misaligned"))
check(
  "frac_month low for template",
  isTRUE(s_bad$frac_in_filename_month < 0.5)
)

report <- audit_vi_parquet_paths(
  c(ok_path, bad_named, dup_path),
  hash_values = TRUE,
  flag_duplicate_values = TRUE,
  verbose = FALSE
)
check("audit nrow", nrow(report) == 3L)
check(
  "duplicate hash flagged on at least one peer",
  any(report$status == "duplicate_values")
)
check(
  "identical value hashes for template pair",
  identical(
    report$value_hash[report$file == basename(bad_named)],
    report$value_hash[report$file == basename(dup_path)]
  )
)

# --- upload filter ----------------------------------------------------------
kept <- filter_vi_parquets_for_upload(
  c(ok_path, bad_named, file.path(tmp, "readme.txt")),
  strict = FALSE,
  verbose = FALSE
)
check(
  "filter keeps aligned + non-VI paths",
  identical(
    sort(basename(kept)),
    sort(c(basename(ok_path), "readme.txt"))
  )
)

err <- tryCatch(
  filter_vi_parquets_for_upload(c(ok_path, bad_named), strict = TRUE, verbose = FALSE),
  error = function(e) e
)
check("strict mode stops on misaligned", inherits(err, "error"))

# Month-boundary composite: filename Aug 29, dates mostly early Sep still in window
boundary <- file.path(tmp, "vi_viirs_20200829.parquet")
write_toy(
  boundary,
  as.Date("2020-08-29") + 0:15
)
check(
  "16-day window file passes via frac_window",
  isTRUE(vi_parquet_content_matches_file_date(boundary))
)

# Year-boundary: Dec 31 composite stores Jan DOYs under the filename year
# (converter contract). Must still pass via DOY wrap → next-year window.
year_boundary <- file.path(tmp, "vi_modis_20221231.parquet")
write_toy(
  year_boundary,
  as.Date("2022-01-01") + 0:14
)
check(
  "Dec→Jan DOY wrap under filename year passes",
  isTRUE(vi_parquet_content_matches_file_date(year_boundary))
)
s_yb <- vi_parquet_date_summary(year_boundary, hash_values = FALSE)
check("year-boundary status ok", identical(s_yb$status, "ok"))
check(
  "year-boundary still fails without wrap (Jul–Aug under Dec name)",
  isFALSE(
    vi_parquet_content_matches_file_date(
      {
        p <- file.path(tmp, "vi_modis_20221219.parquet")
        write_toy(
          p,
          as.Date(c(
            "2022-07-20", "2022-07-28", "2022-08-05", "2022-08-12",
            "2022-08-18", "2022-08-20", "2022-08-22", "2022-08-25"
          ))
        )
        p
      }
    )
  )
)

if (fail > 0L) {
  stop(fail, " VI parquet date-align check(s) failed", call. = FALSE)
}
message("All VI parquet date-align checks passed.")
