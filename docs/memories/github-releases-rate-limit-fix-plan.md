# Plan: Fix GitHub Releases rate-limiting & NA-data poisoning in emma_envdata targets pipeline

## Context / root causes confirmed
- Repo: emma_envdata, R `targets` pipeline, GitHub Releases used as object store (per-dataset tags) + as
  a shard cache for `_targets/objects` + `_targets/meta` (`R/tar_release_storage.R`, tag `targets-cache`).
- Burn/VI data acquired via async NASA AppEEARS jobs (submit -> poll -> download), R/get_burn_dates_viirs.R,
  R/get_burn_dates_modis.R (VI equivalents: R/get_modis_vi.R, R/get_viirs_vi.R).
- CONFIRMED: NA-grid fallback (`write_empty_cog()`) is NOT the primary bug — timeouts/expired tasks already
  `stop()` (get_burn_dates_viirs.R L260-286), letting `error="continue"` retry on next run. All-NA grid is
  only written when AppEEARS task genuinely completed with zero returned tif files, OR local/remote cached
  grid already exists (guarded). Residual risk: `appeears::rs_transfer()` failure (network/API) between
  "done" status and tif-file check is NOT wrapped in tryCatch — a transfer error would silently look like
  "0 tif files" and get miscategorized as confirmed-no-data. This is the one real gap to fix.
- CONFIRMED real root cause of HTTP 403 "API rate limit exceeded for installation": burn grid / fireage /
  STAC upload targets hard-code `overwrite = TRUE` in `_targets.R` (lines ~796, 879, 894, 912, 969, 1039),
  so `upload_to_github_release()` (R/upload_releases.R) deletes+re-POSTs EVERY file in the target's file
  list on EVERY run, even files whose content hasn't changed (176 VIIRS + 320 MODIS + fireage + STAC files
  every single run). This is what exhausts the GitHub Actions installation token's REST rate limit
  (visible in the log: successful reuploads of old 2020s months immediately before the 403s start).
- User can "prime" releases by running full historical `tar_make()` + uploads on a local server with ample
  storage/bandwidth once. Steady-state GitHub Actions runs would then only need to process the newest
  month/composite each week — this removes almost all backfill volume from CI, but does NOT by itself fix
  the overwrite=TRUE reupload-everything bug (that still reuploads full history every run regardless of
  how much is new).

## User decisions (from clarifying questions)
- Scope: **targeted fix**, not full redesign — keep GitHub Releases as the backend.
- Storage backend: stay within GitHub (no external cloud bucket).
- AppEEARS execution model: prefers **separate submit/poll workflows** (lower priority now that priming
  removes most backlog — still useful for fast turnaround on new incoming months).
- Existing bad placeholders: **audit and reprocess** as part of this work.
- Output granularity: **open to batching** (e.g., per-year instead of per-month files) to cut API calls.
- User will **prime** releases via a one-time full local run before relying on CI for incremental updates.

## Steps

### Phase 1 — Fix the real bugs (do first, before priming)
1. **R/upload_releases.R / `_targets.R`**: Replace blanket `overwrite = TRUE` reupload-everything behavior
   with hash-aware upload: before delete+POST, compare local file hash/size against the existing release
   asset (reuse the same hash-comparison pattern already implemented in `tar_upload_github_release()`,
   R/tar_release_storage.R L411-430) and skip upload when unchanged. Apply to the burn_modis_grid,
   burn_viirs_grid, fireage, and STAC upload targets (`_targets.R` ~L873-969, ~L1034).
