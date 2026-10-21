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
  --delete-remote --delete-local
```

Remote runs **before** local so a DNS/API abort does not leave orphans on the
release while locals are already gone.

`--delete-remote` pages the GitHub assets API (safe for 600+ files) with
retries on transient DNS/connection errors.
`--dry-run` (default when no `--delete-*`) only reports.

**Resume after a failed remote delete** (CSV already written; locals may already
be gone — do **not** re-audit without `--from-csv`, or flagged rows disappear):

```bash
# Prefer this branch / main after the resume helper lands.
Rscript R/audit_vi_parquet_dates.R \
  --from-csv data/target_outputs/vi_parquet_date_audit.csv \
  --delete-remote

# Or one-shot from the existing CSV (works on older main too):
R -e '
source("R/utils.R"); source_pipeline_r()
report <- read.csv("data/target_outputs/vi_parquet_date_audit.csv",
                   stringsAsFactors = FALSE)
flagged <- report[report$status != "ok", , drop = FALSE]
token <- .gh_upload_token(verbose = TRUE)
by_tag <- split(flagged$file, vi_parquet_release_tag(flagged$file))
for (tag in names(by_tag)) {
  message("tag ", tag, ": ", length(by_tag[[tag]]), " assets")
  gh_delete_release_assets_by_name(
    repo = "eco-emma/emma_envdata",
    release_tag = tag,
    asset_names = by_tag[[tag]],
    token = token,
    verbose = TRUE
  )
}
'
```

Confirm DNS before a long delete: `getent hosts api.github.com` or
`curl -I https://api.github.com`.

### 3. Check whether grid COGs are also wrong

If parquet was built from a duplicated Jul–Aug COG, regenerating parquet
alone will recreate the same junk. Spot-check a few flagged dates:

```r
# Inside Apptainer
library(terra)
d <- as.Date("2000-09-13")  # example flagged basename
yyyymmdd <- format(d, "%Y%m%d")
terra <- rast(sprintf("data/target_outputs/modis_vi/vi_modis_terra_%s.tif", yyyymmdd))
# DOY band should cluster near the composite window, not a fixed Jul–Aug
# template for every year.
summary(values(terra[["doy"]]))
```

If COGs are wrong or missing after parquet delete:

```r
# Delete bad sensor grids locally + from raster releases, then tar_make
# will treat those composites as pending (filter_pending_composites).
# Reuse audit_na_placeholders helpers or manual unlink + gh_delete…
```

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
Rscript tests/upload_inventory_checks.R
```

## Related

- `docs/VIIRS_VI_PARQUET_PUBLISH.md` — first VIIRS parquet publish
- `R/vi_parquet_date_align.R` — shared audit + upload filter
- `R/audit_vi_parquet_dates.R` — CCR CLI
