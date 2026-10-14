# Park products → `static_data`

## Contract

| Role | Tag | Assets |
|------|-----|--------|
| Inputs | [`manual-data`](https://github.com/eco-emma/emma_envdata/releases/tag/manual-data) | Flat SACAD / SAPAD / CapeNature shapefile sidecars (**by name**, no nested folders) |
| Outputs | `static_data` | `protected_areas.gpkg`, `domain_outline.gpkg`, `parks_buffer_10km.gpkg` |

Ecological rules (parity with emma_report, settled AOI):

- SACAD/SAPAD: `SITE_TYPE` matches “national park” (case-insensitive)
- CapeNature: `COMPLEX` → `name`, `RESERVECON` → `type`, `WMCM_TYPE = Provincial`
- Intersect domain; dissolve by **`name` only**; attrs `name`, `type`, `area_ha`
- CRS = **EPSG:9221**
- `parks_buffer_10km.gpkg` = 10 km buffer of parks **only** (no domain union)
- **Do not** ship `park_pids.parquet` in v1

## First publish = CCR (required)

Nightly Actions remains **AppEEARS-only**. After this branch merges to `main`, Adam
primes park products on CCR:

```bash
# 1. SSH + interactive (or sbatch) node
ssh vortex.ccr.buffalo.edu
salloc --cluster=faculty --qos=adamw --partition=adamw \
  --job-name=emma_parks --nodes=1 --ntasks=4 --mem=24G \
  -C INTEL --time=04:00:00

# 2. Enter Apptainer shell (repo root)
cd /projects/academic/adamw/projects/emma/emma_envdata
git fetch origin && git checkout main && git pull --ff-only
bash R/ccr_startup.sh shell

# 3. Inside the Apptainer shell at the repo root — build + upload to static_data
Rscript R/publish_park_static.R

# Equivalent targets path (uses local domain.tif from the CCR store):
# R -e 'targets::tar_make(c(park_static_products, upload_park_static))'
```

Verify:

```bash
gh release view static_data --repo eco-emma/emma_envdata \
  --json assets --jq '.assets[].name' | grep -E 'protected_areas|domain_outline|parks_buffer'
```

## Optional later: GitHub Actions

Workflow [`.github/workflows/publish-parks.yaml`](../.github/workflows/publish-parks.yaml)
is **`workflow_dispatch` only**. It downloads `domain.tif` from `static_data` and
flat park shapefiles from `manual-data`, then uploads the three gpkgs. Use when
CCR is unavailable — **not** the first-publish path.
