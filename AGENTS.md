# EMMA Environmental Data Pipeline — Agent Reference

## Project Overview

**EMMA** (*Environmental Monitoring and Modelling for Africa*) assembles a suite of environmental datasets (vegetation indices, burn dates, elevation, climate, soils, clouds) over a defined spatial domain (South Africa / Greater Cape Floristic Region) into a consistent grid for downstream ecological modelling.

The pipeline:
1. Downloads source data from NASA AppEEARS, CHELSA, EarthEnv, ISRIC SoilGrids, and manual sources.
2. Projects everything onto a common 500 m domain raster.
3. Outputs `.nc` (static layers) and `.parquet` (dynamic monthly time series) files.
4. Uploads outputs to GitHub Releases for distribution and caches intermediate R objects there for CI reuse.
5. Generates a STAC catalog for dataset discovery.

**Repository**: `AdamWilsonLab/emma_envdata`  
**Primary branch**: `main`; active development on `dev-adam-appeears`  
**Docker image**: `adamwilsonlab/emma:latest`

---

## Coding Style Rules

These are strict preferences — follow them for all new or modified R code.

- **Tidyverse first**: use `dplyr`, `tidyr`, `purrr`, `stringr`, `lubridate`, `ggplot2`. Import with `library()` (packages listed in `DESCRIPTION`).
- **No `for` loops**: use `purrr::map*()`, `lapply()`, or vectorised operations instead.
- **Pipes**: use the base `|>` pipe (R ≥ 4.1). Avoid `%>%` unless in legacy code.
- **Indentation**: 2 spaces. Max line width: 80 characters (tidyverse style).
- **No `print()`**: use `message()` for progress/status output.
- **Function naming**: `verb_noun` snake_case (e.g. `get_elevation()`, `process_vegmap()`). File names match the primary function name.
- **Avoid class-based OOP** (R5/R6/S4). Keep functions as plain functions.
- **Human-readable over clever**: prefer explicit, named arguments over positional; prefer readable intermediate variables over chained one-liners.
- **No global state mutations** inside functions (except writing output files). Functions should be pure where practical.
- **Linting**: `lintr` with `tidyverse_style()`. Run `Rscript scripts/agents/tidyverse_check.R` to check. Add `--fix` to auto-format with `styler`.

---

## Technology Stack

| Layer | Tool |
|---|---|
| Pipeline orchestration | `targets` + `tarchetypes` + `geotargets` |
| Raster processing | `terra` (not `raster`) |
| Vector / spatial | `sf` |
| Tabular data | `dplyr`, `tidyr`, `arrow` (parquet) |
| AppEEARS API | `appeears` package |
| GitHub Releases I/O | `piggyback` |
| Serialization | `qs2` (`.qs` objects, fast binary) |
| Output format (tabular) | Apache Parquet with gzip codec (`arrow`) |
| Output format (raster) | NetCDF4 CF-1.8 (`.nc`) via `terra::writeCDF()` |
| STAC catalog | custom functions in `R/generate_stac.R` |
| Auth (NASA EarthData) | env vars `EARTHDATA_USER` / `EARTHDATA_PASSWORD` |

---

## Directory Structure

```
_targets.R              # Pipeline definition (single source of truth)
R/                      # All R functions (one file per logical group)
data/
  manual_download/      # Hand-downloaded shapefiles — never auto-deleted
  temp/
    appeears/           # Ephemeral AppEEARS NetCDF downloads (per-dataset subdirs)
    terra/              # terra scratch tiles
  target_outputs/       # Final pipeline outputs (NC + parquet files)
  stac/                 # STAC JSON catalog files
_targets/
  objects/              # targets local object store (qs files, no extension)
  cache/                # Local mirror of GitHub Release objects_current (speed cache)
  workspaces/           # targets file-format target store
docs/                   # Setup guides (APPEEARS_SETUP.md)
agents/                 # Agent definitions (.agent.md files)
scripts/agents/         # Runnable agent R scripts
```

