# VI parquet date realign (`vi_modis_parquet` / `vi_viirs_parquet`)

## Problem

Many historical release assets are **misaligned duplicates**:

- Basename month does not match row `date` months (often a Jul–Aug template
  with the filename year rewritten into the epoch dates).
- Hundreds of files share identical EVI `value` fingerprints.

`emma_report` skips these defensively for climatologies. This repo must
**regenerate and replace** bad assets on CCR so the full archive is usable.

## Contract

| Role | Tag | Assets |
|------|-----|--------|
| MODIS VI parquet | [`vi_modis_parquet`](https://github.com/eco-emma/emma_envdata/releases/tag/vi_modis_parquet) | `vi_modis_YYYYMMDD.parquet` |
| VIIRS VI parquet | [`vi_viirs_parquet`](https://github.com/eco-emma/emma_envdata/releases/tag/vi_viirs_parquet) | `vi_viirs_YYYYMMDD.parquet` |

`YYYYMMDD` = 16-day composite **start** (`generate_composite_sequence()`).
Row `date` = per-pixel DOY converted with the filename year.

**Aligned** when either:

- ≥50% of rows fall in the filename calendar month, **or**
- ≥80% of rows fall in `[file_date − 7, file_date + 22]` (month-boundary slack).

## Publish guard (always on)

`upload_vi_modis` / `upload_vi_viirs` and `R/publish_vi_viirs_parquet.R` call
`filter_vi_parquets_for_upload()` before upload:

- **Default:** skip misaligned files (warning).
- **Strict:** `EMMA_VI_PARQUET_STRICT=1` → stop the upload target.

This prevents re-publishing junk after a bad regenerate. It does **not**
remove assets already on the release — use the audit delete path below.

## CCR workflow (Adam)

Prefer the usual Apptainer path (`bash R/ccr_startup.sh shell`), not host R.

```bash
ssh vortex.ccr.buffalo.edu
salloc --cluster=faculty --qos=adamw --partition=adamw \
  --job-name=emma_vi_realign --nodes=1 --ntasks=8 --mem=64G \
  -C INTEL --time=12:00:00

cd /projects/academic/adamw/projects/emma/emma_envdata
git fetch origin && git checkout main && git pull --ff-only
# After this PR merges — until then checkout the PR branch.

test -n "${GITHUB_PAT:-}" || export GITHUB_PAT="$(gh auth token)"
bash R/ccr_startup.sh shell
```

### 1. Audit local store

```bash
Rscript R/audit_vi_parquet_dates.R \
  --out data/target_outputs/vi_parquet_date_audit.csv

# Or via targets:
# R -e 'targets::tar_make(audit_vi_parquet_dates_report)'

wc -l data/target_outputs/vi_parquet_date_audit.csv
# Inspect status counts: ok / misaligned / duplicate_values / …
```

### 2. Delete flagged locals + release assets

Only after inspecting the CSV:

```bash
Rscript R/audit_vi_parquet_dates.R \
  --out data/target_outputs/vi_parquet_date_audit.csv \
  --delete-local --delete-remote
```

`--delete-remote` pages the GitHub assets API (safe for 600+ files).
`--dry-run` (default when no `--delete-*`) only reports.

### 3. Delete bad grid COGs (required after Jul–Aug template)

Build + upload now gate AppEEARS source dates and COG DOY
(`R/vi_geotiff_date_match.R`). **Already published** bad grids must still be
deleted — `filter_pending_composites()` is name-only, so poisoned release
assets never re-queue AppEEARS.

Map flagged parquet basenames → sensor COGs:

| Parquet | Sensor assets | Release tags |
|---------|---------------|--------------|
| `vi_modis_YYYYMMDD.parquet` | `vi_modis_terra_YYYYMMDD.tif`, `vi_modis_aqua_YYYYMMDD.tif` | `vi_modis_terra_raster`, `vi_modis_aqua_raster` |
| `vi_viirs_YYYYMMDD.parquet` | `vi_viirs_snpp_YYYYMMDD.tif`, `vi_viirs_noaa20_YYYYMMDD.tif` | `vi_viirs_raster` |

**Preferred after remote parquet cleanup:** `--from-release-orphans` — list
remaining `vi_*_parquet` dates, then delete any sensor COG on
`vi_modis_*_raster` / `vi_viirs_raster` whose YYYYMMDD is **not** in that set.
Needs neither the 683-flagged CSV nor bad locals (survivor CSV + ~8 local
COGs is the usual post-cleanup state).

```bash
getent hosts api.github.com   # confirm DNS before remote deletes

# Optional: a pre-delete flagged CSV may still exist under another name
ls data/target_outputs/vi_parquet_date_audit*.csv*

# Dry-run → data/target_outputs/vi_grid_cog_delete_plan.csv
Rscript R/delete_vi_grids_from_audit.R --from-release-orphans --dry-run

# Real delete (remote; add --delete-local if any matching locals remain)
Rscript R/delete_vi_grids_from_audit.R --from-release-orphans --delete-remote
```

Other sources (usually unnecessary once remotes are cleaned):

```bash
Rscript R/delete_vi_grids_from_audit.R \
  --from-csv data/target_outputs/vi_parquet_date_audit.csv --dry-run
Rscript R/delete_vi_grids_from_audit.R --from-local-doy --dry-run
```

Plan CSV: `data/target_outputs/vi_grid_cog_delete_plan.csv`.

### 3b. Invalidate `vi_*_pending` (required after release deletes)

`filter_pending_composites()` **does** look at the raster releases (not
parquet) and the date window is full history (`modis_start_date` 2000-01-01 /
`viirs_start_date` 2012-01-01 → ~608 / ~337 composites). Emptying the three
raster releases is **not** enough by itself: `vi_modis_pending` /
`vi_viirs_pending` are ordinary `tar_target`s whose stored value is the old
2-row “only recent dates missing” table. GitHub release mutations are an
external side effect, so `tar_make` **skips** pending and still declares
`[2 branches]`.

After remote COG deletes (on `main` or this branch), invalidate **pending +
grid + parquet only**. Keep `task_ids` / `geotiff` so AppEEARS is not
resubmitted or re-downloaded when those branches still hold real task IDs
and temp TIFs. Grid must be invalidated because `format=rds` stores path
strings and will skip even when COG files are gone.

```bash
# Inside Apptainer
R -e 'targets::tar_invalidate(any_of(c(
  "vi_modis_pending", "vi_viirs_pending",
  "vi_modis_grid", "vi_modis_parquet",
  "vi_viirs_grid", "vi_viirs_parquet"
)))'

# Sanity: pending should print hundreds, not 2
R -e 'targets::tar_make(c("vi_modis_pending","vi_viirs_pending"));
      print(nrow(targets::tar_read(vi_modis_pending)));
      print(nrow(targets::tar_read(vi_viirs_pending)))'
```

Then host: `sbatch --cluster=faculty run_tar_make.sh`. Expect logs like
`vi_modis_* declared [~600 branches]`, not `[2 branches]`.

Caveat: branches stored as `cached:YYYYMMDD` (AppEEARS was skipped because
release/local already had COGs) cannot rebuild content without raw TIFs under
`data/temp/appeears/...` — grid falls through to NA placeholders. Only
invalidate `task_ids`/`geotiff` for dates that truly need a new AppEEARS pull.

If COGs look good, only the parquet step needs a rebuild:

```r
# Force parquet branches for deleted files (example)
targets::tar_invalidate(starts_with("vi_modis_parquet"))
# Prefer invalidating only affected branches when practical.
```

### 4. Regenerate + republish

Full pipeline (AppEEARS may re-submit missing composites — long job):

```bash
# From host (outside shell) — usual CCR batch path:
# SKIP_GH_UPLOAD can stay false; product uploads are inside tar_make.
sbatch --cluster=faculty run_tar_make.sh
```

Or interactive, upload-only after locals are fixed:

```bash
# Inside Apptainer — refuse junk:
export EMMA_VI_PARQUET_STRICT=1
R -e 'targets::tar_make(c("upload_vi_modis", "upload_vi_viirs"))'
```

Replacing assets that still exist remotely with corrected locals:

```r
files <- filter_vi_parquets_for_upload(
  list_release_inventory(
    "data/target_outputs/modis_vi",
    "^vi_modis_[0-9]{8}\\.parquet$"
  )
)
upload_to_github_release(
  files, repo = "eco-emma/emma_envdata",
  release_tag = "vi_modis_parquet",
  release_name = "Dynamic MODIS Vegetation Index",
  overwrite = TRUE, verbose = TRUE
)
# Same for vi_viirs_parquet / viirs_vi/
```

### 5. Verify

```bash
Rscript R/audit_vi_parquet_dates.R \
  --out data/target_outputs/vi_parquet_date_audit_after.csv
# Expect status == ok for retained files; no large duplicate_values groups.

gh release view vi_modis_parquet --repo eco-emma/emma_envdata \
  --json assets --jq '.assets | length'
gh release view vi_viirs_parquet --repo eco-emma/emma_envdata \
  --json assets --jq '.assets | length'
```

### 6. Report climatology rebuild (emma_report)

After releases are clean, bump/rebuild report means (content-align cues on the
report side, e.g. `monthly_climatology_v3_content_align`) so ΔEVI monthly and
long-term layers stop looking identical. That work lives in `emma_report`, not
this repo.

## Tests

```bash
Rscript tests/vi_parquet_date_align_checks.R
Rscript tests/vi_geotiff_date_match_checks.R
Rscript tests/upload_inventory_checks.R
```

## Related

- `docs/VIIRS_VI_PARQUET_PUBLISH.md` — first VIIRS parquet publish
- `R/vi_parquet_date_align.R` — shared parquet audit + upload filter
- `R/vi_geotiff_date_match.R` — AppEEARS basename date filter + COG DOY upload gate
- `R/vi_grid_cog_delete.R` — parquet→sensor-COG map + release/local delete
- `R/audit_vi_parquet_dates.R` — CCR parquet audit CLI
- `R/delete_vi_grids_from_audit.R` — CCR grid COG delete CLI
