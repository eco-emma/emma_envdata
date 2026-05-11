# AppEEARS Setup Guide

This project now uses NASA AppEEARS instead of Google Earth Engine for satellite data access.

## Prerequisites

1. **NASA EarthData Account**: Register at https://urs.earthdata.nasa.gov/
2. **AppEEARS Access**: Approve AppEEARS application at https://appeears.earthdatacloud.nasa.gov/

## Local Setup

Set environment variables in your `.Renviron` file:

```r
# Edit .Renviron
usethis::edit_r_environ()

# Add these lines:
EARTHDATA_USER=your_username
EARTHDATA_PASSWORD=your_password
```

Restart R session for changes to take effect.

## GitHub Actions Setup

Add secrets to your repository:

1. Go to repository Settings → Secrets and variables → Actions
2. Add two secrets:
   - `EARTHDATA_USER`: Your NASA EarthData username
   - `EARTHDATA_PASSWORD`: Your NASA EarthData password

## Verify Setup

Test authentication in R:

```r
library(appeears)
rs_login(
  user = Sys.getenv("EARTHDATA_USER"),
  password = Sys.getenv("EARTHDATA_PASSWORD")
)

# List available products
rs_products()
```

## Migration Notes

### Changes from rgee to AppEEARS

- **Authentication**: Simple username/password instead of service account JSON
- **Output format**: Gzip-compressed Parquet files (`.parquet`) instead of GeoTIFFs; NetCDF is intermediate only
- **Storage efficiency**: ~20% reduction in file sizes
- **Simpler CI/CD**: No Python/conda dependencies required

### Product Mapping

| Dataset | AppEEARS Product | Status |
|---------|-----------------|--------|
| MODIS Burned Area | MCD64A1.061 | ✅ Active |
| MODIS VI — Terra | MOD13A1.061 | ✅ Active |
| MODIS VI — Aqua | MYD13A1.061 | ✅ Active |
| VIIRS Burned Area | VNP64A1.001 | ✅ Active |
| Elevation (SRTM) | SRTMGL3_NC.003 | ✅ Active |
| CHELSA Climate | Direct download (unchanged) | ✅ Active |
| SoilGrids | ISRIC WCS (direct download) | ✅ Active |
| Cloud frequency | EarthEnv MODCF (direct download) | ✅ Active |

### Output Format

AppEEARS NetCDF downloads are intermediate files only. Each monthly NetCDF is converted to a
gzip-compressed Parquet file (`.parquet`) and the NetCDF is deleted on GitHub Actions to save
disk space. Final outputs are Parquet files stored in GitHub Releases.

### Release Tags

- `data_modis_vi_current` — MODIS EVI time series (monthly parquets)
- `data_burn_dates_modis_current` — MODIS burned area (monthly parquets)
- `data_burn_dates_viirs_current` — VIIRS burned area (monthly parquets)
- `data_fire_covariates_current` — Derived fire metrics (most recent burn, fire age)
- `data_static_current` — Static environmental layers (elevation, climate, clouds, soil, topography)
- `data_stac_current` — STAC catalog JSON for dataset discovery
- `objects_current` — Internal targets cache (workflow artifacts)

## Troubleshooting

### Authentication Errors

If you see "EARTHDATA credentials not found":
1. Check environment variables are set: `Sys.getenv("EARTHDATA_USER")`
2. Restart R session after setting `.Renviron`
3. Verify credentials at https://urs.earthdata.nasa.gov/

### AppEEARS Task Failures

Check task status:
```r
appeears::rs_status(task_id = "your_task_id")
```

Common issues:
- Date range too large (split into smaller requests)
- Invalid area of interest (ensure valid WGS84 coordinates)
- Service temporarily unavailable (retry after delay)

## Resources

- [AppEEARS Documentation](https://appeears.earthdatacloud.nasa.gov/help)
- [appeears R package](https://docs.ropensci.org/appeears/)
- [NASA EarthData](https://earthdata.nasa.gov/)
