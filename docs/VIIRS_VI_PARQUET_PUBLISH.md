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
3. **CCR one-shot publish (2026-10)**: `Rscript R/publish_vi_viirs_parquet.R`
   listed hundreds of `Uploading: vi_viirs_….parquet` lines, then
   `There were 50 or more warnings` and
   `Done. Uploaded/confirmed 0 asset path(s)` while the tag stayed 404.
   Root cause: `upload_to_github_release()` swallowed release-create failures as
   “Using existing release”, caught every upload error as a warning, and
   returned success with zero paths. Fixed: hard-fail on missing token / create
   / upload; `gh` CLI fallback; paginated asset listing.

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

# Preflight (host or inside Apptainer)
ls data/target_outputs/viirs_vi/vi_viirs_*.parquet | wc -l
# Expect hundreds; names like vi_viirs_20120407.parquet … vi_viirs_20260921.parquet
test -n "${GITHUB_PAT:-}" || export GITHUB_PAT="$(gh auth token)"
gh api user -q .login   # must succeed; needs contents:write on eco-emma

bash R/ccr_startup.sh shell

# Inside Apptainer — creates tag vi_viirs_parquet if missing, uploads all locals
# Must end with "Success: all N vi_viirs_*.parquet assets confirmed"
# Must NOT print "Uploaded/confirmed 0" or exit 0 after warnings-only.
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

Verify on GitHub (host, after script exits 0):

```bash
gh release view vi_viirs_parquet --repo eco-emma/emma_envdata
gh release view vi_viirs_parquet --repo eco-emma/emma_envdata \
  --json assets --jq '.assets | length'
# Expect hundreds (one per VIIRS composite since ~2012), including:
gh api repos/eco-emma/emma_envdata/releases/tags/vi_viirs_parquet \
  --jq '.assets[].name' 2>/dev/null | head
# Prefer paginated asset list for full count:
gh api --paginate \
  repos/eco-emma/emma_envdata/releases/$(
    gh api repos/eco-emma/emma_envdata/releases/tags/vi_viirs_parquet -q .id
  )/assets -q '.[].name' | grep -E 'vi_viirs_202609(05|21)\.parquet'
```

Success looks like: release tag `vi_viirs_parquet` exists (not 404), asset
count ≈ local `wc -l`, and Sep 2026 files `vi_viirs_20260905.parquet` /
`vi_viirs_20260921.parquet` are present.

## Ongoing path

- **CCR full `tar_make`**: `upload_vi_viirs` publishes new months (mirrors
  `upload_vi_modis`).
- **Nightly Actions** (`R/ci_appeears_update.R`): already maps
  `vi_viirs_*.parquet` → tag `vi_viirs_parquet` and creates the release on
  first upload; no GHA workflow change required for *new* months.
