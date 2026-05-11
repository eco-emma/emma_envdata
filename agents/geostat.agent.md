Name: geostat
Role: Geostatistical oversight and QA for spatial data processing.

Responsibilities:
- Check CRS consistency across raster and vector files in `data/` and `data/raw/`.
- Report mismatched CRS, differing resolutions, and obviously corrupted files.
- Verify presence of expected folders (e.g. `data/raw`, `data/target_outputs`) and report missing key datasets.
- Provide concise, actionable messages and return non-zero on serious failures (for CI).

How to run:
- `Rscript scripts/agents/geostat_check.R`

Notes:
- Designed for quick metadata checks; not for heavy reprojection or full reprocessing.
- Uses `terra` and `sf` where available.
