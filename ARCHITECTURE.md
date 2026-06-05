# EMMA Environmental Data Pipeline — Architecture Overview

> Branch: `dev-adam-appeears-cog`  
> Last reviewed: June 2026

---

## 1. High-Level Purpose

This repository is an R [`targets`](https://docs.ropensci.org/targets/) pipeline that:

1. Downloads multi-sensor satellite and environmental datasets (MODIS, VIIRS, CHELSA, SoilGrids, etc.) for the EMMA project domain (Cape Floristic Region / South Africa).
2. Reprojects and aligns all rasters to a 500 m domain grid as Cloud-Optimized GeoTIFFs (COGs) and GeoParquet tables.
3. Publishes processed data as named GitHub Release assets.
4. Generates a [STAC](https://stacspec.org/) catalog whose item asset HREFs point to those Release URLs.
5. Runs automatically in CI (GitHub Actions) on a weekly schedule.

---

## 2. Module Map

### 2.1 Pipeline Orchestration

| File | Role |
|------|------|
| `_targets.R` | Defines the full `targets` DAG — all targets, their dependencies, format, cue, and deployment settings. Also sets global options (terra, geotargets, cleanup, date ranges, release config). |
| `_targets_packages.R` | (helper) package loading shim used by `tar_source()`. |
| `run_tar_make.sh` / `ccr_startup.sh` | Shell wrappers for running the pipeline on a local HPC (CCR Buffalo). |
| `run.R` | Minimal entry-point that calls `tar_make()` for convenience. |

### 2.2 Domain Definition (static, `cue="never"`)

| File | Target(s) | Output |
|------|-----------|--------|
| `R/get_country.R` | `country` | `sf` country boundary polygon |
| `R/get_vegmap.R` | `vegmap` | NVM2024 vegetation map shapefile |
| `R/get_remnants.R` | `remnants` | RLE 2021 remnants polygon |
| `R/domain_define.R` | `domain_boundary` | Intersected domain envelope (`sf`) |
| `R/domain_rasterize.R` | `domain.tif` | 500 m raster with pixel IDs + remnant distance |
| `R/domain_to_geoparquet.R` | `domain_geoparquet` | `data/target_outputs/domain.parquet` |
| `R/domain_bbox.R` | helper | Bounding-box extraction utility |

### 2.3 Static Environmental Layers (static, `cue="never"`)

| File | Target(s) | Source | Output |
|------|-----------|--------|--------|
| `R/get_elevation.R` | `elevation_task_id`, `elevation.tif` | NASA AppEEARS / NASADEM | 500 m COG GeoTIFF |
| `R/get_climate_chelsa.R` | `climate_chelsa` | CHELSA v2.1 REST | 19 BIO NetCDF files |
| `R/get_clouds_wilson.R` | `clouds.tif` | EarthEnv MODCF | 500 m COG GeoTIFF |
| `R/get_soilgrid.R` | `soils.tif` | ISRIC SoilGrids v2 REST | 500 m COG GeoTIFF |
| `R/process_topographic_diversity.R` | `geodiversity.tif` | Derived from elevation | 500 m COG GeoTIFF |
| `R/process_vegmap.R` | `vegmap.tif` | Rasterised NVM2024 | 500 m COG GeoTIFF |
| `R/combine_static_layers_to_geoparquet.R` | `static_geoparquet` | All static layers | `static_covariates.parquet` |

### 2.4 Dynamic Vegetation Index Pipeline (MODIS + VIIRS, branched)

```
vi_modis_pending (date sequence)
    → vi_modis_task_ids    (AppEEARS task submission, one per 16-day composite)
    → vi_modis_geotiff     (download raw GeoTIFFs, error="continue")
    → vi_modis_grid        (reproject to domain COG, format="file")
    → vi_modis_parquet     (extract to parquet, format="file")

vi_viirs_pending (date sequence)
    → vi_viirs_task_ids
    → vi_viirs_geotiff
    → vi_viirs_grid
    → vi_viirs_parquet
```

| File | Implements |
|------|-----------|
| `R/get_modis_vi.R` | Task submission + idempotency check against release |
| `R/get_viirs_vi.R` | Same for VIIRS (S-NPP + NOAA-20) |

### 2.5 Burned Area Pipeline (MODIS MCD64A1 + VIIRS VNP64A1, branched)

```
burn_modis_pending / burn_viirs_pending (monthly date sequences)
    → burn_*_task_ids
    → burn_*_geotiff   (error="continue")
    → burn_*_grid      (domain-aligned COG, format="file")
    → burn_*_parquet   (format="file")

burn_events_merged    ← merge_burn_dates()  (all monthly parquets)
most_recent_burn      ← compute_most_recent_burn()
recentburn.tif        ← most_recent_burn_to_grid()
```

| File | Implements |
|------|-----------|
| `R/get_burn_dates_modis.R` | MODIS task submission + idempotency check |
| `R/get_burn_dates_viirs.R` | VIIRS task submission + idempotency check |
| `R/process_burn_dates.R` | Merging, most-recent-burn derivation, rasterisation |

### 2.6 GitHub Release Storage

| File | Role |
|------|------|
| `R/upload_releases.R` | `upload_to_github_release()` — creates/updates a release, skips existing assets, retries, verifies. Uses `gh` + `httr` directly (avoids `piggyback` API incompatibilities). |
| `R/tar_release_storage.R` | `tar_upload_github_release()` / `tar_download_github_release()` — upload/restore the targets **cache** (metadata + serialised objects) to the `targets-cache` release. `gh_release_has_asset()` — session-cached idempotency check used by task-submission functions. |

### 2.7 STAC Catalog Generation

| File | Function | Writes |
|------|----------|--------|
| `R/stac_functions.R` | `generate_modis_vi_stac()` | `data/stac/modis_vi/vi_collection.json` + per-date item JSONs |
| | `generate_burn_stac()` | `data/stac/burn/burn_collection.json` + per-month item JSONs + `burn_recentburn.json` |
| | `generate_static_layers_stac()` | `data/stac/static/static_collection.json` + per-layer item JSONs |
| | `generate_emma_stac_catalog()` | `data/stac/catalog.json` |
| | `generate_burn_dates_stac()` | (unused in current pipeline; legacy parquet-focused STAC) |

### 2.8 Utilities

| File | Role |
|------|------|
| `R/utils.R` | `%||%`, `load_description_packages()`, misc helpers |
| `R/robust_download_file.R` | Retrying file downloader |
| `R/appeears_auth.R` | AppEEARS token management |
| `R/generate_release_manifest.R` | Writes `TARGET_MANIFEST.json` from `tar_meta()` |

### 2.9 CI

| File | Role |
|------|------|
| `.github/workflows/targets.yaml` | Weekly cron + push trigger; runs pipeline in `adamwilsonlab/emma:latest` Docker container; uploads targets cache; creates review PR on failure. |

---

## 3. Data Flow Summary

```
External APIs          Local Processing       GitHub Releases       STAC Catalog
──────────────         ────────────────       ───────────────       ────────────
AppEEARS  ──→  raw GeoTIFFs  ──→  domain-aligned COGs  ──→  vi_modis_dynamic_raster
CHELSA    ──→  NetCDF BIOs   ──→  static parquet       ──→  static_data
SoilGrids ──→  REST tiles    ──→  soils.tif             ──→  burn_dates_modis_raster
                               burn COGs                ──→  burn_dates_viirs_raster
                               recentburn.tif            ──→  firehistory_dynamic
                               *.parquet               ──→  vi_modis_dynamic
                                                        ──→  burndate_modis_dynamic
                                                        ──→  stac  ←── STAC JSONs
                                                        ──→  targets-cache
```

---

## 4. Release Tag ↔ STAC Tag Mapping

| Pipeline release tag | Upload target | STAC generator that references it |
|---|---|---|
| `static_data` | `upload_static` | `generate_static_layers_stac()` |
| `vi_modis_dynamic_raster` | `upload_vi_modis_grid` | `generate_modis_vi_stac()` (MODIS assets) |
| `vi_viirs_dynamic_raster` | `upload_vi_viirs_grid` | `generate_modis_vi_stac()` (VIIRS assets) |
| `vi_modis_dynamic` | `upload_vi_modis` | *(no STAC items — parquet only)* |
| `burn_dates_modis_raster` | `upload_burn_modis_grid` | `generate_burn_stac()` |
| `burn_dates_viirs_raster` | `upload_burn_viirs_grid` | `generate_burn_stac()` |
| `firehistory_dynamic` | `upload_fire_history` | `generate_burn_stac()` (recentburn item) |
| `burndate_modis_dynamic` | `upload_burn_modis` | *(no STAC items — parquet only)* |
| `burndate_viirs_dynamic` | `upload_burn_viirs_data` | *(no STAC items — parquet only)* |
| `stac` | `upload_stac_catalog` | *(is the STAC release itself)* |
| `targets-cache` | CI step / manual | *(pipeline cache, not data)* |

---

## 5. Key Design Issues / Risks

### 5.1 Burn STAC Extension Mismatch (Broken Asset Links) — **CRITICAL**
`generate_burn_stac()` filters input files with `filter_nc()` (regex `\.nc$`) and emits assets typed `application/x-netcdf`. But the actual `burn_modis_grid` / `burn_viirs_grid` targets produce **`.tif` COGs** (consistent with the upload targets, skip-checks in `get_burn_dates_modis.R`, and the `upload_burn_*_grid` targets which match `\.skip$` but otherwise pass `.tif` paths). Result: the burn collection contains zero monthly items and all burn asset HREFs are constructed with wrong filenames.

### 5.2 Catalog → Collection Filename Mismatch (Broken Child Links) — **CRITICAL**
`generate_emma_stac_catalog()` looks for `{dataset_name}_collection.json` for each key in `dataset_collections`. The key `modis_vi` → `data/stac/modis_vi/modis_vi_collection.json`. But `generate_modis_vi_stac()` writes `vi_collection.json` (not `modis_vi_collection.json`). Same for burn (`burn_collection.json` ✓ matches key `burn`), and static (`static_collection.json` ✓ matches key `static`). Only the VI collection silently drops out of the catalog.

### 5.3 Phantom `fire_history` Collection — **HIGH**
The `dataset_collections` list in `_targets.R` passes `fire_history = "data/stac/fire_history"` to `generate_emma_stac_catalog()`. No target generates a collection JSON at that path. `file.exists()` returns FALSE → warning is issued but catalog link is skipped silently, leaving a dangling reference that will confuse STAC consumers.

### 5.4 Missing Dependency: Catalog Can Run Before Collections — **HIGH**
`emma_stac_catalog` only has a data dependency on no collection targets — it uses `file.exists()` to discover collections at runtime. Because `targets` doesn't see explicit deps on `vi_stac`, `burn_stac`, `static_stac`, the catalog can build before any/all of them complete, writing an empty or partial `catalog.json`. The explicit deps exist only on `upload_stac_catalog`, not on the catalog generation itself.

### 5.5 STAC Not Published Atomically — **HIGH**
If `upload_stac_catalog` fails mid-way, the `stac` release can contain a mix of old collection JSONs and new item JSONs (or vice versa), resulting in broken STAC hrefs. There is no transactional upload or rollback.

### 5.6 No Post-Publish Link Validation — **MEDIUM**
After STAC upload, no step verifies that asset HREFs in item JSONs actually resolve. A wrong release tag, a failed upload, or a filename mismatch silently produces a published but broken STAC catalog.

### 5.7 `deployment = "main"` Misinterpretation — **MEDIUM**
Code comments say upload/STAC targets "only run on the main branch." In `targets`, `deployment = "main"` means *run in the main R process, not a distributed crew worker*. It has no relationship to the git branch. All upload targets run on every CI trigger regardless of branch.

### 5.8 CI Branch/Ref Drift — **HIGH**
The workflow (`targets.yaml`) hard-codes `ref: dev-adam-appeears` in `actions/checkout` and lists `dev-adam-appeears`/`dev-jiyeon`/`main` as push triggers. The current active branch is `dev-adam-appeears-cog`, which is neither in the trigger list nor the checkout ref. CI does not run for this branch.

---

## 6. Code Quality Issues

| # | Location | Issue |
|---|----------|-------|
| CQ-1 | `R/stac_functions.R:621` | `filter_nc()` hard-codes `\.nc$` — wrong extension now that outputs are `.tif`. |
| CQ-2 | `R/stac_functions.R:164` | `vi_collection.json` name doesn't match the catalog's expected `modis_vi_collection.json`. |
| CQ-3 | `_targets.R:797-808` | `dataset_collections` includes `fire_history` which has no corresponding generator; dead key. |
| CQ-4 | `_targets.R:793-808` | `emma_stac_catalog` missing explicit `tar_dep()` / `force()` on `vi_stac`, `burn_stac`, `static_stac`. |
| CQ-5 | `R/upload_releases.R:142-153` | Uses `piggyback::pb_new_release()` to create releases (despite bypassing piggyback elsewhere due to API incompatibilities). |
| CQ-6 | `_targets.R:90-95` | `modis_start_date` / `viirs_start_date` / `burn_start_date` are all `"2026-03-01"` — hard-coded future/narrow window. These should be parameters or environment variables. |
| CQ-7 | Multiple `get_*.R` | Release tag strings are duplicated: defined in `_targets.R` and also hard-coded in STAC generators. No single source of truth. |
| CQ-8 | `R/stac_functions.R:228-229` | STAC `bbox` and `geometry` use global `(-180,-90,180,90)` for a regional South African dataset — incorrect. |
| CQ-9 | `R/generate_release_manifest.R:16` | `tar_meta()` called with no `store` argument — will fail if working dir is not the project root at call time. |
| CQ-10 | `_targets.R:50` | `source('R/tar_release_storage.R')` is called in `_targets.R` body (not inside a target), so it re-sources on every parse — side effects possible. |
| CQ-11 | `.github/workflows/targets.yaml:66` | `questionr::qscan()` to install packages is non-standard and fragile; no lockfile is used. |
| CQ-12 | `.github/workflows/targets.yaml:58` | `actions/checkout@v2` is outdated (v4 current); `actions/upload-artifact@main` pins to unstable `main`. |

---

## 7. Performance Issues

| # | Issue | Impact |
|---|-------|--------|
| P-1 | `upload_to_github_release()` performs a `Sys.sleep(attempt * 5)` verification loop (up to 275 s) for *every* upload call, including small static files that complete instantly. | Adds minutes of wall time per CI run. |
| P-2 | `tar_upload_github_release()` uploads every object in `_targets/objects/` serially; no parallelism. For a full run with hundreds of monthly parquets this is extremely slow. | CI upload step dominates run time. |
| P-3 | `gh_release_has_asset()` is session-cached per release tag but the cache is populated on first call only — if assets are added during the same session, the cache goes stale. | Can cause unnecessary re-submissions. |
| P-4 | `_targets.R` uses `memory = "transient"` + `garbage_collection = TRUE` globally — correct for large rasters, but some small non-raster targets (e.g. `vi_modis_pending`, `release_manifest`) pay unnecessary GC overhead. | Minor. |
| P-5 | CHELSA BIO download (`get_climate_chelsa`) downloads 19 files sequentially, each > 100 MB. No parallelism or resume capability on partial failure. | Long download on first run. |

---

## 8. Security Concerns

| # | Issue | Severity |
|---|-------|----------|
| S-1 | `GITHUB_TOKEN` has `contents: write` scope globally. The auto-failure PR step commits code and requests `@github-copilot-agent` to "fix issues" automatically — an external agent with write access on failure. | Medium — supply-chain risk if agent PR is merged without review. |
| S-2 | `EARTHDATA_USER` / `EARTHDATA_PASSWORD` stored as plain GitHub Secrets are passed to the container as env vars, which are visible to any code running in the job. No per-step scoping. | Low (standard practice, but note the risk). |
| S-3 | `gh auth token` is retrieved via `system()` call in `upload_releases.R` — could be captured by any code running in the same process. | Low. |
| S-4 | The pipeline writes data directly to GitHub Releases (public assets) from CI without any checksum/signature of the uploaded files. A compromised token could silently replace a release asset. | Low–Medium. |
