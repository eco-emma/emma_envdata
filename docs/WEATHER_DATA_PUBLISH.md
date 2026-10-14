# Weather (GSOD) + stations → `weather_data`

## Contract

| Role | Tag | Assets |
|------|-----|--------|
| Input parks | [`static_data`](https://github.com/eco-emma/emma_envdata/releases/tag/static_data) | `protected_areas.gpkg` (from parks Phase B / E1–E2) |
| Outputs | `weather_data` | `weather.parquet`, `stations.gpkg` |

Ecological / harvest rules (plan §0.1 + E3 assignment):

- Stations: country **SOUTH AFRICA**; recent `END` year (≥ previous calendar year); within **100 km** of dissolved parks (`st_buffer(dist = 100000)` then filter)
- GSOD years: **last 5 calendar years** by default (override with `WEATHER_MIN_YEAR`, e.g. `1970` for full history)
- `weather.parquet` columns: `STNID`, `YEARMODA`, `TEMP` (°C), `PRCP` (mm), `NAME`
- `stations.gpkg`: `STNID`, `NAME`, begin/end fields, `LON`/`LAT`, geometry **WGS84**

**Prerequisite:** parks `protected_areas.gpkg` must exist on `static_data` (CCR-prime [PR #31](https://github.com/eco-emma/emma_envdata/pull/31) first), or set `WEATHER_PARKS_GPKG` to a local copy.

## First publish = CCR (required)

Nightly Actions remains **AppEEARS-only**. After this branch merges to `main` **and** parks are on `static_data`, Adam primes weather on CCR:

```bash
# 1. SSH + interactive (or sbatch) node
ssh vortex.ccr.buffalo.edu
salloc --cluster=faculty --qos=adamw --partition=adamw \
  --job-name=emma_weather --nodes=1 --ntasks=4 --mem=16G \
  -C INTEL --time=04:00:00

# 2. Enter Apptainer shell (repo root)
cd /projects/academic/adamw/projects/emma/emma_envdata
git fetch origin && git checkout main && git pull --ff-only
bash R/ccr_startup.sh shell

# 3. Inside the Apptainer shell at the repo root — build + upload to weather_data
Rscript R/publish_weather.R

# Optional local parks override (if static_data parks not yet public):
# WEATHER_PARKS_GPKG=/path/to/protected_areas.gpkg Rscript R/publish_weather.R

# Dry-run without upload:
# Rscript R/publish_weather.R --no-upload
```

Verify:

```bash
gh release view weather_data --repo eco-emma/emma_envdata \
  --json assets --jq '.assets[].name' \
  | grep -E '^(weather\.parquet|stations\.gpkg)$'
```

## Optional later: GitHub Actions

Workflow [`.github/workflows/publish-weather.yaml`](../.github/workflows/publish-weather.yaml)
is **`workflow_dispatch` only** (later: attach to midnight cron as its **own** job —
never on the AppEEARS job).

Actions → **publish-weather** → Run workflow (`upload: true`). Downloads
`protected_areas.gpkg` from `static_data`, harvests GSOD, uploads
`weather.parquet` + `stations.gpkg` to `weather_data`.

Optional `min_year` input overrides the default last-5-years window.
