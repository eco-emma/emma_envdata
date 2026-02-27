# Target Objects Release (`objects_current`)

This GitHub release contains cached computational artifacts from the emma_envdata workflow pipeline using content-addressable storage. Objects are stored with hash-based filenames for deduplication and efficient caching, enabling the workflow to avoid redundant computation of expensive intermediate datasets.

## Contents

This release stores two types of objects:

### File Outputs (Spatial Data)
Published directly as files on the release such as parquet and netCDF files. However, due to the targets workflow's content-addressable storage system, these files are referenced by their content hash in the workflow metadata. The targets workflow automatically manages hash lookups and downloads based on content.

### Serialized R Objects (Intermediate Results)
Stored with hash-based filenames (content-addressable storage) for efficient deduplication. These intermediate objects are serialized as QS files (`.qs`) and referenced by content hash on the release page. The targets workflow automatically manages hash lookups and downloads based on content.


## How the Workflow Uses These Objects

### Prime Mode (Full Processing)
When running on the analysis server (`run_mode = "prime"`), the workflow:
1. **Retrieves** objects from this release using the `tar_github_release_repo()` backend
2. **Caches locally** in `data/target_outputs/.tar_cache/` for speed
3. **Recomputes** targets only if:
   - Source code has changed
   - Input data has changed
   - Objects are manually invalidated with `tar_invalidate()`
4. **Uploads** new/modified targets back to this release

### Update Mode (GitHub Actions)
When running on GitHub Actions (`run_mode = "update"`), the workflow:
1. **Retrieves** all cached objects from this release
2. **Never recomputes** (cue mode = "never") to save CI/CD time
3. **Uses cached objects** for downstream operations only
4. **Skips** expensive computations (elevation API calls, climate downloads) unless manually invalidated

This separation allows:
- **Local development** with full control and recomputation
- **Efficient CI/CD** that leverages pre-computed intermediate results
- **Reproducibility** by pinning exact object versions in the release

## File Formats & Storage

### Spatial Files (NetCDF)
Published with human-readable filenames on the release:
- `.nc` files are CF-1.8 compliant netCDF4 format
- Include geospatial metadata (CRS, bounds, variable attributes)
- Can be read with standard tools (GDAL, xarray, R terra/ncdf4)

### Serialized Objects (QS Format)
Stored with hash-based filenames (content-addressable storage):
- `.qs` files are R object serializations (fast, lossless)
- Filenames are SHA-256 hashes of content
- Hash naming enables deduplication: identical objects share one file
- Managed transparently by targets—humans don't interact with hashes directly
- Only the workflow's metadata tracks which hash corresponds to which target

## When Objects Are Updated

Objects in this release are regenerated and pushed automatically when:
1. Running `tar_make()` on the analysis server with changes to:
   - R functions in `R/` folder
   - Data download URLs or APIs
   - Target definitions in `_targets.R`
2. Manual `tar_make(targets = "target_name")` calls
3. Scheduled workflows or CI/CD pipelines

## Accessing Objects

### Automatic (Preferred)
Objects are automatically retrieved by `tar_load()` and `tar_read()`:
```r
tar_load(elevation)  # Loads from cache or downloads from release
```

### Manual Download
To download specific objects manually:
```bash
gh release download objects_current --dir data/target_outputs
```

## Cache Management

The local cache in `data/target_outputs/.tar_cache/` can be cleared to force re-downloads:
```r
unlink("data/target_outputs/.tar_cache", recursive = TRUE)
tar_make()  # Will re-download from release
```

## Hash-to-File Mapping

The targets metadata stores the relationship between hash-based filenames and human-readable target names. To view this mapping:

```r
# Show all targets with their store information
tar_manifest() %>% 
  select(name, type, path, repository) %>%
  filter(!is.na(path))  # Only file-based targets
```

This shows:
- **name**: Target name (e.g., `domain_boundary.parquet`, `elevation`)
- **type**: Object type (e.g., "file", "qs")
- **path**: Output file path (for file targets like NetCDF)
- **repository**: Storage location (gh_repo for GitHub release objects)

For serialized R objects without human-readable filenames, the mapping is stored in `_targets/meta/objects/` as metadata files that track content hashes.

## Troubleshooting

**Objects not loading?**
- Check GitHub credentials: `gitcreds::gitcreds_set()`
- Verify network connectivity
- Clear cache and retry: `unlink("data/target_outputs/.tar_cache", recursive = TRUE)`

**Out-of-sync objects?**
- Invalidate and recompute: `tar_invalidate(target_name)`
- Rebuild all: `tar_destroy(); tar_make()`

**Need to recompute everything?**
```r
unlink("_targets", recursive = TRUE)  # Clear all metadata
unlink("data/target_outputs/.tar_cache", recursive = TRUE)  # Clear cache
tar_make()  # Recompute all targets
```

## Related Files

- [`_targets.R`](https://github.com/AdamWilsonLab/emma_envdata/blob/main/_targets.R) - Workflow pipeline definition
- [`R/`](https://github.com/AdamWilsonLab/emma_envdata/tree/main/R) - R functions that generate these objects
- [DESCRIPTION](https://github.com/AdamWilsonLab/emma_envdata/blob/main/DESCRIPTION) - Package dependencies
