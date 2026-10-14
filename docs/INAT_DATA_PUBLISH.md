# iNaturalist invasives → `inat_data`

## Contract

| Role | Tag | Assets |
|------|-----|--------|
| AOI input | [`static_data`](https://github.com/eco-emma/emma_envdata/releases/tag/static_data) | **`parks_buffer_10km.gpkg`** — buffered parks **only** (no domain union) |
| Species seed | repo file | `data/inat_invasive_species.csv` (curated names from report iNat project CSV) |
| Output | **`inat_data`** | **`inat_invasives.gpkg`** (WGS84) |

Schema (`inat_invasives.gpkg`): `scientific_name`, `observed_on`, `longitude`, `latitude`, `invasive`, `geometry`. CRS = **WGS84** (do not publish invasives in Albers).

Ecological / harvest rules (parity with emma_report, settled AOI):

- Invasive genera: `Acacia`, `Pinus`, `Hakea`, `Eucalyptus`, `Leptospermum`
- `oldest_date = "2020-01-01"`
- Live `rinat::get_inat_obs()` per curated scientific name
- Spatial filter to **`parks_buffer_10km` only** — **do not** `st_union` with unbuffered domain
- Zero rows → succeed and publish empty gpkg (report Quarto guards empty panels)
- Missing `parks_buffer_10km.gpkg` on `static_data` → **fail loud**

## Prerequisite

Park Phase B must publish `parks_buffer_10km.gpkg` to `static_data` first
([PR #31](https://github.com/eco-emma/emma_envdata/pull/31) / CCR park prime).

Verify:

```bash
gh release view static_data --repo eco-emma/emma_envdata \
  --json assets --jq '.assets[].name' | grep parks_buffer_10km
```

## First publish = CCR (required)

Nightly AppEEARS Actions stays separate. After parks buffer exists on
`static_data` and this branch is on `main`:

```bash
# 1. SSH + interactive node
ssh vortex.ccr.buffalo.edu
salloc --cluster=faculty --qos=adamw --partition=adamw \
  --job-name=emma_inat --nodes=1 --ntasks=4 --mem=24G \
  -C INTEL --time=04:00:00

# 2. Repo + Apptainer shell
cd /projects/academic/adamw/projects/emma/emma_envdata
git fetch origin && git checkout main && git pull --ff-only
bash R/ccr_startup.sh shell

# 3. Inside the Apptainer shell at repo root — harvest + upload to inat_data
Rscript R/publish_inat_data.R
```

Optional local AOI (skip download):

```bash
INAT_AOI_GPKG=/path/to/parks_buffer_10km.gpkg Rscript R/publish_inat_data.R
```

Dry-run without upload: `Rscript R/publish_inat_data.R --no-upload`

Equivalent targets form (cue `never`; not on the AppEEARS cron):

```r
targets::tar_make(c(inat_invasives_product, upload_inat_data))
```

Verify assets:

```bash
gh release view inat_data --repo eco-emma/emma_envdata \
  --json assets --jq '.assets[].name' | grep inat_invasives.gpkg
```

## Optional later: GitHub Actions (not first publish)

Workflow [`.github/workflows/publish-inat.yaml`](../.github/workflows/publish-inat.yaml)
is **`workflow_dispatch` only** (dedicated concurrency group
`emma-envdata-publish-inat`). Downloads `parks_buffer_10km.gpkg` from
`static_data`, harvests, uploads `inat_invasives.gpkg` to `inat_data`.

Nightly cron can be added later — keep **AppEEARS | weather | iNat** as
separate jobs; do not stack with `targets.yaml`.

## Non-goals

- Does not edit the AppEEARS `targets.yaml` cron/body (owned by E0 / parks PRs).
- Does not publish weather or park gpkgs.
- Does not flip emma_report to download-only (report R3).