2. **R/get_burn_dates_viirs.R / R/get_burn_dates_modis.R**: wrap `appeears::rs_transfer()` in `tryCatch`
   and `stop()` on failure (do not let a transfer error fall through to the "0 tif files -> confirmed
   empty" branch). Mirror the fix in both files (VIIRS ~L292-304, MODIS equivalent).
3. *(parallel with 1-2)* Add basic backoff/jitter + honor `Retry-After` header in `upload_to_github_release()`
   HTTP calls as a defense-in-depth measure against secondary rate limits.

### Phase 2 — Audit & reprocess existing bad placeholders
4. Write a one-off maintenance script (`R/audit_na_placeholders.R`, run manually, not part of
   `_targets.R`) that:
   - Lists all-NA `.tif` grids on `burn_modis_raster` / `burn_viirs_raster` releases (and any `.skip`
     markers) alongside local `data/target_outputs/burndates/`.
   - Cross-checks against known valid sensor date ranges (VNP64A1 VIIRS starts ~2012-01; MCD64A1 MODIS
     starts ~2000-11) to flag suspicious NA months (i.e., NA surrounded by real data — likely a past
     transfer failure, not genuine no-fire).
   - For flagged months: delete the bad placeholder file from disk + release asset. No
     `tar_invalidate()` needed — `targets` format="file" targets detect the now-missing file and rebuild
     automatically on the next `tar_make()`.
   - *(depends on Phase 1 landing first, so reprocessing doesn't re-trigger the same bug)*

### Phase 3 — Priming run (user-run, local, after Phase 1 fixes land)
5. On a local server with ample storage/bandwidth: run full `tar_make()` for entire historical backfill
   (VI MODIS/VIIRS 2000/2012–present, burn MODIS/VIIRS 2000/2012–present), then run
   `tar_upload_github_release()` (targets-cache) and all per-dataset `upload_*` targets to fully seed every
   release tag. This must happen after Phase 1 so priming doesn't ship the same reupload/poisoning bugs.

### Phase 4 — Lightweight polling workflow (optional, do after Phase 3, lower priority)
6. Add a small second GitHub Actions workflow (e.g. `.github/workflows/appeears-poll.yaml`) on a more
   frequent schedule (e.g. hourly) that only runs a narrow `tar_make(names = ...)` subset covering the
   task_ids/geotiff acquisition targets (not the full grid/upload pipeline), so newly-submitted AppEEARS
   jobs for the current month get downloaded within hours instead of waiting for the next weekly run.
   Main `targets.yaml` continues to run weekly for full grid/merge/STAC/upload processing.

### Phase 5 — Batching (optional follow-up, bigger refactor, discuss timing separately)
7. If API volume is still a concern after Phases 1-4, consolidate monthly/16-day composite output files
   into fewer larger assets (e.g. one multi-band per-year COG per dataset instead of per-month files),
   cutting release asset counts ~12x. This touches grid-writing functions, STAC item generation, and
   downstream parquet extraction — larger change, do only if needed after measuring Phase 1-4 impact.

## Relevant files
- `_targets.R` — upload target definitions (overwrite=TRUE spots), AppEEARS target wiring (pending/task_ids/geotiff/grid pattern per dataset)
- `R/upload_releases.R` — `upload_to_github_release()`, now has hash-aware skip logic (Phase 1)
- `R/tar_release_storage.R` — existing hash-comparison pattern reused (L411-430), `.check_file_integrity()`, `gh_release_has_asset()`
- `R/get_burn_dates_viirs.R`, `R/get_burn_dates_modis.R` — transfer error handling fix, NA-fallback logic (`write_empty_cog()`, `.skip` markers)
- `R/get_modis_vi.R`, `R/get_viirs_vi.R` — same "skip marker" pattern for VI, same transfer-error gap fixed
- `.github/workflows/targets.yaml` — existing weekly workflow; new `appeears-poll.yaml` if Phase 4 pursued
- `R/audit_na_placeholders.R` — one-off maintenance script (Phase 2)

## Verification
1. After Phase 1: trigger a manual `workflow_dispatch` run on a branch with a handful of new months pending;
   confirm log shows uploads only for genuinely new/changed files, no reupload of untouched historical months.
2. Confirm no HTTP 403 rate-limit messages in a full run log.
3. Unit-test / manually invoke `download_burn_date_viirs_geotiff()`/modis equivalent with a mocked
   `rs_transfer()` failure to confirm it now `stop()`s instead of writing a `.skip` marker.
4. After Phase 2 script: spot check a handful of previously-NA months (e.g. 201201-201206 VIIRS) either
   get reprocessed with real data or are confirmed+documented as genuinely pre-launch/no-data.
5. After Phase 3 priming: confirm all release tags (`burn_modis_raster`, `burn_viirs_raster`,
   `vi_modis_raster`, `vi_viirs_raster`, etc.) have full historical asset counts before re-enabling
   scheduled CI runs.

## Decisions
- Keep GitHub Releases as backend (no external cloud storage) — targeted fix only.
- Priming shifts bulk backfill off CI entirely; CI becomes incremental-only going forward.
- Batching (Phase 5) deferred unless Phases 1-4 don't sufficiently reduce API volume.

## Implementation progress
- Phase 1 steps 1-3 DONE (2026-09-18):
  - `R/upload_releases.R`: added `.gh_release_remote_checksums()` (reads the
    existing `{release_tag}_SHA256SUMS.txt` sidecar) and changed
    `upload_to_github_release()` so `overwrite=TRUE` now hash-compares each
    local file against the remote checksum sidecar and only reuploads
    changed/new files (previously reuploaded ALL files unconditionally —
    this was the main root cause of the HTTP 403 rate-limit errors).
  - `R/upload_releases.R`: `.gh_upload_release_asset()` POST now uses
    `httr::RETRY()` with secondary-rate-limit detection (429 or 403 containing
    "rate limit") that sleeps 60s and errors so the caller's existing
    per-file `tryCatch`/warning path retries on the next run — mirrors the
    pattern already in `R/tar_release_storage.R`.
  - `R/get_burn_dates_viirs.R`, `R/get_burn_dates_modis.R`,
    `R/get_modis_vi.R`, `R/get_viirs_vi.R`: wrapped `appeears::rs_transfer()`
    calls in `tryCatch`/`stop()` so a transfer failure errors the branch
    (retried via `error="continue"`) instead of falling through to the
    "0 tif files -> confirmed empty -> write NA/skip marker" path.
  - All 5 files parse cleanly (`Rscript -e "parse(f)"`, no errors).
  - NOT YET DONE: Phase 3 (user's local priming run), Phase 4 (optional poll
    workflow), Phase 5 (batching).
  - NOT YET DONE: no unit/integration test run against live AppEEARS/GitHub
    API — changes are code-reviewed + parse-checked only so far.

- Phase 2 DONE (2026-09-18): created `R/audit_na_placeholders.R` (one-off
  maintenance script, NOT sourced by `_targets.R`):
  - `audit_burn_na_grids(dataset, valid_start, dry_run=TRUE)` — for
    burn_modis/burn_viirs: scans local `data/target_outputs/burndates/*.tif`,
    flags all-NA content within [valid_start, today - min_age_days]. Burn
    placeholders have no distinguishing metags tag (write_empty_cog() sets
    the same metags whether genuinely empty or bugged), so all-NA content is
    the only signal — this means genuinely-empty real months will also get
    reprocessed, which is fine/idempotent (will just rewrite the same NA
    grid, now honestly, since the rs_transfer fix landed).
  - `audit_vi_na_grids(dataset, sensors, valid_start, dry_run=TRUE)` — for
    vi_modis (sensors terra/aqua) / vi_viirs (sensors snpp/noaa20): checks
    `terra::metags(r)[["source"]] == "no_data"`, a reliable placeholder flag
    set only by write_na_cog() in R/get_modis_vi.R / R/get_viirs_vi.R.
  - `audit_skip_markers(local_dir, valid_start, dry_run=TRUE)` — deletes
    stale `.skip` marker files (no release-asset cleanup needed; skip
    markers are local-only, never uploaded).
  - All three default to `dry_run = TRUE` (report only); set `dry_run=FALSE`
    to actually delete local file + matching GitHub release asset. No
    `tar_invalidate()` needed — `targets` format="file" targets detect the
    now-missing file and rebuild automatically on the next `tar_make()`.
  - File parses cleanly (`Rscript -e "parse(...)"`).
  - Not yet run against real data/releases — user should dry-run first and
    review flagged months before setting dry_run=FALSE.

## Further Considerations
1. Phase 4 (separate polling workflow) may be unnecessary once priming is done, since steady-state new-data
   volume per week is tiny and the existing stop()/retry-next-run pattern already resumes across weekly
   runs — recommend deferring Phase 4 until proven necessary.
2. Should Phase 2's audit script auto-invalidate+reprocess in CI, or only flag findings for manual review
   before deleting anything from the live releases? Recommend manual review first given it deletes data.
