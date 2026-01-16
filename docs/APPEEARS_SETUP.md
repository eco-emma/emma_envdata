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
- **Output format**: Monthly NetCDF files instead of individual GeoTIFFs
- **Storage efficiency**: ~20% reduction in file sizes
- **Simpler CI/CD**: No Python/conda dependencies required

### Product Mapping

| Current (rgee) | AppEEARS Product | Status |
|----------------|------------------|--------|
| MODIS Fire (MCD64A1) | MCD64A1.061 | ✅ Migrated |
| MODIS NDVI (MOD13A1) | MOD13A1.061 | ✅ Migrated |
| VIIRS NDVI | VNP13A1.001 | 🔄 Pending |
| KNDVI | Calculate from reflectances | 🔄 Pending |
| CHELSA Climate | Direct download (unchanged) | ✅ No change |
| NASADEM | NASADEM.001 | 🔄 Pending |

### Release Tags

NetCDF outputs use new tag names to distinguish from GeoTIFF:

- `raw_fire_modis_nc` - Raw fire monthly NetCDF
- `raw_ndvi_modis_nc` - Raw NDVI monthly NetCDF
- etc.

### File Naming Convention

Monthly NetCDF files follow the pattern: `{product}_{collection}_{YYYY-MM}.nc`

Examples:
- `fire_MCD64A1_2025-12.nc`
- `ndvi_MOD13A1_2025-12.nc`

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