**Directories that are NOT created by the pipeline** (do not reference them):
- `data/raw/` — removed; ephemeral downloads go to `data/temp/appeears/`
- `data/releases/` — removed; GitHub Releases replaced local release storage
- `data/processed_data/` — old GEE-era path, gone

---

## Pipeline Architecture

### targets Framework

- `_targets.R` defines the DAG. All function calls go in `tar_target()` blocks.
- `tar_option_set(format = "qs", repository = "local")` — objects are stored locally as `.qs`; the custom hooks sync to/from GitHub Releases.
- `tar_hook_before()` calls `tar_download_github_release()` to restore cached objects at pipeline start.
- `tar_hook_after(condition = "success")` calls `tar_upload_github_release()` to push new objects after success.
- To invalidate a target and force recomputation: `targets::tar_invalidate(target_name)`.
- Dynamic branching with `pattern = map(...)` is used for all monthly time-series targets.

### AppEEARS Two-Step Pattern

All AppEEARS datasets follow this pattern (separate targets for resilience):
1. `submit_*_task()` — submits the API job, returns a task ID string.
2. `download_*_results()` or `download_*_netcdf()` — polls for completion, downloads NetCDF, reprojects to domain grid, writes output file.

Temp NetCDF files land in `data/temp/appeears/{dataset}/` and are removed after processing when `cleanup_mode = TRUE` (set automatically on GitHub Actions).

### Dynamic Monthly Targets (MODIS VI, Burn Dates)

Pattern for each dataset:
1. `identify_missing_*()` — scans `data/target_outputs/{dataset}/` for existing files; returns a data frame of missing months.
2. `submit_*_task()` — branched by `pattern = map(to_download)`.
3. `download_*_netcdf()` — branched by `pattern = map(task_ids, to_download)`.
4. `*_netcdf_to_parquet()` — processes NetCDF → `.parquet`; branched; `format = "file"`.
5. `generate_*_stac()` — generates STAC collection JSON.

### Output Formats

| Data type | Format | Location |
|---|---|---|
| Monthly tabular time series | `.parquet` (gzip codec) | `data/target_outputs/{dataset}/YYYY-MM.parquet` |
| Static rasters | `.nc` (CF-1.8 NetCDF4) | `data/target_outputs/{name}.nc` |
| Domain grid | `.nc` + `.parquet` (GeoParquet) | `data/target_outputs/domain.*` |
| STAC catalog | `.json` | `data/stac/` |

**Important**: parquet files use internal gzip compression (`compression = "gzip"` in `arrow::write_parquet()`). The filenames do **not** include `.gz` — they are plain `.parquet`.

---

## GitHub Release Tags

| Tag | Contents |
|---|---|
| `objects_current` | Cached intermediate targets (`.qs` objects + file-format mirrors) |
| `static_data` | Domain, elevation, climate, clouds, soils, topography NC files |
| `dynamic_modis_vi` | Monthly MODIS VI parquet files |
| `dynamic_burn_dates_modis` | Monthly MODIS MCD64A1 burn date parquets |
| `dynamic_burn_dates_viirs` | Monthly VIIRS VNP64A1 burn date parquets |
| `fire_covariates` | Derived most-recent-burn parquet |
| `vegmap2024` | NVM 2024 vegetation map shapefile |
| `stac` | STAC catalog + collection JSON files |

Upload targets use `deployment = "main"` so they only run on the `main` branch, not feature branches.

---

## Key R Functions by File

