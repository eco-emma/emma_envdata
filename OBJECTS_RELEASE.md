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

## Clear a local copy

```r
unlink("_targets/objects", recursive = TRUE)
unlink("_targets/meta", recursive = TRUE)
unlink("_targets/user/cache", recursive = TRUE)
```

The next `tar_make()` on CCR recomputes. On Actions, the next run downloads
the shards again.
