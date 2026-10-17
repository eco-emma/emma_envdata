# VIIRS VI parquets → `vi_viirs_parquet`

## Contract

| Role | Tag | Assets |
|------|-----|--------|
| Outputs | [`vi_viirs_parquet`](https://github.com/eco-emma/emma_envdata/releases/tag/vi_viirs_parquet) | `vi_viirs_YYYYMMDD.parquet` (one per 16-day composite) |
| Companion rasters | [`vi_viirs_raster`](https://github.com/eco-emma/emma_envdata/releases/tag/vi_viirs_raster) | `vi_viirs_{snpp,noaa20}_YYYYMMDD.tif` COGs |

Local path on CCR: `data/target_outputs/viirs_vi/vi_viirs_*.parquet`.

Report monthly/long-term EVI means fuse VIIRS → Terra → Aqua when this tag
exists; without it, emma_report falls back to **MODIS-only** means.

## Why the tag was 404

1. **CCR `tar_make`**: `_targets.R` had `upload_vi_modis` → `vi_modis_parquet`
   and `upload_vi_viirs_grid` → `vi_viirs_raster`, but **no**
   `upload_vi_viirs` for parquets. Sep 2026 COGs and fireage published; VIIRS
   parquets stayed local only.
2. **GHA (2026-10-15)**: Nightly built `vi_viirs_20260905/20260921.parquet` on
   the runner, then skipped product upload because `todo` listed pattern stems
   while the upload filter only accepted `*_grid_<hex>` names (fixed later in
   [#36](https://github.com/eco-emma/emma_envdata/pull/36)). Those runner files
   were discarded; later nights saw empty pending and never re-uploaded.

GHA cannot reconstruct the full historical parquet archive from release COGs
without re-running `vi_viirs_geotiff_to_parquet` for every composite. Prefer
CCR upload of existing local files.

## One-shot CCR publish (Adam)

After this branch is on `main`:

```bash
ssh vortex.ccr.buffalo.edu
salloc --cluster=faculty --qos=adamw --partition=adamw \
  --job-name=emma_viirs_pq --nodes=1 --ntasks=2 --mem=16G \
  -C INTEL --time=04:00:00

cd /projects/academic/adamw/projects/emma/emma_envdata
git fetch origin && git checkout main && git pull --ff-only
bash R/ccr_startup.sh shell

# Inside Apptainer — creates tag vi_viirs_parquet if missing, uploads all locals
Rscript R/publish_vi_viirs_parquet.R
```

Dry-run count only:

```bash
Rscript R/publish_vi_viirs_parquet.R --dry-run
```

Equivalent targets path (after merge; needs local store + all parquet paths):

```r
targets::tar_make(upload_vi_viirs)
```

Verify:

```bash
gh release view vi_viirs_parquet --repo eco-emma/emma_envdata \
  --json assets --jq '.assets | length'
# Expect hundreds (one per VIIRS composite since ~2012), including:
gh release view vi_viirs_parquet --repo eco-emma/emma_envdata \
  --json assets --jq '.assets[].name' | grep -E 'vi_viirs_202609(05|21)\.parquet'
```

## Ongoing path

- **CCR full `tar_make`**: `upload_vi_viirs` publishes new months (mirrors
  `upload_vi_modis`).
- **Nightly Actions** (`R/ci_appeears_update.R`): already maps
  `vi_viirs_*.parquet` → tag `vi_viirs_parquet` and creates the release on
  first upload; no GHA workflow change required for *new* months.
