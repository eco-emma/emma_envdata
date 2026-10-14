# Manual Downloads

This folder holds local copies of files that are awkward to fetch from
upstream portals on every run. **Park boundary inputs are not SoT here** —
they live as **flat assets** on the GitHub release tag
[`manual-data`](https://github.com/eco-emma/emma_envdata/releases/tag/manual-data)
(no nested folders such as `provincial_park/`).

## `manual-data` release (flat assets — park inputs)

Park writers download by **asset name** into a temp work dir, for example:

| Asset stem | Sidecars (required) |
|---|---|
| `SACAD_OR_2021_Q4` | `.shp` `.shx` `.dbf` `.prj` (+ optional `.cpg`) |
| `SAPAD_OR_2021_Q4` | same |
| `CapeNature_Reserves_gw` | `.shp` `.shx` `.dbf` `.prj` |

Also on the same tag (non-park): `RLE_2021_Remnants.zip`, PDFs, optional
legacy `protected_areas.gpkg` (inputs only — **not** the report SoT).

Processed park products for `emma_report` are published to **`static_data`**:

| Asset | Meaning |
|---|---|
| `protected_areas.gpkg` | Dissolved parks (`name`, `type`, `area_ha`); EPSG:9221 |
| `domain_outline.gpkg` | Dissolved domain polygon |
| `parks_buffer_10km.gpkg` | 10 km buffer of parks **only** (iNat AOI; no domain union) |

`park_pids.parquet` is **not** shipped in v1 (needs domain/`pid` co-versioning).

## Current local datasets

- **NVM2024/** — South African National Vegetation Map (2024 release), shapefile format.
  Downloaded from [SANBI BGIS](https://bgis.sanbi.org/SpatialDataset/Detail/2287).
  Also mirrored on release tag `vegmap2024`.
- **RLE_2021_Remnants/** — Remaining natural vegetation remnants (Red List of Ecosystems 2021).
  Prefer `get_remnants()` which pulls `RLE_2021_Remnants.zip` from `manual-data`.
- **All_fires_23_24_gw/** — Fire perimeter data for 2023–2024 (CapeNature fires).
- **VEGMAP2018_AEA_16082019Final/** — Legacy vegetation map (2018 release); retained for reference.

## Adding New Datasets

1. Prefer uploading **flat** assets to the `manual-data` release (no nested paths).
2. For CCR-only local mirrors, create a subdirectory and update `_targets.R`.
3. Add an entry to this README with a description and source URL.