| File | Key functions |
|---|---|
| `R/utils.R` | `load_description_packages()` |
| `R/tar_release_storage.R` | `tar_download_github_release()`, `tar_upload_github_release()`, `.check_file_integrity()` |
| `R/upload_releases.R` | `upload_to_github_release()` |
| `R/domain_define.R` | `domain_define()` |
| `R/domain_rasterize.R` | `domain_rasterize()` |
| `R/domain_bbox.R` | `make_domain_bbox()` |
| `R/domain_to_geoparquet.R` | `domain_to_geoparquet()` |
| `R/get_vegmap.R` | `get_vegmap()` |
| `R/process_vegmap.R` | `process_vegmap()` |
| `R/get_country.R` | `get_country()` |
| `R/get_elevation.R` | `submit_elevation_task()`, `download_elevation_results()` |
| `R/process_topographic_diversity.R` | `process_topographic_diversity()` |
| `R/get_climate_chelsa.R` | `get_climate_chelsa()` |
| `R/get_clouds_wilson.R` | `get_clouds_wilson()` |
| `R/get_soil_soilgrids.R` | `get_soil_soilgrids()` |
| `R/get_modis_vi.R` | `submit_modis_vi()`, `download_modis_vi_netcdf()`, `netcdf_to_parquet()`, `identify_missing_vi()` |
| `R/get_burn_dates_modis.R` | `submit_burn_date_modis_task()`, `download_burn_date_modis_netcdf()`, `identify_missing_burn_dates_modis()` |
| `R/get_burn_dates_viirs.R` | `submit_burn_date_viirs_task()`, `download_burn_date_viirs_netcdf()`, `identify_missing_burn_dates_viirs()` |
| `R/process_burn_dates.R` | `burn_date_modis_netcdf_to_parquet()`, `burn_date_viirs_netcdf_to_parquet()`, `merge_burn_dates()`, `compute_most_recent_burn()` |
| `R/generate_stac.R` | `generate_modis_vi_stac()`, `generate_burn_dates_stac()`, `generate_emma_stac_catalog()` |
| `R/appeears_auth.R` | AppEEARS authentication helpers |
| `R/robust_download_file.R` | `robust_download_file()` — retry-aware generic downloader |

---

## Spatial Domain

- **Region**: South Africa / Greater Cape Floristic Region
- **Resolution**: ~500 m (MODIS sinusoidal → WGS84 reprojection)
- **CRS**: WGS84 (EPSG:4326) for all outputs
- **Domain raster**: `data/target_outputs/domain.nc` — defines the pixel grid used by everything. Changing this invalidates all downstream targets.
- **Bounding box**: derived from `domain_boundary` with 50 km buffer; used for AppEEARS area-of-interest submissions.

---

## Authentication Setup

### Local Development
Add to `~/.Renviron`:
```
EARTHDATA_USER=your_username
EARTHDATA_PASSWORD=your_password
```
GitHub credentials: `gitcreds::gitcreds_set()`

### GitHub Actions
Add repository secrets: `EARTHDATA_USER`, `EARTHDATA_PASSWORD`.

---

## CI / Agents

Three lightweight agent scripts in `scripts/agents/`:

- `tidyverse_check.R` — runs `lintr`; `--fix` applies `styler`
- `geostat_check.R` — checks CRS consistency, verifies expected directories exist
- `ci_check.R` — runs both, exits non-zero on failure

CI workflow: `.github/workflows/agents-check.yml` runs `ci_check.R` on push/PR to any `.R` file.

---

## Common Pitfalls / Notes

- **Never use `raster` package** — use `terra` only. `raster` is in `Suggests` for legacy compatibility only.
- **`format = "file"` targets return the output file path as a string** — downstream targets receive this path, not the data object.
- **`tar_cue(mode = "never")` on `vegmap`** — this target requires a manual local download; it never runs on CI.
- **`cleanup_mode`** is `TRUE` on GitHub Actions (auto-detected via `GITHUB_ACTIONS` env var) and `FALSE` locally. Pass it as `cleanup = cleanup_mode` to all `get_*` / `download_*` functions.
- **Monthly parquets may have `.skip` suffix** when a month has no valid data — filter with `files[!grepl("\\.skip$", files)]` before uploading.
- **`devtools::load_all()`** at the top of `_targets.R` loads all functions in `R/` — no need to `source()` individual files in the pipeline.
- **Do not add `data/raw/` or `data/releases/`** — these directories no longer exist in the workflow.
- **Cache path is `_targets/cache/`** (not `data/target_outputs/.tar_cache/` which was the old location).
