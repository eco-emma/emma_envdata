# Manual Downloads

This folder contains files that cannot be programmatically downloaded.

## Current Datasets

- **NVM2024/** — South African National Vegetation Map (2024 release), shapefile format.
  Downloaded from [SANBI BGIS](https://bgis.sanbi.org/SpatialDataset/Detail/2287).
- **RLE_2021_Remnants/** — Remaining natural vegetation remnants (Red List of Ecosystems 2021), shapefile format.
  Downloaded from [SANBI BGIS](https://bgis.sanbi.org).
- **All_fires_23_24_gw/** — Fire perimeter data for 2023–2024.
- **VEGMAP2018_AEA_16082019Final/** — Legacy vegetation map (2018 release); retained for reference.

## Adding New Datasets

1. Create a subdirectory with a descriptive name (e.g., `DatasetName_YYYY/`).
2. Download files directly into that directory.
3. Update `_targets.R` to reference the new path.
4. Add an entry to this README with a description and source URL.
