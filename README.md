

<script src="README_files/libs/kePrint-0.0.1/kePrint.js"></script>
<link href="README_files/libs/lightable-0.0.1/lightable.css" rel="stylesheet" />

![](img/EMMA%20Logo_RE_3.jpg)

# Ecological Monitoring and Management Application (EMMA)

This repository processes environmental data for the [EMMA
project](https://emma.io), assembling multi-sensor satellite and
environmental datasets (MODIS, VIIRS, CHELSA, SoilGrids, etc.) for the
Cape Floristic Region / South Africa. All data are domain-aligned to a
500m grid and distributed as Cloud-Optimized GeoTIFFs (COGs) and
GeoParquet tables via GitHub Releases with full STAC catalog support.

## Pipeline Workflow

    #> Starting tar_make()
    #> System info: sysname=Linux; release=6.8.0-117-generic; version=#117-Ubuntu SMP PREEMPT_DYNAMIC Tue May  5 19:26:24 UTC 2026; nodename=cpn-c08-13.core.ccr.buffalo.edu; machine=x86_64; login=unknown; user=adamw; effective_user=adamw
    #> Set working directory to: /projects/academic/adamw/projects/emma/emma_envdata
    #> tar_source() only sources R scripts. Ignoring non-R files: R/ccr_startup.sh
    #> Loaded 40 packages from DESCRIPTION
    #> + burn_viirs_task_ids declared [3 branches]
    #> + vi_modis_task_ids declared [5 branches]
    #> + burn_modis_task_ids declared [3 branches]
    #> + vi_viirs_task_ids declared [5 branches]
    #> + burn_viirs_geotiff declared [3 branches]
    #> + vi_modis_geotiff declared [5 branches]
    #> + burn_modis_geotiff declared [3 branches]
    #> + vi_viirs_geotiff declared [5 branches]
    #> + burn_viirs_grid declared [3 branches]
    #> + vi_modis_grid declared [5 branches]
    #> + burn_modis_grid declared [3 branches]
    #> + vi_viirs_grid declared [5 branches]
    #> + burn_viirs_parquet declared [3 branches]
    #> + vi_modis_parquet declared [5 branches]
    #> + burn_modis_parquet declared [3 branches]
    #> + vi_viirs_parquet declared [5 branches]
    #> Warning messages:
    #> 1: <anonymous>: ..1 may be used in an incorrect context
    #>  
    #> 2: <anonymous>: ..2 may be used in an incorrect context
    #>  
    #> 3: <anonymous>: ..1 may be used in an incorrect context
    #>  
    #> 4: <anonymous>: ..2 may be used in an incorrect context
    #> 

![Pipeline
Network](https://github.com/eco-emma/emma_envdata/releases/download/readme-assets/network.png)

## Pipeline Health

| Status     | Count | Percent (%) |
|:-----------|------:|------------:|
| errored    |     1 |         0.5 |
| never run  |    94 |        47.5 |
| up-to-date |   103 |        52.0 |

Pipeline Target Status Summary {.table .table-striped .table-hover
quarto-postprocess="true"
style="margin-left: auto; margin-right: auto;"}

[![Build
Status](https://github.com/eco-emma/emma_envdata/workflows/targets/badge.svg)](https://github.com/eco-emma/emma_envdata/actions)
**Last pipeline run:** 2026-06-19 05:36:55.815952

## Data Inventory

| Dataset | Source | Type | Format | Release Tag | Time Steps | Date Updated |
|:---|:---|:---|:---|:---|---:|:---|
| MODIS VI (Terra + Aqua) | MOD13A1 + MYD13A1 | Dynamic | COG GeoTIFF + Parquet | vi_modis_raster | 5 | 2026-05-16T23:59:59Z |
| VIIRS VI (S-NPP + NOAA-20) | VNP13A1 + VJ113A1 | Dynamic | COG GeoTIFF + Parquet | vi_viirs_raster | 5 | 2026-05-16T23:59:59Z |
| MODIS Burned Area | MCD64A1 | Dynamic | COG GeoTIFF + Parquet | burn_modis_raster | 5 | NULL |
| VIIRS Burned Area | VNP64A1 | Dynamic | COG GeoTIFF + Parquet | burn_viirs_raster | 5 | NULL |
| Fire History (derived) | Multi-sensor merge | Dynamic | COG GeoTIFF | firehistory_dynamic | 1 | 2026-06-19 |
| Domain Grid | NVM2024 + RLE2021 | Static | COG GeoTIFF + Parquet | static_data | 1 | 2026-06-18 13:46:26.474895 |
| Vegetation Map | NVM2024 | Static | COG GeoTIFF | static_data | 1 | 2026-06-18 13:53:11.417559 |
| Elevation | NASADEM | Static | COG GeoTIFF | static_data | 1 | 2026-06-18 13:56:29.827807 |
| Climate | CHELSA BIO1-19 | Static | GeoTIFF (19 layers) | static_data | 19 | 2026-06-18 13:46:34.044251 |
| Cloud Frequency | MODCF (EarthEnv) | Static | COG GeoTIFF | static_data | 1 | 2026-06-18 13:48:11.14382 |
| Soil Properties | SoilGrids v2 | Static | COG GeoTIFF | static_data | 1 | 2026-06-18 13:49:33.055107 |
| Topographic Diversity | Derived from NASADEM | Static | COG GeoTIFF | static_data | 1 | 2026-06-19 05:19:37.36503 |

EMMA Environmental Data Inventory {.table .table-striped .table-hover
.table-condensed quarto-postprocess="true"
style="margin-left: auto; margin-right: auto;"}

## Temporal Coverage

![](https://github.com/eco-emma/emma_envdata/releases/download/readme-assets/temporal-coverage-1.png)

## Domain Statistics

|                   |                            |
|:------------------|:---------------------------|
| Total Pixels      | 900,723                    |
| Spatial Extent    | 17°E to 33°E, 28°S to 35°S |
| CRS               | EPSG:4326 (WGS84)          |
| Resolution        | 500m                       |
| Domain Area (km²) | 225,181                    |

## Data Visualizations

### Most Recent Enhanced Vegetation Index (EVI)

![](https://github.com/eco-emma/emma_envdata/releases/download/readme-assets/evi-map-1.png)

### Time Since Fire

![](https://github.com/eco-emma/emma_envdata/releases/download/readme-assets/fire-age-map-1.png)

### Static Environmental Covariates

![](https://github.com/eco-emma/emma_envdata/releases/download/readme-assets/elevation-map-1.png)
![](https://github.com/eco-emma/emma_envdata/releases/download/readme-assets/temp-map-1.png)
![](https://github.com/eco-emma/emma_envdata/releases/download/readme-assets/precip-map-1.png)

![](https://github.com/eco-emma/emma_envdata/releases/download/readme-assets/soil-map-1.png)
![](https://github.com/eco-emma/emma_envdata/releases/download/readme-assets/clouds-map-1.png)
![](https://github.com/eco-emma/emma_envdata/releases/download/readme-assets/topo-map-1.png)

<div>

</div>

## STAC Catalog

All datasets are cataloged following the [SpatioTemporal Asset Catalog
(STAC)](https://stacspec.org/) specification. The catalog is available
at:

**🔗 [EMMA STAC
Catalog](https://github.com/eco-emma/emma_envdata/releases/download/stac/catalog.json)**

### Accessing Data with `rstac`

``` r
library(rstac)
library(arrow)

# Connect to STAC catalog
stac_url <- "https://github.com/eco-emma/emma_envdata/releases/download/stac"
catalog <- stac(paste0(stac_url, "/catalog.json"))

# Browse VI collection
vi_collection <- stac(paste0(stac_url, "/vi/vi_collection.json"))

# Search for specific date range
results <- stac_search(
  q = vi_collection,
  datetime = "2026-03-01/2026-05-31"
) %>%
  get_request()

# Access data from a specific item
item <- results$features[[1]]
terra_evi_url <- item$assets$modis_terra_vi$href

# Read the COG directly
library(terra)
evi_raster <- rast(paste0("/vsicurl/", terra_evi_url))

# Or read parquet files directly
parquet_url <- item$assets$data$href  # if available
df <- arrow::read_parquet(parquet_url)
```

## STAC Validation Status

|                     |            |
|:--------------------|:-----------|
| Total Links Checked | NULL       |
| Valid Links         | NULL       |
| Broken Links        | NULL       |
| Validation Status   | ❌ FAIL \| |

## GitHub Release Assets

| Release Tag | Description | Asset Count |
|:---|:---|:---|
| static_data | Static environmental layers | 8+ |
| vi_modis_raster | MODIS VI rasters | data/stac/vi/vi_20260313.json composites × 2 sensors, data/stac/vi/vi_20260329.json composites × 2 sensors, data/stac/vi/vi_20260414.json composites × 2 sensors, data/stac/vi/vi_20260430.json composites × 2 sensors, data/stac/vi/vi_20260516.json composites × 2 sensors |
| vi_viirs_raster | VIIRS VI rasters | data/stac/vi/vi_20260313.json composites × 2 sensors, data/stac/vi/vi_20260329.json composites × 2 sensors, data/stac/vi/vi_20260414.json composites × 2 sensors, data/stac/vi/vi_20260430.json composites × 2 sensors, data/stac/vi/vi_20260516.json composites × 2 sensors |
| burn_modis_raster | MODIS burned area rasters | 5 months |
| burn_viirs_raster | VIIRS burned area rasters | 5 months |
| firehistory_dynamic | Fire history snapshot | 1 |
| stac | STAC catalog + items | 50+ |

GitHub Release Summary {.table .table-striped .table-hover
quarto-postprocess="true"
style="margin-left: auto; margin-right: auto;"}

## Data Notes

- **MODIS/VIIRS EVI values**: Stored as `integer × 10000`. To restore:
  `EVI = value / 10000`
- **Fire dates**: Stored as days since 1970-01-01 (Unix epoch)
- **Time since fire**: Right-censored for pixels with no observed fire
  (age ≥ time since 2000-01-01)
- **Multi-sensor fire detection**: Priority order: CapeNature
  ground-truth \> VIIRS (375m) \> MODIS (500m)
- **Coordinate Reference System**: All rasters are in EPSG:4326 (WGS84)
  at 500m resolution
- **Cloud-Optimized GeoTIFFs**: All rasters use COG format for efficient
  cloud access via `/vsicurl/`

## Repository Structure

    ├── _targets.R          # Pipeline definition
    ├── R/                  # Processing functions
    ├── data/
    │   ├── target_outputs/ # Processed data (local)
    │   └── stac/          # STAC catalog JSONs
    ├── docs/              # Documentation
    └── README.qmd         # This file (renders to README.md)

## Setup Instructions

### Required Packages

Install all dependencies:

``` r
remotes::install_deps()
```

### Credentials

This pipeline requires: - **NASA EarthData credentials** (for AppEEARS
API): Set `EARTHDATA_USER` and `EARTHDATA_PASSWORD` environment
variables - **GitHub Personal Access Token** (for release uploads): Use
`gitcreds::gitcreds_set()`

### Running the Pipeline

``` r
# Load targets
library(targets)

# View pipeline
tar_visnetwork()

# Run full pipeline
tar_make()

# Run specific targets
tar_make(c(domain.tif, elevation.tif))
```

## Citation

[![](https://zenodo.org/badge/421127852.svg)](https://zenodo.org/badge/latestdoi/421127852)

## License

This project is licensed under the MIT License. See
[LICENSE.md](LICENSE.md) for details.

Individual datasets retain their original licenses (CC-BY-4.0 for most
satellite products).
