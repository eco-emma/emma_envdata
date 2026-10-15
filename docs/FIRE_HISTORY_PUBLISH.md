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

### CCR steps

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

# 3. Inside Apptainer — invalidate cue=never fire inputs, rebuild merge → fireage
R -e '
targets::tar_invalidate(c(
  "capenature_fires", "capenature_burn_events",
  "tmnp_fire_shp", "tmnp_fires", "tmnp_burn_events",
  "burn_events_merged", "most_recent_burn",
  "fireage_parquets", "fireage_current.tif", "upload_fireage"
))
targets::tar_make(c(
  "capenature_burn_events", "tmnp_burn_events",
  "burn_events_merged", "most_recent_burn",
  "fireage_parquets", "fireage_current.tif", "upload_fireage"
))
'
```

If only TMNP changed (CapeNature already current):

```bash
R -e '
targets::tar_invalidate(c(
  "tmnp_fire_shp", "tmnp_fires", "tmnp_burn_events",
  "burn_events_merged", "most_recent_burn",
  "fireage_parquets", "fireage_current.tif", "upload_fireage"
))
targets::tar_make(c(
  "tmnp_burn_events", "burn_events_merged", "most_recent_burn",
  "fireage_parquets", "fireage_current.tif", "upload_fireage"
))
'
```

`compute_fire_state()` rebuilds from scratch when a **new** `fire_source` (e.g. `tmnp`) appears in events — expect a longer first run after TMNP is introduced.

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
