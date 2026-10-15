# Fire history (CapeNature + TMNP) → `fireage`

## Contract

| Role | Tag / path | Assets |
|------|------------|--------|
| CapeNature input | local `data/manual_download/All_fires_23_24_gw/` | Shapefile + `capenature_date_fixes.csv` |
| TMNP input | [`manual-data`](https://github.com/eco-emma/emma_envdata/releases/tag/manual-data) | Flat `tmnp_fire_1962_2021.{shp,shx,dbf,prj}` (**TMNP only** — not full SANParks) |
| Outputs | `fireage` | `fireage_current.tif`, `fireage_*.parquet` |

**Source priority** in `merge_burn_dates()`: CapeNature > TMNP > VIIRS > MODIS.

**Scope:** Other national parks stay MODIS/VIIRS + censored / never-burned. Do not claim SANParks-wide fire history.

### Censor / never-burned semantics (W3.3)

| Field | Known burn | Never burned / unknown |
|-------|------------|------------------------|
| `last_burn_date` | days since 1970-01-01 | `NA` |
| `fire_age_days` | true age in days | `NA` (do **not** invent age 20) |
| `is_censored` | `FALSE` / raster band `0` | `TRUE` / raster band `1` |
| `censor_age_days` (parquet only) | `NA` | lower bound `vi_date − 2000-01-01` for models |

`fireage_current.tif` bands: `fire_age_days`, `last_burn_date`, `is_censored`.

CapeNature `DATE_START` / `DATE_EXTIN` accept **ISO** (`YYYY-MM-DD`) and **`DD/MM/YYYY`**. Keep correcting corrupt rows in `capenature_date_fixes.csv`.

## `cue = "never"` — CCR rebuild required

Targets `capenature_fires`, `capenature_burn_events`, `tmnp_fire_shp`, `tmnp_fires`, and `tmnp_burn_events` use `tar_cue(mode = "never")`. Nightly AppEEARS Actions **does not** rebuild them. When shapefiles or date fixes change, Adam (or CCR operator) must intentionally rebuild and republish `fireage`.

### When to rebuild

- New / updated CapeNature fire shapefile under `data/manual_download/All_fires_23_24_gw/`
- New rows in `data/manual_download/capenature_date_fixes.csv`
- Updated `tmnp_fire_1962_2021.*` uploaded to `manual-data`
- First time after merging TMNP ingest (this branch) so `fire_source=tmnp` lands in published fireage

### Why `tar_make(burn_events_merged)` must NOT be used for this

`burn_events_merged` has explicit `force(burn_modis_parquet)` and `force(burn_viirs_parquet)`.  
`fireage_parquets` has `force(vi_modis_parquet)` and `force(vi_viirs_parquet)`.

So any `tar_make()` that names `burn_events_merged`, `most_recent_burn`, `fireage_parquets`, `fireage_current.tif`, or `upload_fireage` walks the **full AppEEARS burn (and VI) graph**. That is correct for a satellite backfill, and **wrong** for a CapeNature/TMNP republish.

`filter_pending_months()` treats months missing from the GitHub `burn_modis_raster` / `burn_viirs_raster` releases as pending. Those releases are incomplete today; months without a local `data/target_outputs/burndates/burn_modis_YYYYMM.tif` will **submit new AppEEARS tasks**. Local burn/VI products on disk are enough for merge → fireage — do not re-request them.

### CCR steps (safe: no AppEEARS)

```bash
# 1. SSH + interactive (or sbatch) node
ssh vortex.ccr.buffalo.edu
salloc --cluster=faculty --qos=adamw --partition=adamw \
  --job-name=emma_fireage --nodes=1 --ntasks=4 --mem=32G \
  -C INTEL --time=08:00:00

# 2. Enter Apptainer shell (repo root)
cd /projects/academic/adamw/projects/emma/emma_envdata
git fetch origin && git checkout main && git pull --ff-only
bash R/ccr_startup.sh shell

# 3. Inside Apptainer — only cue=never inputs via targets; merge→upload bypasses the AppEEARS graph
R -e '
stopifnot(dir.exists("data/target_outputs/burndates"))
# Prefer existing local satellite burn parquets; do not tar_make burn_* / vi_*
n_modis <- length(list.files("data/target_outputs/burndates", "^burn_modis_.*\\.parquet$"))
n_viirs <- length(list.files("data/target_outputs/burndates", "^burn_viirs_.*\\.parquet$"))
message("Local burn parquets: MODIS=", n_modis, " VIIRS=", n_viirs)
if (n_modis < 10L) {
  stop("Too few local MODIS burn parquets — fix disk products before republish; do not tar_make burn_events_merged")
}

targets::tar_invalidate(c(
  "capenature_fires", "capenature_burn_events",
  "tmnp_fire_shp", "tmnp_fires", "tmnp_burn_events"
))
# ONLY cue=never targets — never burn_events_merged / fireage_* / upload_fireage
targets::tar_make(c("capenature_burn_events", "tmnp_burn_events"))

cn   <- targets::tar_read(capenature_burn_events)
tmnp <- targets::tar_read(tmnp_burn_events)
domain <- targets::tar_read(domain.tif)

merged <- merge_burn_dates(
  burn_dir = "data/target_outputs/burndates/",
  capenature_parquet = cn,
  tmnp_parquet = tmnp,
  verbose = TRUE
)

state_file <- compute_fire_state(
  burn_events = merged,
  state_file  = "data/target_outputs/most_recent_burn_state.parquet",
  verbose     = TRUE
)

# fireage_*.parquet skips existing files — delete so TMNP/censor columns refresh
unlink(list.files("data/target_outputs/fireage",
                  pattern = "^fireage_.*\\.(parquet|skip)$",
                  full.names = TRUE))

fireage_files <- compute_fireage_for_vi(
  modis_vi_dir = "data/target_outputs/modis_vi",
  viirs_vi_dir = "data/target_outputs/viirs_vi",
  state_file   = state_file,
  out_dir      = "data/target_outputs/fireage/",
  verbose      = TRUE
)

rast <- most_recent_burn_to_grid(
  state_file    = state_file,
  domain_raster = domain,
  verbose       = TRUE
)
fireage_tif <- "data/target_outputs/fireage/fireage_current.tif"
dir.create(dirname(fireage_tif), recursive = TRUE, showWarnings = FALSE)
terra::writeRaster(rast, fireage_tif, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE"))

upload_to_github_release(
  files        = c(fireage_tif, fireage_files[!grepl("\\.skip$", fireage_files)]),
  repo         = "eco-emma/emma_envdata",
  release_tag  = "fireage",
  release_name = "Fire Age (snapshot raster + per-VI-date parquets)",
  overwrite    = TRUE,
  verbose      = TRUE
)
'
```

If only TMNP changed (CapeNature already current), invalidate/make only the `tmnp_*` targets, then run the same merge → fireage → upload block (still **do not** `tar_make` `burn_events_merged` / `fireage_*`).

`compute_fire_state()` rebuilds from scratch when a **new** `fire_source` (e.g. `tmnp`) appears in events — expect a longer first run after TMNP is introduced.

### If AppEEARS already started submitting

1. **Ctrl-C** the `tar_make` / R session — safe for targets (interrupted branches stay incomplete).
2. **Cancel** in-flight AppEEARS tasks in the [AppEEARS UI](https://appeears.earthdatacloud.nasa.gov/) (Tasks → select `MODIS_BurnDate_*` / `VIIRS_BurnDate_*` submitted in this session → Delete/Cancel). Already-finished downloads on disk are fine to keep.
3. Resume with the **safe CCR steps** above (function calls, not `tar_make` of merge/fireage).

### Verify

```bash
# TMNP present in a recent fireage parquet
gh release view fireage --repo eco-emma/emma_envdata \
  --json assets --jq '.assets[].name' | grep -E '^fireage_.*\.parquet$' | tail

# fireage_current.tif updated
gh release view fireage --repo eco-emma/emma_envdata \
  --json assets --jq '.assets[] | select(.name=="fireage_current.tif") | {name,updatedAt,size}'
```

On CCR, after rebuild, spot-check:

```r
arrow::read_parquet("data/target_outputs/fireage/fireage_modis_<date>.parquet") |>
  dplyr::count(fire_source, is_censored)
```

Expect `fire_source == "tmnp"` for TMNP park pids with historical burns, and `is_censored == TRUE` where never burned.

## Optional later: GitHub Actions

A `workflow_dispatch` job could mirror parks/weather (download `domain.tif` + shapefiles, rebuild cue=never targets, upload `fireage`). **Not** required for first publish — CCR prime above is the supported path. Nightly AppEEARS cron must stay separate.
