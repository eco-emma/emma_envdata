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
  startdate = c("19620101", "20100500", "19650000", "0", "bad"),
  year = c(1962, 2010, 1965, 1970, 1980),
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
check("bad STARTDATE → NA", is.na(tmnp$burn_date[5]))

# ── Cluster helper still works ───────────────────────────────────────────────
cl <- .assign_fire_clusters(c(0L, 10L, 200L, 210L))
check("6-month clusters", identical(cl, c(1L, 1L, 2L, 2L)))

if (fail > 0L) {
  stop(fail, " date-parse check(s) failed", call. = FALSE)
}
message("All fire date-parse checks passed.")
