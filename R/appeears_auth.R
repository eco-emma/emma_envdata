library(appeears)

# Initialize AppEEARS authentication using environment variables.
# Uses keyring::backend_env (in-process env vars; no keyring file, no file
# locking) so it is safe to call from parallel crew workers.
# Call ensure_appeears_auth() at the top of every target function that uses
# the AppEEARS API.
ensure_appeears_auth <- function(verbose = FALSE) {
  # Idempotent: skip if already authenticated in this R session.
  if (isTRUE(getOption("appeears_auth_done"))) return(invisible(NULL))

  # Load ~/.Renviron if it exists — R's own parser handles quoted values and
  # avoids the shell $-expansion that can corrupt passwords passed via --env.
  renviron <- path.expand("~/.Renviron")
  if (file.exists(renviron)) readRenviron(renviron)

  user <- trimws(Sys.getenv("EARTHDATA_USER"))
  pass <- trimws(Sys.getenv("EARTHDATA_PASSWORD"))

  if (user == "" || pass == "") {
    stop(
      "AppEEARS authentication failed: ",
      "EARTHDATA_USER and EARTHDATA_PASSWORD environment variables must be set."
    )
  }

  message("AppEEARS auth: user='", user, "' pass_nchar=", nchar(pass))

  # The appeears .onAttach forces http_version=2 globally; reset to default so
  # compute-node network paths that don't support HTTP/2 don't block logins.
  httr::set_config(httr::config(http_version = 0))

  # backend_env stores credentials as env vars (via Sys.setenv internally),
  # so there is no keyring file to lock, create, or share between processes.
  # rs_set_key() validates credentials via rs_check_login() before storing,
  # which gives a clear error if the username/password are wrong.
  options(keyring_backend = keyring::backend_env)
  suppressMessages(
    appeears::rs_set_key(user = user, password = pass)
  )

  # service$initialize() calls rs_login() on every rs_request() call (one per
  # dynamic branch). With many branches, rapid sequential logins hit the
  # AppEEARS rate limit (~7-8 calls). Replace rs_login in the appeears namespace
  # with a memoized version: the bearer token is fetched once and reused for the
  # entire R session. Token lifetime is 24 h (well beyond any pipeline run).
  utils::assignInNamespace(
    "rs_login",
    memoise::memoise(appeears::rs_login),
    ns = "appeears"
  )

  options(appeears_auth_done = TRUE)
  if (verbose) message("AppEEARS authentication configured")
  invisible(NULL)
}
