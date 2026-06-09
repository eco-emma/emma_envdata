# EMMA Burn Pipeline Redesign Plan — `BURNPLAN.md`

> Branch: `main`  
> Authored: June 2026  
> Status: **Design approved — ready for implementation**

---

## 1. Goals

This plan redesigns the fire-history processing pipeline to:

1. **Incorporate CapeNature ground-truth fire polygons** (currently loaded as a target but never used downstream).
2. **Correctly merge three sources** — CapeNature, VIIRS VNP64A1, and MODIS MCD64A1 — into a single deduplicated fire-event table with source provenance and date uncertainty per event.
3. **Compute per-pixel time-since-fire at every VI observation date** (MODIS + VIIRS, per-pixel actual dates, not just one sensor's unique date list).
4. **Produce `fire_age` parquets that mirror the VI parquets** (Option B) — separate files, consumed alongside VI via `arrow::open_dataset()`.
5. **Make the `most_recent_burn` derivation incremental** — append-only, idempotent per the burn-download pattern; no full recompute on each run.
6. **Encode right-censoring, uncertainty, and source provenance** in the output schema so the model can handle unburned pixels correctly.

---

## 2. Current-State Gaps

| Gap | Detail |
|-----|--------|
| CapeNature unused | `capenature_fires` target is defined but not passed to `merge_burn_dates()` |
| Non-incremental recompute | `compute_most_recent_burn()` loops over all query dates × all burn events on every run — O(dates × events), will not scale to 2000–present |
| MODIS-only VI dates | `vi_load_observation_dates()` reads only `modis_vi`, ignoring `vi_viirs_parquet` |
| Wrong source preference | Code comment says "prefer MODIS" but `source_rank` actually prefers VIIRS; no CapeNature rank |
| No source/uncertainty field | Output lacks `fire_source`, `date_uncertainty_days`, `fire_count`, `burn_fraction` |
| No right-censoring | Unburned pixels and pre-record pixels are both `NA last_burn_date` — indistinguishable |
| Single aggregate output | `most_recent_burn` / `postfireage.parquet` not branched; whole product invalidated if any burn month changes |
| Snapshot raster only | `recentburn.tif` stores only the latest `as_of_date`; historical monthly snapshots not preserved |

---

## 3. Data Sources & Priority

### 3.1 Priority Order

```
CapeNature  >  VIIRS (VNP64A1, 375 m)  >  MODIS (MCD64A1, 500 m)
```

**CapeNature** provides ground-verified fire records with exact calendar dates
(`DATE_START`) but covers only CapeNature-managed land and may have reporting
lags near the present. It is the authoritative date when present.

**VIIRS** (S-NPP / NOAA-20, 375 m) is the highest-resolution satellite source;
for the same fire, its detection date is preferred over MODIS.

**MODIS** (500 m) provides the longest continuous record back to November 2000
and is the sole source for 2000–2011.

### 3.2 Source Attributes

| Source | Date field | Date precision | `date_uncertainty_days` base |
|--------|-----------|----------------|------------------------------|
| CapeNature | `DATE_START` | Exact calendar date | 0 |
| VIIRS VNP64A1 | `burn_doy` (monthly) | Day-of-year in the burn month | 8 (half of 16-day compositing window) |
| MODIS MCD64A1 | `burn_doy` (monthly) | Day-of-year in the burn month | 8 |

`date_uncertainty_days` is widened by the cluster date-spread (see §5.2).

---

## 4. CapeNature Data Cleaning — `clean_capenature_fires()`

The CapeNature (SANBI) fire polygon dataset contains known date-quality
problems: typographical year errors, impossible future dates, fires where only
month/year (not day) is recorded, and a small number of records flagged as
having fabricated start dates. All cleaning is performed **before** rasterization.

This step is implemented as a dedicated cleaning block inside
`process_capenature_to_parquet()`, keeping all parameters near the top of the
script for easy auditing per the R style guide.

### 4.1 Field-Name Mapping

The current shapefile (`All_fires_23_24_gw.shp`) uses truncated DBF field
names. The mapping from Brian's older code to the current file:

| Brian's code | Current field | Description |
|---|---|---|
| `DateStart` | `DATE_START` | Date fire started (string `"YYYY-MM-DD"`) |
| `DateExting` | `DATE_EXTIN` | Date fire extinguished |
| `FIRE_CODE` | `FIRE_CODE` | Unique fire identifier used for manual fixes |
| `LOCAL_DESC`| `LOCAL_DESC` | Text notes; may contain `"START DATE FAKE"` |
| `MONTH` | `MONTH` | Calendar month (integer; 0 = unknown) |
| `YEAR` | `YEAR` | Calendar year |

### 4.2 Manual Date Corrections

A small lookup file `data/manual_download/capenature_date_fixes.csv`
(columns: `fire_code`, `field`, `corrected_value`, `note`) holds all known
hand-corrected dates. This is applied via a join before any filtering, so the
fix list is auditable and extensible without modifying function code.

The fixes are seeded from Brian Maitner's review of the historical archive.
They correct:
- **Obvious year typos** (e.g. `7197→1979`, `3009→2009`, `2103→2013`,
  `2066→2006`) affecting `DATE_EXTIN`.
- **~40 `FIRE_CODE`-specific `DATE_START` and/or `DATE_EXTIN` corrections**
  for records where dates are impossible (in the future, reversed, or >30-day
  span). Educated guesses are documented in the `note` column.
- **Month-only records** where neither start nor end day is known — dates are
  assigned to the 15th of the recorded month.

Example CSV rows:

```
fire_code,         field,      corrected_value, note
"",                DATE_EXTIN, "1979-07-31",    "year typo 7197→1979"
"",                DATE_EXTIN, "2009-02-04",    "year typo 3009→2009"
OUTE/06/2016/01,   DATE_EXTIN, "2016-06-03",    "impossible date"
KGBG/02/2017/03,   DATE_START, "2017-02-15",    "only month known"
KGBG/02/2017/03,   DATE_EXTIN, "2017-02-15",    "only month known"
...
```

#### QC re-audit rule

After applying the fix-list, a **validation check** is run and **flags** any
remaining records that may need adding to the fix-list:
- `DATE_EXTIN < DATE_START` (reversed dates)
- `DATE_EXTIN − DATE_START > 30` days (implausibly long fires)
- `DATE_START > Sys.Date()` (future dates)
- `DATE_EXTIN > Sys.Date()` (future dates)

Flagged records are printed as a warning so developers can add new entries to
`capenature_date_fixes.csv`. A `stop()` is raised only if the count of
corrupt records exceeds a configurable threshold (default: 0 for future dates,
5 for reversed/long spans — matching the known historical noise level).

### 4.3 Derive Canonical Burn Date (`burn_date`)

After cleaning, a single canonical burn date is derived per polygon using the
following hierarchy (using `DATE_START` as authoritative, per project design):

```
burn_date =
  1. DATE_START  if DATE_START is present and valid →
  2. YEAR-MONTH-15  if MONTH != 0 (and DATE_START is NA) →
  3. YEAR-01-01  if MONTH == 0 AND YEAR < 1996 →
  4. DROP (exclude record)
```

`date_uncertainty_days` is set to:
- `0` when exact `DATE_START` known.
- `15` when only `YEAR-MONTH` known (mid-month assignment).
- `180` when only year known (`YEAR < 1996`, MONTH = 0).
- If `DATE_EXTIN` is present and valid and `DATE_EXTIN > DATE_START`,
  `date_uncertainty_days = DATE_EXTIN − DATE_START` (actual fire duration
  bounds when uncertainty in which day within the fire the pixel burned).

### 4.4 Post-Clean Filtering

After date derivation:

1. **Drop low-precision MODIS-era records**: remove rows where `YEAR >= 2000`
   AND `DATE_START` is absent (`burn_date` derived from month or year only).
   Post-2000 we have satellite coverage — low-precision CapeNature dates would
   add noise without benefit.

2. **Drop future dates**: remove rows where `burn_date >= Sys.Date()`.

3. **Drop "fake" start dates**: where `LOCAL_DESC` matches the pattern
   `"START DATE FAKE"` (case-insensitive), set `DATE_START <- NA`, then
   apply the hierarchy above (which will drop the record if YEAR ≥ 2000 and no
   exact date is derivable).

### 4.5 Rasterization Algorithm

With the cleaned `sf` object, proceed to rasterization:

1. For each fire polygon, compute the **fractional burn coverage** of every
   500 m `pid` pixel it overlaps using `terra::rasterize(..., cover = TRUE)`.
   `cover = TRUE` returns the fraction of each cell covered by the polygon.

2. A pixel is **recorded as burned** if `burn_fraction > 0.5` (majority-pixel
   rule). Pixels with `0 < burn_fraction ≤ 0.5` are **not** recorded as burned
   for that fire event, but the fraction is retained as a diagnostic field.

3. Burn date = `burn_date` (from §4.3). `date_uncertainty_days` from §4.3.

4. Output: parquet with one row per burned pixel per fire event:

```
pid               int32   — domain pixel ID
date              int32   — DATE_START as days since 1970-01-01
source            chr     — "capenature"
date_uncertainty_days int16  — 0 if point date, else fire span in days
burn_fraction     float32 — fraction of 500 m pixel covered by polygon
```

### 4.6 Target

```r
tar_target(
  capenature_burn_events,
  process_capenature_to_parquet(
    capenature_fires  = capenature_fires,
    domain_raster     = domain.tif,
    date_fixes_csv    = "data/manual_download/capenature_date_fixes.csv",
    out_file          = "data/target_outputs/burndates/capenature_burns.parquet",
    verbose           = TRUE
  ),
  format = "file",
  cue    = tar_cue(mode = "never")  # Static manual data: only rerun locally
)
```

The `date_fixes_csv` argument decouples the correction lookup from the
function code — adding a new fix requires only editing the CSV and
re-running this target locally, not modifying any `.R` file.

---

## 5. Burn Event Merging — `merge_burn_dates()`

### 5.1 Inputs
- `capenature_burn_events`: parquet from §4.
- All `burn_modis_*.parquet` files in `data/target_outputs/burndates/`.
- All `burn_viirs_*.parquet` files in `data/target_outputs/burndates/`.

Unified intermediate schema (one row per raw detection per pixel):

```
pid                   int32
date                  int32   — days since 1970-01-01
source                chr     — "capenature" | "viirs" | "modis"
date_uncertainty_days int16
burn_fraction         float32  — NA for VIIRS/MODIS (pixel-level sources)
```

### 5.2 Cross-Sensor De-duplication (greedy 6-month clustering)

Because a real fire is detected by multiple sensors with slightly different dates,
a naive group-by-pixel-date would keep false duplicates. The same fire **never**
burns the same 500 m pixel twice within 6 months — so:

1. For each `pid`, sort all events by `date`.
2. Walk events in order. Start a new fire cluster at the first unassigned event;
   absorb all subsequent events within **182 days** of that cluster's anchor date.
3. Collapse each cluster into one canonical fire event:
   - **Canonical date:**
     - If CapeNature is present in the cluster → use CapeNature `date`
       (ground truth; it may be earlier or later than the satellite detections
       but it is the most reliable).
     - Otherwise → use the **earliest satellite detection date** across VIIRS
       and MODIS in the cluster ("first detection most likely"). Ties broken by
       VIIRS > MODIS.
   - **`fire_source`:** source that supplied the canonical date (`capenature`,
     `viirs`, or `modis`).
   - **`date_uncertainty_days`:** `base_uncertainty_for_source +
     (max_date_in_cluster − min_date_in_cluster)`. The within-cluster spread
     captures multi-sensor disagreement.
   - **`burn_fraction`:** taken from CapeNature if present, else `NA`.

4. The resulting **deduplicated** table has one row per pixel × distinct fire.

### 5.3 Output: `burn_events_merged`

```
pid                   int32
date                  int32   — canonical date (days since epoch)
fire_source           chr     — "capenature" | "viirs" | "modis"
date_uncertainty_days int16
burn_fraction         float32  — NA for non-CapeNature events
```

This is an in-memory object passed between targets (format = "qs"), not a parquet
(it's an intermediate, not a published product).

---

## 6. Incremental Most-Recent-Burn State — `compute_fire_state()`

### 6.1 Rationale

`compute_most_recent_burn()` currently recomputes the full pixel × date matrix
from scratch. For the full 2000–present record at per-pixel VI dates this is
O(n_pixels × n_VI_dates × n_fire_events) — impractical.

The new design maintains a **running per-pixel state file**:
`most_recent_burn_state.parquet`, updated by appending only newly-completed months.
Each run:
1. Reads the current state (last processed month, `last_burn_date`, `fire_count`
   per pixel).
2. Finds newly completed months since the last run.
3. Applies new fire events from those months (from `burn_events_merged`).
4. Writes the updated state back.

This mirrors the idempotency pattern used by `submit_burn_date_modis_task()` —
check what is done, skip what is already done, append new work.

### 6.2 Per-Pixel State Schema — `most_recent_burn_state.parquet`

```
pid               int32
state_month       int32   — last processed month-start as days since epoch
last_burn_date    int32   — most recent fire date up to state_month (NA = never)
fire_count        int32   — total fires recorded since 2000-01-01 (0 = never burned)
fire_source       chr     — source of last_burn_date
date_uncertainty_days int16 — uncertainty of last_burn_date
burn_fraction     float32
```

- Pixels with `fire_count = 0` and `last_burn_date = NA` are **right-censored**:
  age is at minimum `state_month − 2000-01-01`, not truly unknown.
- This state is read at the start of each `fire_age` computation and carried
  forward per-pixel to new VI dates.

### 6.3 Algorithm

```
# Pseudocode — linear, top-to-bottom
record_start  <- as.integer(as.Date("2000-01-01") - as.Date("1970-01-01"))

state <- read_parquet("most_recent_burn_state.parquet")
        # or initialise empty if first run

last_state_month <- max(state$state_month, default = record_start)
new_months <- months in burn_events_merged after last_state_month

for each new_month in new_months (in order):
  month_fires <- burn_events_merged |> filter(date >= month_start, date < next_month)
  
  # Update state for pixels that burned this month
  state <- state |>
    left_join(month_fires, by = "pid") |>
    mutate(
      last_burn_date        = coalesce(fire_date, last_burn_date),
      fire_count            = fire_count + if_else(!is.na(fire_date), 1L, 0L),
      fire_source           = coalesce(fire_source_new, fire_source),
      date_uncertainty_days = coalesce(date_uncertainty_new, date_uncertainty_days),
      burn_fraction         = coalesce(burn_fraction_new, burn_fraction),
      state_month           = month_start
    )

write_parquet(state, "most_recent_burn_state.parquet")
```

The loop is a standard sequential `for` loop (stateful carry-forward — one of
the R style guide's explicit exceptions to the "prefer `purrr::map`" rule).

---

## 7. Fire-Age at VI Observation Dates — `compute_fire_age_for_vi()`

### 7.1 Inputs

- VI parquets: read both `data/target_outputs/modis_vi/` and
  `data/target_outputs/viirs_vi/` as one logical dataset via
  `arrow::open_dataset(c(modis_dir, viirs_dir))`. Each file already has
  `pid`, `date`, `variable` (sensor code), `value` (EVI).
- `most_recent_burn_state.parquet` (§6).

### 7.2 Algorithm (per VI month / per sensor)

For each VI parquet file (`vi_modis_YYYYMMDD.parquet` or
`vi_viirs_YYYYMM.parquet`):

1. Read the VI parquet.
2. For each `(pid, date)` in that VI file, look up the state as of
   `max(state$state_month ≤ vi_date)` — i.e. the most recent burn state that
   predates the VI observation.
3. Compute:

```
fire_age_days = vi_date − last_burn_date        # NA if never burned
```

4. For pixels with `fire_count = 0`: `fire_age_days = vi_date − record_start`
   (right-censored lower bound, not NA).
   This is distinguishable because `fire_count = 0`.

### 7.3 Output Schema — `fire_age_modis_YYYYMMDD.parquet` / `fire_age_viirs_YYYYMM.parquet`

Mirrors the VI parquet rows exactly (same `pid` × `date` × `sensor`):

```
pid                   int32    — domain pixel ID
date                  int32    — VI observation date (days since 1970-01-01)
sensor                int32    — 1 = Terra MOD13A1, 2 = Aqua MYD13A1, 3 = VIIRS S-NPP, 4 = NOAA-20
last_burn_date        int32    — most recent fire date before this VI date (days since epoch)
fire_age_days         int32    — date − last_burn_date (right-censored for fire_count = 0)
fire_source           chr      — "capenature" | "viirs" | "modis" | NA (never burned)
date_uncertainty_days int16    — uncertainty in last_burn_date (days)
fire_count            int32    — total fires recorded in this pixel since 2000-01-01
burn_fraction         float32  — CapeNature fractional burn coverage; NA if satellite-sourced
```

Notes:
- For **right-censored** pixels (`fire_count = 0`): `fire_age_days` =
  `date − record_start_date` (a minimum age), `fire_source = NA`,
  `last_burn_date = NA`.
- `date_uncertainty_days = 0` when CapeNature supplies the date, ~8 + spread
  for MODIS/VIIRS clusters.

### 7.4 Idempotency

Before computing `fire_age_modis_YYYYMMDD.parquet`, check if the file already
exists in `data/target_outputs/fire_age/` (and on the GitHub release). Skip if
present (same pattern as burn download idempotency).

---

## 8. Consuming the Combined VI+Fire Dataset

The model reads VI and fire-age data via `arrow::open_dataset()` and joins on
`(pid, date, sensor)`. No physical merge target needed:

```r
vi_dataset <- arrow::open_dataset(
  c(
    "data/target_outputs/modis_vi",
    "data/target_outputs/viirs_vi"
  )
)

fire_age_dataset <- arrow::open_dataset(
  "data/target_outputs/fire_age"
)

# Example: query all NDVI observations with fire age for a single pixel
vi_with_fire <- vi_dataset |>
  dplyr::left_join(fire_age_dataset, by = c("pid", "date", "sensor")) |>
  dplyr::filter(pid == target_pid) |>
  dplyr::collect()
```

Arrow pushes the join filter predicate to disk — only matching row groups are
read. This scales to the full multi-year record.

Optionally, a combined convenience parquet can be written by a downstream
`combine_vi_fire_parquet` target (not included in this plan — add if the model
explicitly requires a single-file input).

---

## 9. Updated `_targets.R` Target Graph

### New / modified targets

```r
# ── Static: rasterize CapeNature to burn events (manual-data, cue="never") ──
tar_target(
  capenature_burn_events,
  process_capenature_to_parquet(
    capenature_fires = capenature_fires,
    domain_raster    = domain.tif,
    out_file         = "data/target_outputs/burndates/capenature_burns.parquet",
    verbose          = TRUE
  ),
  format = "file",
  cue    = tar_cue(mode = "never")
),

# ── Merge all three sources into deduplicated fire-event table (in-memory qs) ─
tar_target(
  burn_events_merged,
  {
    force(burn_modis_parquet)
    force(burn_viirs_parquet)
    force(capenature_burn_events)          # ← new dependency
    merge_burn_dates(
      burn_dir             = "data/target_outputs/burndates/",
      capenature_parquet   = capenature_burn_events,  # ← new argument
      verbose              = TRUE
    )
  },
  format = "qs"
),

# ── Update incremental per-pixel fire state through end of last complete month ─
tar_target(
  most_recent_burn,
  compute_fire_state(
    burn_events = burn_events_merged,
    state_file  = "data/target_outputs/most_recent_burn_state.parquet",
    verbose     = TRUE
  ),
  format = "file"
),

# ── Compute fire age at every VI observation date (MODIS + VIIRS) ─────────────
tar_target(
  fire_age_parquets,
  compute_fire_age_for_vi(
    modis_vi_dir = "data/target_outputs/modis_vi",
    viirs_vi_dir = "data/target_outputs/viirs_vi",
    state_file   = most_recent_burn,
    out_dir      = "data/target_outputs/fire_age/",
    verbose      = TRUE
  ),
  format = "file",
  # force dependency on all VI parquets (branched vectors)
  # achieved by passing vi_modis_parquet/vi_viirs_parquet to function args or force()
),

# ── Snapshot raster (latest state only — unchanged from current) ──────────────
geotargets::tar_terra_rast(
  recentburn.tif,
  most_recent_burn_to_grid(
    state_file    = most_recent_burn,
    domain_raster = domain.tif,
    verbose       = TRUE
  ),
  datatype = "INT4S"
),

# ── Upload fire_age parquets to GitHub release ────────────────────────────────
tar_target(
  upload_fire_age,
  upload_to_github_release(
    files        = fire_age_parquets[!grepl("\\.skip$", fire_age_parquets)],
    repo         = gh_repo_config$repo,
    release_tag  = release_tags$fire_age,
    release_name = "Fire Age at VI Observation Dates",
    verbose      = TRUE
  ),
  deployment = "main"
),
```

Add `fire_age = "fire_age_dynamic"` to the `release_tags` list.

Remove (or rename) the now-superseded targets:
- `most_recent_burn` (replaced by `compute_fire_state`)
- `vi_load_observation_dates` call inside the old `most_recent_burn` target

---

## 10. Updated `R/process_burn_dates.R`

### Functions to rewrite / add

| Function | Action |
|----------|--------|
| `process_capenature_to_parquet()` | **New.** Runs QC cleaning (§4.2–4.4) then rasterizes CapeNature polygons to `pid` grid with fractional cover; writes events parquet. |
| `merge_burn_dates()` | **Rewrite.** Accept `capenature_parquet` arg; combine 3 sources; apply 6-month cluster de-dup; return `burn_events_merged`. |
| `compute_fire_state()` | **New replaces `compute_most_recent_burn()`.** Idempotent append-only loop; maintain per-pixel running state; write `most_recent_burn_state.parquet`. |
| `compute_fire_age_for_vi()` | **New replaces `vi_load_observation_dates()` + old `compute_most_recent_burn()`.** Per-VI-parquet, join state → write `fire_age_*.parquet` with full schema. |
| `most_recent_burn_to_grid()` | **Update** to read from `most_recent_burn_state.parquet` instead of `postfireage.parquet`. |
| `vi_load_observation_dates()` | **Remove** (logic absorbed into `compute_fire_age_for_vi()`). |

### Companion data file

`data/manual_download/capenature_date_fixes.csv` — the manual date-correction
lookup seeded from Brian Maitner's historical review. Columns:
`fire_code, field, corrected_value, note`. Empty `fire_code` entries apply the
correction to all records matching the raw bad value in `corrected_value`
(for the obvious year typos). This file is tracked in version control so the
full correction audit trail is visible in git history.

### Style
All new functions follow `r-style.instructions.md`:
- Native pipe `|>`, tidyverse idioms (`dplyr`, `purrr`, `tibble`).
- Named intermediate objects, not deeply nested pipes.
- `for` loop for stateful carry-forward (`compute_fire_state()`).
- 2-space indent, ≤80 chars.
- Comments explain scientific rationale (e.g., "# pixels do not burn twice within 6 months — cluster multi-sensor events").

---

## 11. Uncertainties & Known Limitations

| Uncertainty | Handling |
|-------------|----------|
| CapeNature spatial incompleteness | `fire_source` encodes whether ground-truth is available; model can stratify |
| CapeNature reporting lag near present | `cue = "never"` means stale data if not manually refreshed — document in README |
| CapeNature date corruption | Manual fix-list (`capenature_date_fixes.csv`) + QC validation guards flag remaining issues |
| CapeNature low-precision pre-2000 dates | Date hierarchy assigns mid-month/mid-year with `date_uncertainty_days = 15` or `180`; post-2000 records without exact dates are dropped |
| Polygon-date vs per-pixel burn moment | `date_uncertainty_days = DATE_EXTIN − DATE_START` bounds the fire duration; per-pixel burn moment unknown within that span |
| MODIS/VIIRS ~1–2 month processing lag | Pipeline already applies 14-day lag before downloading; burn events are always ≥1 month old |
| Left-truncation at 2000-01-01 | `fire_count = 0` flags right-censored pixels; `fire_age_days` gives minimum age |
| 182-day cluster window | Assumption that a single pixel does not burn twice within 6 months — may fail in extreme drought years; `fire_count` remains correct even if occasionally two fires within 6 months are collapsed |
| MODIS composite DOY vs true burn date | `date_uncertainty_days ≈ 8 + cluster_spread` partially captures this |
| VIIRS 375 m vs 500 m grid | VIIRS pixels resampled to 500 m domain grid; some mixed pixels inevitable |
| Subpixel burns | `burn_fraction` from CapeNature tracks this; MODIS/VIIRS are binary detections so `burn_fraction = NA` |

---

## 12. Release & STAC Changes

### New release tag
```r
release_tags$fire_age <- "fire_age_dynamic"
```

### STAC
Add a STAC collection entry for `fire_age_dynamic` alongside the existing
`burn` collection. The `generate_burn_stac()` function (or a new
`generate_fire_age_stac()`) should include `fire_age_*.parquet` items with the
new schema documented in item metadata.

---

## 13. Implementation Sequence

1. **`capenature_date_fixes.csv`** — create the lookup file seeded from Brian's manual corrections; run the QC validation step on the current shapefile to identify any new corrupt records.
2. **`process_capenature_to_parquet()`** — new function + target including QC cleaning. Testable in isolation locally (needs the shapefile).
3. **`merge_burn_dates()` rewrite** — add CapeNature arg, implement 6-month cluster de-dup. Unit-test on small synthetic data.
4. **`compute_fire_state()`** — incremental state builder. Test by running on a few months and checking `fire_count` + `last_burn_date`.
5. **`compute_fire_age_for_vi()`** — VI join + right-censoring. Test output row count matches VI parquet.
6. **`_targets.R` edits** — wire new targets, add `fire_age` release tag, update `burn_events_merged` deps.
7. **`most_recent_burn_to_grid()` update** — minor read-path change.
8. **Release/STAC** — new release tag, update STAC generator.
9. **Documentation** — update `ARCHITECTURE.md` §2.5, §4, data-flow diagram; note `capenature_date_fixes.csv` QC re-audit procedure.

---

*End of BURNPLAN.md*
