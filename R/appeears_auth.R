library(appeears)

# AppEEARS authentication via keyring (no .netrc)
earthdata_user <- Sys.getenv("EARTHDATA_USER")
earthdata_pass <- Sys.getenv("EARTHDATA_PASSWORD")

if (earthdata_user != "" && earthdata_pass != "") {
  message("Setting up NASA EarthData authentication (keyring file backend)")

  # Configure file keyring backend and location
  if (Sys.getenv("R_KEYRING_PASSWORD") == "") {
    Sys.setenv(R_KEYRING_PASSWORD = earthdata_pass)
  }
  if (Sys.getenv("R_KEYRING_FILE") == "") {
    Sys.setenv(R_KEYRING_FILE = path.expand("~/.config/r-keyring/appeears.keyring"))
  }
  options(keyring_backend = "file")
  suppressWarnings(dir.create(dirname(Sys.getenv("R_KEYRING_FILE")), recursive = TRUE, showWarnings = FALSE))

  kr_name <- "appeears"
  kr_pwd  <- Sys.getenv("R_KEYRING_PASSWORD")

  # Create keyring only if missing
  existing_kr <- tryCatch(keyring::keyring_list()$keyring, error = function(e) character(0))
  if (!(kr_name %in% existing_kr)) {
    keyring::keyring_create(kr_name, password = kr_pwd)
  }

  # Unlock if locked (non-interactive using env password)
  if (keyring::keyring_is_locked(kr_name)) {
    keyring::keyring_unlock(kr_name, password = kr_pwd)
  }

  # Store credentials for appeears token refresh
  suppressMessages(appeears::rs_set_key(user = earthdata_user, password = earthdata_pass))

  # Authenticate (reads from keyring)
  rstoken <- appeears::rs_login(earthdata_user)
  message("AppEEARS authentication configured")
} else {
  warning("EARTHDATA credentials not found. Set EARTHDATA_USER and EARTHDATA_PASSWORD environment variables.")
}
