# MODIS VI Monthly Download Implementation Guide

## Overview

As of February 2026, MODIS VI data is downloaded **month-by-month** instead of in a single monolithic request. This improves resilience, enables parallelization, and simplifies incremental updates.

## How It Works

### 1. Month Identification (`modis_vi_months_to_download`)
- Generates full sequence of months from start date to present
- Checks which months already exist in `data/target_outputs/modis_vi_monthly/`
- Returns only missing months for downstream processing
- **Prime mode**: Downloads all months from 2000-02-18 to present
- **Update mode**: Downloads last ~3 months (to recapture any missed dates)

### 2. Task Submission (`modis_vi_month_task_ids`)
- **Dynamic branching**: One task per missing month
- Each task submits a single month to AppEEARS API
- Returns task ID for downstream polling
- With 2 workers: Can submit 2 months simultaneously

### 3. Download & Processing (`modis_vi_monthly_files`)
- **Dynamic branching**: Polls and downloads each month independently
- Applies QA masking to EVI data
- Projects to domain CRS and grid
- Outputs: Individual NetCDF file per month (format: `modis_vi_YYYY_MM.nc`)
- With 2 workers: Can download 2 months simultaneously

### 4. Indexing (`modis_vi_monthly_index`)
- Creates parquet summary of all monthly files
- Maps: month → file path, size, creation date
- Useful for downstream analysis tools to discover available data

### 5. Optional Aggregation (Commented Out)
- Can combine all months into single NetCDF file
- Uncomment the `modis_vi` target in `_targets.R` if needed
- Trade-off: Single file easier to use, but loses monthly granularity

## File Structure

```
data/
├── target_outputs/
│   ├── modis_vi_monthly/          # Monthly NetCDF files
│   │   ├── modis_vi_2000_02.nc
│   │   ├── modis_vi_2000_03.nc
│   │   └── ... (1 file per month)
│   └── modis_vi_monthly_index.parquet  # Index of all monthly files
```

## Migration from Old Approach

**Old approach** (commented-out in current code):
- Single AppEEARS request for entire date range (26+ years)
- Returns one massive download
- Failure means entire run fails
- "Update mode" creates separate file and requires reconciliation

**New approach**:
- 312 independent AppEEARS requests (one per month)
- Each month ~5-10 GB per format (NDVI, EVI, QA)
- Failure of month N doesn't affect other months
- "Update mode" naturally only downloads missing months
- Targets automatically parallelizes: with 2 workers, ~156 parallel jobs instead of 1 serial job

## Parallelization

The current GitHub Actions workflow runs single-processor. To enable parallelization:

In `_targets.R` line ~97, change:
```r
Rscript -e "targets::tar_make()"
```

To:
```r
Rscript -e "targets::tar_make_future(workers = 2)"
```

This will download up to 2 months simultaneously, ~2x speedup for full historical runs.

## Resuming Interrupted Runs

If a GitHub Actions run times out mid-way:
1. The completed monthly files are already saved
2. On next run, `modis_vi_months_to_download` will detect and skip them
3. Only missing months are re-downloaded
4. No re-submission of already-completed AppEEARS tasks needed

## Downstream Usage

### Access All Monthly Data
```r
# Load the index
library(arrow)
monthly_index <- read_parquet("data/target_outputs/modis_vi_monthly_index.parquet")

# Load specific month(s)
ndvi_jan_2020 <- terra::rast(
  monthly_index$file_path[monthly_index$month == "2020-01-01"]
)
```

### Access Time Series Data
```r
# Read all months as stacked raster
monthly_files <- sort(list.files(
  "data/target_outputs/modis_vi_monthly",
  pattern = "modis_vi_.*\\.nc$",
  full.names = TRUE
))
ndvi_timeseries <- terra::rast(monthly_files)  # Stacked raster
```

### Aggregate After Pipeline Completes
If needed, aggregate monthly files manually:
```r
# After all months downloaded, aggregate to single file
r::source("R/modis_vi_monthly_helpers.R")

aggregate_modis_vi_monthly(
  monthly_files = sort(list.files(...)),
  out_file = "data/target_outputs/modis_vi_combined.nc"
)
```

## Future Enhancements

Potential improvements:
1. **Parallel download speeds**: Currently 2 workers (limited by GitHub Actions CPU); CCR cluster supports more
2. **Tighter incremental updates**: Current "update mode" re-downloads last 3 months; could be refined to only new data
3. **QA statistics**: Track which months had failed pixels, guide re-processing
4. **Data subsetting**: Support downloading specific regions instead of full domain
5. **Format flexibility**: Consider keeping data as monthly parquet files instead of NetCDF for model consumption

## Troubleshooting

### "No NetCDF files downloaded from AppEEARS"
- AppEEARS task failed to complete
- Check AppEEARS API status (may be temporarily down)
- Verify domain geometry is valid (simplify step in `submit_modis_vi_month()`)
- Manual retry: Delete month file from `modis_vi_monthly/` and re-run targets

### "modis_vi_monthly_index not found"
- Monthly downloads still in progress (check GitHub Actions logs)
- Or all months already exist and no work was done (expected in updates)

### Memory issues with aggregation
- Monthly files are large (~5-10 GB each)
- If aggregating many months, may need to increase memory or process subset
- Better solution: Keep monthly files separate, access via index
