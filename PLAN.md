# EMMA Environmental Data Pipeline — Prioritized Improvement Plan

> Companion to `ARCHITECTURE.md`  
> Branch: `dev-adam-appeears-cog`  
> June 2026

Issue references map to the `ARCHITECTURE.md` sections (5.x = Design Issue, CQ-x = Code Quality, P-x = Performance, S-x = Security).

---

## Priority Legend

| Symbol | Meaning |
|--------|---------|
| 🔴 P0 | **Blocking** — pipeline produces broken/missing output today |
| 🟠 P1 | **High** — correctness or reliability risk; fix before next wide release |
| 🟡 P2 | **Medium** — CI hygiene, maintainability, incorrect metadata |
| 🟢 P3 | **Low** — performance, minor polish |

---


## Step 6 🟠 P1 — Single source of truth for release tags

**Problem (ARCHITECTURE.md §CQ-7):** Release tag strings (e.g. `"vi_modis_dynamic_raster"`, `"burn_dates_modis_raster"`, `"firehistory_dynamic"`) are duplicated across `_targets.R` (upload targets), `R/stac_functions.R` (asset HREF construction), and `get_*.R` (idempotency checks). A renaming in one place silently breaks links in another — exactly how the `.nc`/`.tif` mismatch was introduced.

**Fix:** Define a central config list in `_targets.R` and pass it explicitly:

```r
# In _targets.R, near the top with gh_repo_config:
release_tags <- list(
  static            = "static_data",
  vi_modis_raster   = "vi_modis_dynamic_raster",
  vi_viirs_raster   = "vi_viirs_dynamic_raster",
  vi_modis_parquet  = "vi_modis_dynamic",
  burn_modis_raster = "burn_dates_modis_raster",
  burn_viirs_raster = "burn_dates_viirs_raster",
  burn_modis_parq   = "burndate_modis_dynamic",
  burn_viirs_parq   = "burndate_viirs_dynamic",
  fire_history      = "firehistory_dynamic",
  stac              = "stac",
  cache             = "targets-cache"
)
```

Then thread `release_tags` into every target that needs a tag string, removing all repeated string literals. The STAC generator functions should accept tag parameters (they already do) — the default argument values in their signatures can stay for backwards compatibility but the live pipeline should always pass explicit values from `release_tags`.

---

## Step 7 🟠 P1 — Ensure STAC JSONs are reliably published to the `stac` release

**Problem (ARCHITECTURE.md §5.5):** The `upload_stac_catalog` target globs `data/stac/**/*.json` and uploads with `overwrite=TRUE`. If any upload fails (network error, rate-limit, missing file), the `stac` release is left in a partially-updated state. There is no verification that all expected JSON files landed.

**Fix in `upload_to_github_release()` / `_targets.R`:**

1. **Verify file existence before upload:** In `upload_stac_catalog`, explicitly enumerate the expected JSON files from the collection targets' return values rather than globbing from disk. This ensures nothing is accidentally omitted:
   ```r
   stac_files <- unique(c(
     emma_stac_catalog,            # catalog.json path (from target return)
     vi_stac,                       # vi_collection.json + item paths
     burn_stac,                     # burn_collection.json + item paths
     static_stac                    # static_collection.json + item paths
   ))
   stac_files <- stac_files[file.exists(stac_files)]
   ```

2. **Post-upload JSON count check:** After `upload_to_github_release()` returns, count the assets on the `stac` release via `gh_release_has_asset()` or a simple `gh::gh()` call and warn if the count is less than `length(stac_files)`:
   ```r
   after_count <- length(.gh_release_asset_names(repo, "stac", token))
   if (after_count < length(stac_files)) {
     warning("STAC upload incomplete: expected ", length(stac_files),
             " files, found ", after_count, " on release.")
   }
   ```

3. **Replace `piggyback::pb_new_release()` in `upload_to_github_release()`** with the same direct `gh::gh()` pattern used everywhere else in the codebase (fixes CQ-5):
   ```r
   tryCatch(
     gh::gh("POST /repos/{owner}/{repo}/releases",
            owner = parts[1], repo = parts[2],
            tag_name = release_tag, name = release_name,
            prerelease = TRUE, .token = token),
     error = function(e) {
       if (verbose) message("Using existing release '", release_tag, "'")
     }
   )
   ```

---

## Step 8 🟠 P1 — Add a runtime STAC validation target (warn/report)

**Problem (ARCHITECTURE.md §5.6):** After publication, there is no check that STAC asset HREFs actually resolve to real GitHub Release assets.

**Fix:** Add a new `validate_stac` target in `_targets.R` and a new function `R/validate_stac.R`:

