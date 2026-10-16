# Lightweight tests for W3.1 / W3.2 date helpers (base R + sourced file).
# Run: Rscript tests/fire_date_parse_checks.R

source("R/process_burn_dates.R", local = FALSE)

fail <- 0L
check <- function(label, cond) {
  if (isTRUE(cond)) {
    message("OK  ", label)
  } else {
    message("FAIL ", label)
    fail <<- fail + 1L
  }
}

# ── W3.1 CapeNature-style flexible dates ─────────────────────────────────────
today <- as.Date("2026-10-15")
dmy <- .parse_flexible_date(
  c("28/05/1927", "11/02/1933", "2017-02-15", "", NA, "99/99/9999"),
  today = today
)
check("DD/MM/YYYY 1927", identical(dmy[1], as.Date("1927-05-28")))
check("DD/MM/YYYY 1933", identical(dmy[2], as.Date("1933-02-11")))
check("ISO YYYY-MM-DD", identical(dmy[3], as.Date("2017-02-15")))
check("empty → NA", is.na(dmy[4]) && is.na(dmy[5]))
check("invalid → NA", is.na(dmy[6]))

# ── W3.2 TMNP STARTDATE patterns ─────────────────────────────────────────────
tmnp <- .parse_tmnp_startdate(
  startdate = c(
    "19620101", "20100500", "19650000", "0", "bad",
    # Real shapefile row ID 1993_18: month 93 — previously threw
    # "character string is not in a standard unambiguous format"
    "19939315",
    "2017-02-15", "28/05/1927"
  ),
  year = c(1962, 2010, 1965, 1970, 1980, 1993, 2017, 1927),
  today = today
)
check(
  "YYYYMMDD exact",
  identical(tmnp$burn_date[1], as.Date("1962-01-01")) &&
    identical(tmnp$date_uncertainty_days[1], 0L)
)
check(
  "YYYYMM00 mid-month",
  identical(tmnp$burn_date[2], as.Date("2010-05-15")) &&
    identical(tmnp$date_uncertainty_days[2], 15L)
)
check(
  "YYYY0000 mid-year",
  identical(tmnp$burn_date[3], as.Date("1965-07-01")) &&
    identical(tmnp$date_uncertainty_days[3], 180L)
)
check(
  "STARTDATE 0 falls back to YEAR",
  identical(tmnp$burn_date[4], as.Date("1970-07-01")) &&
    identical(tmnp$date_uncertainty_days[4], 180L)
)
check("bad STARTDATE → YEAR fallback", {
  identical(tmnp$burn_date[5], as.Date("1980-07-01")) &&
    identical(tmnp$date_uncertainty_days[5], 180L)
})
check(
  "corrupt YYYYMMDD (month 93) → YEAR mid-year, no error",
  identical(tmnp$burn_date[6], as.Date("1993-07-01")) &&
    identical(tmnp$date_uncertainty_days[6], 180L)
)
check(
  "TMNP ISO STARTDATE",
  identical(tmnp$burn_date[7], as.Date("2017-02-15")) &&
    identical(tmnp$date_uncertainty_days[7], 0L)
)
check(
  "TMNP DD/MM/YYYY STARTDATE",
  identical(tmnp$burn_date[8], as.Date("1927-05-28")) &&
    identical(tmnp$date_uncertainty_days[8], 0L)
)

# Regression: as.Date without format= must not be used on invalid calendars
check(
  "parse_ymd_safe month 93 → NA (no throw)",
  {
    d <- tryCatch(
      .parse_ymd_safe(1993L, 93L, 15L),
      error = function(e) structure("threw", class = "error-marker")
    )
    inherits(d, "Date") && is.na(d)
  }
)

# ── Cluster helper still works ───────────────────────────────────────────────
cl <- .assign_fire_clusters(c(0L, 10L, 200L, 210L))
check("6-month clusters", identical(cl, c(1L, 1L, 2L, 2L)))

if (fail > 0L) {
  stop(fail, " date-parse check(s) failed", call. = FALSE)
}
message("All fire date-parse checks passed.")
