# Targets cache on GitHub Releases

The pipeline stores targets objects on GitHub Releases. The base tag is
`targets-cache`. Objects are spread across four shard releases,
`targets-cache-1` through `targets-cache-4`, because a single release holds
about 1,000 assets. `_targets_meta` is an asset on shard 1.

`repository` is `"local"` and the default format is `"rds"`. Objects live in
`_targets/objects/` during a run. GitHub Actions restores them into that
directory, using `_targets/user/cache` as the download cache, before
`tar_make()`.

## Who writes the cache

- **CCR** (`run_tar_make.sh`) builds history. After `tar_make()` finishes,
  upload with `tar_upload_github_release()`. That function uploads objects
  first and writes `_targets_meta` only when every object upload succeeded.
- **GitHub Actions** restores the shards, then runs `tar_make()` for targets
  that are out of date. If `_targets/meta/meta` was not restored, the run
  stops. The workflow uploads the cache only after `tar_make()` succeeds.

Static and manual targets use `cue = tar_cue(mode = "never")`. They have to
already be in the cache before Actions is trusted. Input releases that a
reset must keep are `vegmap2024` and `manual-data`.

Product COGs, Parquet files, and STAC JSON are separate releases. Their tag
names are the `release_tags` list in `_targets.R`.

## Park products on `static_data`

Park boundary products for `emma_report` are written by
`R/process_park_polygons.R` / targets `park_static_products` +
`upload_park_static` (cue `never`).

| Role | Tag | Assets |
|------|-----|--------|
| Inputs | `manual-data` | Flat SACAD / SAPAD / CapeNature shapefile sidecars (by name; no folders) |
| Outputs | `static_data` | `protected_areas.gpkg`, `domain_outline.gpkg`, `parks_buffer_10km.gpkg` |

**First publish is CCR** (not the nightly AppEEARS Actions job). After merge:

```bash
# On CCR interactive / batch node inside the emma Apptainer image, repo root:
git pull
Rscript R/publish_park_static.R
# or: targets::tar_make(c(park_static_products, upload_park_static))
```

Optional later: Actions workflow `publish-parks` (`workflow_dispatch` only).
Do not ship `park_pids.parquet` until domain/`pid` co-versioning exists.

## Clear a local copy

```r
unlink("_targets/objects", recursive = TRUE)
unlink("_targets/meta", recursive = TRUE)
unlink("_targets/user/cache", recursive = TRUE)
```

The next `tar_make()` on CCR recomputes. On Actions, the next run downloads
the shards again.

## Weather products on `weather_data`

GSOD harvest + station metadata for `emma_report` are written by
`R/process_weather_gsod.R` / CLI `R/publish_weather.R`.

| Role | Tag | Assets |
|------|-----|--------|
| Input | `static_data` | `protected_areas.gpkg` (parks Phase B; 100 km station filter) |
| Outputs | `weather_data` | `weather.parquet`, `stations.gpkg` |

**First publish is CCR** (not the nightly AppEEARS Actions job). After parks
`protected_areas.gpkg` exists on `static_data`:

```bash
# On CCR interactive / batch node inside the emma Apptainer image, repo root:
git pull
Rscript R/publish_weather.R
```

Default year window = last 5 calendar years (`WEATHER_MIN_YEAR` overrides).
Optional later: Actions workflow `publish-weather` (`workflow_dispatch` only).
See `docs/WEATHER_DATA_PUBLISH.md`.