**`R/validate_stac.R`:**
```r
#' Walk STAC catalog and HEAD-check every asset HREF
#' @param catalog_json Path to the root catalog.json (on disk, not the release URL)
#' @param report_file  Path to write a JSON report
#' @return Path to the report file
#' @export
validate_stac_links <- function(
    catalog_json = "data/stac/catalog.json",
    report_file  = "data/stac/validation_report.json",
    verbose      = TRUE) {

  results <- list()

  walk_item <- function(json_path) {
    if (!file.exists(json_path)) return()
    obj <- tryCatch(jsonlite::read_json(json_path), error = function(e) NULL)
    if (is.null(obj)) return()

    # Check asset hrefs in items
    if (!is.null(obj$assets)) {
      for (key in names(obj$assets)) {
        href <- obj$assets[[key]]$href
        if (!is.null(href) && grepl("^https://", href)) {
          status <- tryCatch({
            r <- httr::HEAD(href, httr::timeout(15))
            httr::status_code(r)
          }, error = function(e) NA_integer_)
          results[[length(results) + 1]] <<- list(
            source = basename(json_path),
            asset  = key,
            href   = href,
            status = status,
            ok     = !is.na(status) && status == 200L
          )
          if (verbose && (is.na(status) || status != 200L))
            message("  ⚠ BROKEN: ", key, " → ", href, " [", status, "]")
        }
      }
    }

    # Recurse into child/item links
    for (lnk in obj$links) {
      if (!is.null(lnk$rel) && lnk$rel %in% c("child", "item")) {
        child_path <- file.path(dirname(json_path), lnk$href)
        walk_item(child_path)
      }
    }
  }

  if (verbose) message("Validating STAC links from: ", catalog_json)
  walk_item(catalog_json)

  report <- list(
    validated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    total        = length(results),
    broken       = sum(!sapply(results, `[[`, "ok")),
    items        = results
  )
  jsonlite::write_json(report, report_file, pretty = TRUE, auto_unbox = TRUE)

  n_broken <- report$broken
  if (n_broken > 0)
    warning("STAC validation: ", n_broken, "/", report$total,
            " asset links are broken. See: ", report_file)
  else if (verbose)
    message("STAC validation: all ", report$total, " links OK.")

  report_file
}
```

**In `_targets.R`**, add after `upload_stac_catalog`:
```r
tar_target(
  validate_stac,
  validate_stac_links(
    catalog_json = file.path("data/stac", "catalog.json"),
    report_file  = "data/stac/validation_report.json",
    verbose      = TRUE
  ),
  format     = "file",
  deployment = "main"
),
```

This will **warn** (not fail) when broken links are found, and produce a machine-readable `validation_report.json` that can be inspected in CI artifacts.

---

## Step 9 🟡 P2 — Correct `deployment = "main"` comments

**Problem (ARCHITECTURE.md §5.7):** Comments on every upload/STAC target say they "only run on the main branch" but `deployment = "main"` in `targets` means *run in the main R process (not a distributed crew worker)* — it has no connection to the git branch.

**Fix:**

1. Update the comment block near the upload targets in `_targets.R`:
   ```r
   # deployment = "main" means: run in the main R process, not a distributed crew worker.
   # To restrict uploads to the main git branch only, add a conditional inside the target:
   #   if (Sys.getenv("GITHUB_REF") != "refs/heads/main") return(invisible(NULL))
   ```
2. If true branch-gating is desired (uploads only on `main`), add that guard inside each upload target body or use a CI `if: github.ref == 'refs/heads/main'` condition on the run step.

---

## Step 10 🟡 P2 — Parameterize start dates and fix global STAC bbox

**Problem (ARCHITECTURE.md §CQ-6, CQ-8):**
- `modis_start_date`, `viirs_start_date`, `burn_start_date` are all hard-coded to `"2026-03-01"` — a narrow recent window. The prior full-history dates are commented out. This should be environment-variable driven so CI can use a different window than local runs.
- STAC `bbox` / `geometry` use global `(-180,-90,180,90)` for a regional dataset (Cape Floristic Region, approx. `[17,-35,33,-28]`).

**Fix:**

1. In `_targets.R`:
   ```r
   modis_start_date <- Sys.getenv("MODIS_START_DATE", unset = "2000-02-18")
   viirs_start_date <- Sys.getenv("VIIRS_START_DATE", unset = "2012-01-01")
   burn_start_date  <- Sys.getenv("BURN_START_DATE",  unset = "2000-11-01")
   ```
   For CI cost control, set `MODIS_START_DATE` as a GitHub Actions variable to a recent date.

2. In `R/stac_functions.R`, derive bbox from the actual domain (pass it in or compute from `domain.tif`):
   ```r
   # Cape Floristic Region approximate bbox
   DOMAIN_BBOX <- c(17.0, -35.0, 33.0, -28.0)
   ```
   Use this in all `generate_*_stac()` functions for both `bbox` and `geometry.coordinates`.

---

## Step 11 🟡 P2 — CI dependency management and action pinning

**Problem (ARCHITECTURE.md §CQ-11, CQ-12):**

- Package installation via `questionr::qscan()` is non-standard. If a new package is added to an R file but not `DESCRIPTION`, it installs silently in CI but fails locally (or vice versa).
- `actions/checkout@v2` is outdated; `actions/upload-artifact@main` is unpinned.

**Fix:**

1. Standardize on `DESCRIPTION` as the package manifest. Remove `questionr::qscan()` and replace with:
   ```yaml
   - name: Install R Package Dependencies
     run: Rscript -e "pak::pak()"
   ```
   (assuming `pak` is available in the Docker image, which can be verified and added).

2. Pin all actions to specific versions with SHA digests or at minimum semver tags:
   ```yaml
   - uses: actions/checkout@v4
   - uses: actions/upload-artifact@v4
   ```

---

## Step 12 🟢 P3 — Performance: reduce upload verification sleep and serialise smarter

**Problem (ARCHITECTURE.md §P-1, P-2):**

1. `upload_to_github_release()` always waits up to 275 s verifying uploads, even for tiny JSON files.
2. `tar_upload_github_release()` uploads `_targets/objects/` serially.

**Fix:**

1. Make the verification polling adaptive — skip it entirely for files < 1 MB (GitHub indexes them near-instantly) and only poll for large files:
   ```r
   needs_verification <- file.size(uploaded) > 1e6
   if (any(needs_verification)) {
     # existing retry loop, but only for large files
   }
   ```

2. For `tar_upload_github_release()`, use `parallel::mclapply()` or `future.apply::future_lapply()` with a small worker count (e.g., 4) to upload objects concurrently:
   ```r
   parallel::mclapply(local_files, upload_one, mc.cores = 4L)
   ```
   Note: GitHub API allows concurrent uploads to the same release; asset names must still be unique.

---

## Step 13 🟢 P3 — Security: scope agent write access and add asset checksums

**Problem (ARCHITECTURE.md §S-1, S-4):**

1. The `@github-copilot-agent` auto-fix PR can commit code with full `contents: write` access.
2. Uploaded release assets have no integrity check (no SHA-256 manifest).

**Fixes:**

1. Scope the failure-PR step: add a check so it only runs on scheduled runs or `main` branch pushes, not every push on every branch:
   ```yaml
   - name: Create review PR on failure
     if: failure() && github.event_name == 'schedule'
   ```
   Remove the `@github-copilot-agent` auto-commit instruction; keep only the PR creation for human review.

2. Add a checksum manifest: after all uploads in `upload_to_github_release()`, compute SHA-256 for each uploaded file and write a `SHA256SUMS.txt` sidecar to the same release. This allows downstream users to verify data integrity:
   ```r
   sha_lines <- vapply(uploaded, function(f)
     paste(digest::digest(f, algo = "sha256", file = TRUE), basename(f)),
     character(1))
   writeLines(sha_lines, tmp_sha <- tempfile(fileext = ".txt"))
   .gh_upload_release_asset(tmp_sha, repo, paste0(release_tag, "-checksums"), ...)
   ```

---

## Summary Table

| Step | Priority | File(s) | Root cause addressed |
|------|----------|---------|----------------------|
| 1 | 🔴 P0 | `R/stac_functions.R` | Burn STAC: `.nc`→`.tif` filter mismatch |
| 2 | 🔴 P0 | `R/stac_functions.R`, `_targets.R` | VI catalog child-link filename mismatch |
| 3 | 🔴 P0 | `_targets.R` | Phantom `fire_history` catalog entry |
| 4 | 🔴 P0 | `_targets.R` | Missing catalog→collection `targets` deps |
| 5 | 🔴 P0 | `.github/workflows/targets.yaml` | CI branch/ref drift |
| 6 | 🟠 P1 | `_targets.R`, `R/stac_functions.R`, `R/get_*.R` | Tag string duplication / no single source of truth |
| 7 | 🟠 P1 | `R/upload_releases.R`, `_targets.R` | Unreliable STAC JSON publication to release |
| 8 | 🟠 P1 | `R/validate_stac.R` *(new)*, `_targets.R` | No post-publish link validation |
| 9 | 🟡 P2 | `_targets.R` | Misleading `deployment="main"` comments |
| 10 | 🟡 P2 | `_targets.R`, `R/stac_functions.R` | Hard-coded dates and wrong global bbox |
| 11 | 🟡 P2 | `.github/workflows/targets.yaml` | Fragile package install and unpinned actions |
| 12 | 🟢 P3 | `R/upload_releases.R`, `R/tar_release_storage.R` | Upload performance |
| 13 | 🟢 P3 | `.github/workflows/targets.yaml`, `R/upload_releases.R` | Agent access scope + asset checksums |

---

## Implementation Order

Execute **Steps 1–5** in a single commit/PR — they fix the broken STAC output that exists today and restore CI for the active branch. All five are small, localised changes.

Then execute **Steps 6–8** together in a follow-on PR — they prevent the same class of bugs from recurring by introducing a single tag config, improving publication reliability, and adding automated validation.

**Steps 9–13** can be done incrementally as time permits.
