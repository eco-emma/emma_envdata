

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
    #> System info: sysname=Linux; release=6.8.0-138-generic; version=#138-Ubuntu SMP PREEMPT_DYNAMIC Fri Jul 31 22:41:49 UTC 2026; nodename=cpn-c08-13.core.ccr.buffalo.edu; machine=x86_64; login=unknown; user=adamw; effective_user=adamw
    #> Set working directory to: /projects/academic/adamw/projects/emma/emma_envdata
    #> tar_source() only sources R scripts. Ignoring non-R files: R/ccr_startup.sh
    #> stac: found 0 junk sidecar asset(s)
    #> burn_modis_raster: found 0 junk sidecar asset(s)
    #> static_data: found 0 junk sidecar asset(s)
    #> Found 1121 local STAC JSON files to backfill
    #> Using existing release 'stac'
    #> Uploading 1121 files to release 'stac'
    #>   Uploading: burn_collection.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200001.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200002.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200003.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200004.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200005.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200006.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200007.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200008.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200009.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200010.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200011.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200012.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200101.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200102.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200103.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200104.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200105.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200106.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200107.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200108.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200109.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200110.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200111.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200112.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200201.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200202.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200203.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200204.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200205.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200206.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200207.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200208.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200209.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200210.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200211.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200212.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200301.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200302.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200303.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200304.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200305.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200306.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200307.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200308.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200309.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200310.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200311.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200312.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200401.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200402.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200403.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200404.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200405.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200406.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200407.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200408.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200409.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200410.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200411.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200412.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200501.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200502.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200503.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200504.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200505.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200506.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200507.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200508.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200509.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200510.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200511.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200512.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200601.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200602.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200603.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200604.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200605.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200606.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200607.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200608.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200609.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200610.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200611.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200612.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200701.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200702.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200703.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200704.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200705.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200706.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200707.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200708.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200709.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200710.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200711.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200712.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200801.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200802.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200803.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200804.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200805.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200806.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200807.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200808.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200809.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200810.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200811.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200812.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200901.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200902.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200903.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200904.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200905.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200906.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200907.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200908.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200909.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200910.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200911.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_200912.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201001.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201002.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201003.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201004.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201005.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201006.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201007.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201008.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201009.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201010.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201011.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201012.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201101.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201102.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201103.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201104.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201105.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201106.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201107.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201108.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201109.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201110.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201111.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201112.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201201.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201202.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201203.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201204.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201205.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201206.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201207.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201208.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201209.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201210.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201211.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201212.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201301.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201302.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201303.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201304.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201305.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201306.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201307.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201308.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201309.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201310.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201311.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201312.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201401.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201402.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201403.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201404.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201405.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201406.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201407.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201408.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201409.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201410.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201411.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201412.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201501.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201502.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201503.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201504.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201505.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201506.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201507.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201508.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201509.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201510.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201511.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201512.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201601.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201602.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201603.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201604.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201605.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201606.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201607.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201608.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201609.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201610.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201611.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201612.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201701.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201702.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201703.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201704.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201705.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201706.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201707.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201708.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201709.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201710.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201711.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201712.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201801.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201802.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201803.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201804.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201805.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201806.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201807.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201808.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201809.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201810.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201811.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201812.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201901.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201902.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201903.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201904.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201905.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201906.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201907.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201908.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201909.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201910.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201911.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_201912.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202001.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202002.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202003.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202004.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202005.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202006.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202007.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202008.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202009.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202010.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202011.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202012.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202101.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202102.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202103.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202104.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202105.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202106.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202107.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202108.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202109.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202110.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202111.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202112.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202201.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202202.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202203.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202204.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202205.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202206.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202207.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202208.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202209.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202210.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202211.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202212.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202301.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202302.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202303.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202304.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202305.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202306.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202307.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202308.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202309.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202310.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202311.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202312.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202401.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202402.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202403.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202404.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202405.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202406.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202407.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202408.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202409.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202410.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202411.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202412.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202501.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202502.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202503.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202504.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202505.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202506.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202507.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202508.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202509.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202510.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202511.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202512.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202601.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202602.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202603.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202604.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202605.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202606.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202607.json
    #>     ✓ Uploaded
    #>   Uploading: burn_modis_202608.json
    #>     ✓ Uploaded
    #>   Uploading: burn_recentburn.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201201.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201202.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201203.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201204.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201205.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201206.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201207.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201208.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201209.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201210.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201211.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201212.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201301.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201302.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201303.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201304.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201305.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201306.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201307.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201308.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201309.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201310.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201311.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201312.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201401.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201402.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201403.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201404.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201405.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201406.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201407.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201408.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201409.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201410.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201411.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201412.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201501.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201502.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201503.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201504.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201505.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201506.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201507.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201508.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201509.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201510.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201511.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201512.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201601.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201602.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201603.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201604.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201605.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201606.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201607.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201608.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201609.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201610.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201611.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201612.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201701.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201702.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201703.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201704.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201705.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201706.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201707.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201708.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201709.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201710.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201711.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201712.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201801.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201802.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201803.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201804.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201805.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201806.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201807.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201808.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201809.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201810.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201811.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201812.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201901.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201902.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201903.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201904.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201905.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201906.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201907.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201908.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201909.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201910.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201911.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_201912.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202001.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202002.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202003.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202004.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202005.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202006.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202007.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202008.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202009.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202010.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202011.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202012.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202101.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202102.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202103.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202104.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202105.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202106.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202107.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202108.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202109.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202110.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202111.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202112.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202201.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202202.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202203.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202204.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202205.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202206.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202207.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202208.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202209.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202210.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202211.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202212.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202301.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202302.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202303.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202304.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202305.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202306.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202307.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202308.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202309.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202310.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202311.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202312.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202401.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202402.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202403.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202404.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202405.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202406.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202407.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202408.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202409.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202410.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202411.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202412.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202501.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202502.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202503.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202504.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202505.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202506.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202507.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202508.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202509.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202510.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202511.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202512.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202601.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202602.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202603.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202604.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202605.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202606.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202607.json
    #>     ✓ Uploaded
    #>   Uploading: burn_viirs_202608.json
    #>     ✓ Uploaded
    #>   Uploading: catalog.json
    #>     ✓ Uploaded
    #>   Uploading: collection.json
    #>     ✓ Uploaded
    #>   Uploading: fire_history_collection.json
    #>     ✓ Uploaded
    #>   Uploading: fire_history_modis_202605.json
    #>     ✓ Uploaded
    #>   Uploading: fire_history_postfire_age.json
    #>     ✓ Uploaded
    #>   Uploading: fire_history_viirs_202605.json
    #>     ✓ Uploaded
    #>   Uploading: static_climate.json
    #>     ✓ Uploaded
    #>   Uploading: static_clouds.json
    #>     ✓ Uploaded
    #>   Uploading: static_collection.json
    #>     ✓ Uploaded
    #>   Uploading: static_covariates.json
    #>     ✓ Uploaded
    #>   Uploading: static_domain.json
    #>     ✓ Uploaded
    #>   Uploading: static_elevation.json
    #>     ✓ Uploaded
    #>   Uploading: static_soil.json
    #>     ✓ Uploaded
    #>   Uploading: static_topography.json
    #>     ✓ Uploaded
    #>   Uploading: static_vegmap.json
    #>     ✓ Uploaded
    #>   Uploading: validation_report.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000218.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000305.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000321.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000406.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000422.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000508.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000524.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000609.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000625.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000711.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000727.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000812.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000828.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000913.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20000929.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20001015.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20001031.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20001116.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20001202.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20001218.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010103.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010119.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010204.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010220.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010308.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010324.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010409.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010425.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010511.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010527.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010612.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010628.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010714.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010730.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010815.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010831.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20010916.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20011002.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20011018.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20011103.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20011119.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20011205.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20011221.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020106.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020122.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020207.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020223.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020311.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020327.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020412.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020428.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020514.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020530.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020615.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020701.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020717.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020802.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020818.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020903.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20020919.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20021005.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20021021.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20021106.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20021122.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20021208.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20021224.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030109.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030125.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030210.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030226.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030314.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030330.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030415.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030501.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030517.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030602.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030618.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030704.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030720.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030805.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030821.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030906.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20030922.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20031008.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20031024.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20031109.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20031125.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20031211.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20031227.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040112.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040128.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040213.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040229.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040316.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040401.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040417.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040503.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040519.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040604.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040620.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040706.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040722.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040807.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040823.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040908.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20040924.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20041010.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20041026.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20041111.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20041127.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20041213.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20041229.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050114.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050130.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050215.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050303.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050319.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050404.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050420.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050506.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050522.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050607.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050623.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050709.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050725.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050810.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050826.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050911.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20050927.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20051013.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20051029.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20051114.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20051130.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20051216.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060101.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060117.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060202.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060218.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060306.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060322.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060407.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060423.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060509.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060525.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060610.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060626.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060712.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060728.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060813.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060829.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060914.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20060930.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20061016.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20061101.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20061117.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20061203.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20061219.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070104.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070120.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070205.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070221.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070309.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070325.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070410.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070426.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070512.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070528.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070613.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070629.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070715.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070731.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070816.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070901.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20070917.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20071003.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20071019.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20071104.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20071120.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20071206.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20071222.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080107.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080123.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080208.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080224.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080311.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080327.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080412.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080428.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080514.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080530.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080615.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080701.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080717.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080802.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080818.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080903.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20080919.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20081005.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20081021.json
    #> Request failed [403]. Retrying in 1 seconds...
    #> Request failed [403]. Retrying in 1.5 seconds...
    #>   Secondary rate limit hit — sleeping 60s before continuing
    #>   Uploading: vi_20081106.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20081122.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20081208.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20081224.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090109.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090125.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090210.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090226.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090314.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090330.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090415.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090501.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090517.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090602.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090618.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090704.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090720.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090805.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090821.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090906.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20090922.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20091008.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20091024.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20091109.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20091125.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20091211.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20091227.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100112.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100128.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100213.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100301.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100317.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100402.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100418.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100504.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100520.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100605.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100621.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100707.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100723.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100808.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100824.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100909.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20100925.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20101011.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20101027.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20101112.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20101128.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20101214.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20101230.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110115.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110131.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110216.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110304.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110320.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110405.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110421.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110507.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110523.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110608.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110624.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110710.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110726.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110811.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110827.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110912.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20110928.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20111014.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20111030.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20111115.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20111201.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20111217.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120102.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120118.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120203.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120219.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120306.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120322.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120407.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120423.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120509.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120525.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120610.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120626.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120712.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120728.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120813.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120829.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120914.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20120930.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20121016.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20121101.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20121117.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20121203.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20121219.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130104.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130120.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130205.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130221.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130309.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130325.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130410.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130426.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130512.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130528.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130613.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130629.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130715.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130731.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130816.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130901.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20130917.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20131003.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20131019.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20131104.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20131120.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20131206.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20131222.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140107.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140123.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140208.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140224.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140312.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140328.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140413.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140429.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140515.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140531.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140616.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140702.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140718.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140803.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140819.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140904.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20140920.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20141006.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20141022.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20141107.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20141123.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20141209.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20141225.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150110.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150126.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150211.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150227.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150315.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150331.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150416.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150502.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150518.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150603.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150619.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150705.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150721.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150806.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150822.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150907.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20150923.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20151009.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20151025.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20151110.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20151126.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20151212.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20151228.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160113.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160129.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160214.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160301.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160317.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160402.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160418.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160504.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160520.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160605.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160621.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160707.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160723.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160808.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160824.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160909.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20160925.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20161011.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20161027.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20161112.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20161128.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20161214.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20161230.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170115.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170131.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170216.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170304.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170320.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170405.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170421.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170507.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170523.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170608.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170624.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170710.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170726.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170811.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170827.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170912.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20170928.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20171014.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20171030.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20171115.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20171201.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20171217.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180102.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180118.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180203.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180219.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180307.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180323.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180408.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180424.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180510.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180526.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180611.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180627.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180713.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180729.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180814.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180830.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20180915.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20181001.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20181017.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20181102.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20181118.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20181204.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20181220.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20190105.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20190121.json
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20190206.json
    #> Waiting 600s for retry backoff ■                               
    #> Waiting 600s for retry backoff ■                               
    #> Waiting 600s for retry backoff ■                               
    #> Waiting 600s for retry backoff ■                               
    #> Waiting 600s for retry backoff ■■                              
    #> Waiting 600s for retry backoff ■■                              
    #> Waiting 600s for retry backoff ■■                              
    #> Waiting 600s for retry backoff ■■                              
    #> Waiting 600s for retry backoff ■■                              
    #> Waiting 600s for retry backoff ■■                              
    #> Waiting 600s for retry backoff ■■                              
    #> Waiting 600s for retry backoff ■■■                             
    #> Waiting 600s for retry backoff ■■■                             
    #> Waiting 600s for retry backoff ■■■                             
    #> Waiting 600s for retry backoff ■■■                             
    #> Waiting 600s for retry backoff ■■■                             
    #> Waiting 600s for retry backoff ■■■                             
    #> Waiting 600s for retry backoff ■■■■                            
    #> Waiting 600s for retry backoff ■■■■                            
    #> Waiting 600s for retry backoff ■■■■                            
    #> Waiting 600s for retry backoff ■■■■                            
    #> Waiting 600s for retry backoff ■■■■                            
    #> Waiting 600s for retry backoff ■■■■                            
    #> Waiting 600s for retry backoff ■■■■                            
    #> Waiting 600s for retry backoff ■■■■■                           
    #> Waiting 600s for retry backoff ■■■■■                           
    #> Waiting 600s for retry backoff ■■■■■                           
    #> Waiting 600s for retry backoff ■■■■■                           
    #> Waiting 600s for retry backoff ■■■■■                           
    #> Waiting 600s for retry backoff ■■■■■                           
    #> Waiting 600s for retry backoff ■■■■■                           
    #> Waiting 600s for retry backoff ■■■■■■                          
    #> Waiting 600s for retry backoff ■■■■■■                          
    #> Waiting 600s for retry backoff ■■■■■■                          
    #> Waiting 600s for retry backoff ■■■■■■                          
    #> Waiting 600s for retry backoff ■■■■■■                          
    #> Waiting 600s for retry backoff ■■■■■■                          
    #> Waiting 600s for retry backoff ■■■■■■■                         
    #> Waiting 600s for retry backoff ■■■■■■■                         
    #> Waiting 600s for retry backoff ■■■■■■■                         
    #> Waiting 600s for retry backoff ■■■■■■■                         
    #> Waiting 600s for retry backoff ■■■■■■■                         
    #> Waiting 600s for retry backoff ■■■■■■■                         
    #> Waiting 600s for retry backoff ■■■■■■■                         
    #> Waiting 600s for retry backoff ■■■■■■■■                        
    #> Waiting 600s for retry backoff ■■■■■■■■                        
    #> Waiting 600s for retry backoff ■■■■■■■■                        
    #> Waiting 600s for retry backoff ■■■■■■■■                        
    #> Waiting 600s for retry backoff ■■■■■■■■                        
    #> Waiting 600s for retry backoff ■■■■■■■■                        
    #> Waiting 600s for retry backoff ■■■■■■■■                        
    #> Waiting 600s for retry backoff ■■■■■■■■■                       
    #> Waiting 600s for retry backoff ■■■■■■■■■                       
    #> Waiting 600s for retry backoff ■■■■■■■■■                       
    #> Waiting 600s for retry backoff ■■■■■■■■■                       
    #> Waiting 600s for retry backoff ■■■■■■■■■                       
    #> Waiting 600s for retry backoff ■■■■■■■■■                       
    #> Waiting 600s for retry backoff ■■■■■■■■■■                      
    #> Waiting 600s for retry backoff ■■■■■■■■■■                      
    #> Waiting 600s for retry backoff ■■■■■■■■■■                      
    #> Waiting 600s for retry backoff ■■■■■■■■■■                      
    #> Waiting 600s for retry backoff ■■■■■■■■■■                      
    #> Waiting 600s for retry backoff ■■■■■■■■■■                      
    #> Waiting 600s for retry backoff ■■■■■■■■■■                      
    #> Waiting 600s for retry backoff ■■■■■■■■■■■                     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■                     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■                     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■                     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■                     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■                     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■                     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■                    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■                    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■                    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■                    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■                    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■                    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■                   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■                   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■                   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■                   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■                   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■                   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■                   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■                  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■                  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■                  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■                  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■                  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■                  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■                  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■                 
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■                 
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■                 
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■                 
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■                 
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■                 
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■                
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■                
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■                
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■                
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■                
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■                
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■                
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■               
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■               
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■               
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■               
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■               
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■               
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■               
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■              
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■              
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■              
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■              
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■              
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■              
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■             
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■             
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■             
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■             
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■             
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■             
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■             
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■            
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■            
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■            
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■            
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■            
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■            
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■            
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■           
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■           
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■           
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■           
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■           
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■           
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■          
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■          
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■          
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■          
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■          
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■          
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■          
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■         
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■         
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■         
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■         
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■         
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■         
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■         
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■        
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■        
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■        
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■        
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■        
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■        
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■       
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■       
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■       
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■       
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■       
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■       
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■       
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■      
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■      
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■      
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■      
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■      
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■      
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■      
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■     
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■    
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■   
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 
    #> Waiting 600s for retry backoff ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 
    #> To get started with GitHub CLI, please run:  gh auth login
    #> Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.
    #>   Uploading: vi_20190222.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190310.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190326.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190411.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190427.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190513.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190529.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190614.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190630.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190716.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190801.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190817.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190902.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190918.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20191004.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20191020.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20191105.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20191121.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20191207.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20191223.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200108.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200124.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200209.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200225.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200312.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200328.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200413.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200429.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200515.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200531.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200616.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200702.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200718.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200803.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200819.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200904.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20200920.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20201006.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20201022.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20201107.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20201123.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20201209.json
    #>   Uploading: vi_20201225.json
    #>   Uploading: vi_20210110.json
    #>   Uploading: vi_20210126.json
    #>   Uploading: vi_20210211.json
    #>   Uploading: vi_20210227.json
    #>   Uploading: vi_20210315.json
    #>   Uploading: vi_20210331.json
    #>   Uploading: vi_20210416.json
    #>   Uploading: vi_20210502.json
    #>   Uploading: vi_20210518.json
    #>   Uploading: vi_20210603.json
    #>   Uploading: vi_20210619.json
    #>   Uploading: vi_20210705.json
    #>   Uploading: vi_20210721.json
    #>   Uploading: vi_20210806.json
    #>   Uploading: vi_20210822.json
    #>   Uploading: vi_20210907.json
    #>   Uploading: vi_20210923.json
    #>   Uploading: vi_20211009.json
    #>   Uploading: vi_20211025.json
    #>   Uploading: vi_20211110.json
    #>   Uploading: vi_20211126.json
    #>   Uploading: vi_20211212.json
    #>   Uploading: vi_20211228.json
    #>   Uploading: vi_20220113.json
    #>   Uploading: vi_20220129.json
    #>   Uploading: vi_20220214.json
    #>   Uploading: vi_20220302.json
    #>   Uploading: vi_20220318.json
    #>   Uploading: vi_20220403.json
    #>   Uploading: vi_20220419.json
    #>   Uploading: vi_20220505.json
    #>   Uploading: vi_20220521.json
    #>   Uploading: vi_20220606.json
    #>   Uploading: vi_20220622.json
    #>   Uploading: vi_20220708.json
    #>   Uploading: vi_20220724.json
    #>   Uploading: vi_20220809.json
    #>   Uploading: vi_20220825.json
    #>   Uploading: vi_20220910.json
    #>   Uploading: vi_20220926.json
    #>   Uploading: vi_20221012.json
    #>   Uploading: vi_20221028.json
    #>   Uploading: vi_20221113.json
    #>   Uploading: vi_20221129.json
    #>   Uploading: vi_20221215.json
    #>   Uploading: vi_20221231.json
    #>   Uploading: vi_20230116.json
    #>   Uploading: vi_20230201.json
    #>   Uploading: vi_20230217.json
    #>   Uploading: vi_20230305.json
    #>   Uploading: vi_20230321.json
    #>   Uploading: vi_20230406.json
    #>   Uploading: vi_20230422.json
    #>   Uploading: vi_20230508.json
    #>   Uploading: vi_20230524.json
    #>   Uploading: vi_20230609.json
    #>   Uploading: vi_20230625.json
    #>   Uploading: vi_20230711.json
    #>   Uploading: vi_20230727.json
    #>   Uploading: vi_20230812.json
    #>   Uploading: vi_20230828.json
    #>   Uploading: vi_20230913.json
    #>   Uploading: vi_20230929.json
    #>   Uploading: vi_20231015.json
    #>   Uploading: vi_20231031.json
    #>   Uploading: vi_20231116.json
    #>   Uploading: vi_20231202.json
    #>   Uploading: vi_20231218.json
    #>   Uploading: vi_20240103.json
    #>   Uploading: vi_20240119.json
    #>   Uploading: vi_20240204.json
    #>   Uploading: vi_20240220.json
    #>   Uploading: vi_20240307.json
    #>   Uploading: vi_20240323.json
    #>   Uploading: vi_20240408.json
    #>   Uploading: vi_20240424.json
    #>   Uploading: vi_20240510.json
    #>   Uploading: vi_20240526.json
    #>   Uploading: vi_20240611.json
    #>   Uploading: vi_20240627.json
    #>   Uploading: vi_20240713.json
    #>   Uploading: vi_20240729.json
    #>   Uploading: vi_20240814.json
    #>   Uploading: vi_20240830.json
    #>   Uploading: vi_20240915.json
    #>   Uploading: vi_20241001.json
    #>   Uploading: vi_20241017.json
    #>   Uploading: vi_20241102.json
    #>   Uploading: vi_20241118.json
    #>   Uploading: vi_20241204.json
    #>   Uploading: vi_20241220.json
    #>   Uploading: vi_20250105.json
    #>   Uploading: vi_20250121.json
    #>   Uploading: vi_20250206.json
    #>   Uploading: vi_20250222.json
    #>   Uploading: vi_20250310.json
    #>   Uploading: vi_20250326.json
    #>   Uploading: vi_20250411.json
    #>   Uploading: vi_20250427.json
    #>   Uploading: vi_20250513.json
    #>   Uploading: vi_20250529.json
    #>   Uploading: vi_20250614.json
    #>   Uploading: vi_20250630.json
    #>   Uploading: vi_20250716.json
    #>   Uploading: vi_20250801.json
    #>   Uploading: vi_20250817.json
    #>   Uploading: vi_20250902.json
    #>   Uploading: vi_20250918.json
    #>   Uploading: vi_20251004.json
    #>   Uploading: vi_20251020.json
    #>   Uploading: vi_20251105.json
    #>   Uploading: vi_20251121.json
    #>   Uploading: vi_20251207.json
    #>   Uploading: vi_20251223.json
    #>   Uploading: vi_20260108.json
    #>   Uploading: vi_20260124.json
    #>   Uploading: vi_20260209.json
    #>   Uploading: vi_20260225.json
    #>   Uploading: vi_20260313.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20260329.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20260414.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20260430.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20260516.json
    #>   Uploading: vi_20260601.json
    #>   Uploading: vi_20260617.json
    #>   Uploading: vi_20260703.json
    #>   Uploading: vi_20260719.json
    #>   Uploading: vi_20260804.json
    #>   Uploading: vi_20260820.json
    #>   Uploading: vi_collection.json
    #>     ✓ Uploaded
    #> Retrying 363 failed upload(s) after 30s backoff...
    #>   Uploading: vi_20081021.json
    #>   Uploading: vi_20081106.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20081122.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20081208.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20081224.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090109.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090125.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090210.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090226.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090314.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090330.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090415.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090501.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090517.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090602.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090618.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090704.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090720.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090805.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090821.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090906.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20090922.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20091008.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20091024.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20091109.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20091125.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20091211.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20091227.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100112.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100128.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100213.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100301.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100317.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100402.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100418.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100504.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100520.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100605.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100621.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100707.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100723.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100808.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100824.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100909.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20100925.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20101011.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20101027.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20101112.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20101128.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20101214.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20101230.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110115.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110131.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110216.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110304.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110320.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110405.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110421.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110507.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110523.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110608.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110624.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110710.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110726.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110811.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110827.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110912.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20110928.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20111014.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20111030.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20111115.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20111201.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20111217.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120102.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120118.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120203.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120219.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120306.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120322.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120407.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120423.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120509.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120525.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120610.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120626.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120712.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120728.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120813.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120829.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120914.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20120930.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20121016.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20121101.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20121117.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20121203.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20121219.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130104.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130120.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130205.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130221.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130309.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130325.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130410.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130426.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130512.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130528.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130613.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130629.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130715.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130731.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130816.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130901.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20130917.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20131003.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20131019.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20131104.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20131120.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20131206.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20131222.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140107.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140123.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140208.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140224.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140312.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140328.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140413.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140429.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140515.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140531.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140616.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140702.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140718.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140803.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140819.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140904.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20140920.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20141006.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20141022.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20141107.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20141123.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20141209.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20141225.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150110.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150126.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150211.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150227.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150315.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150331.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150416.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150502.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150518.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150603.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150619.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150705.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150721.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150806.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150822.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150907.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20150923.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20151009.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20151025.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20151110.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20151126.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20151212.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20151228.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160113.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160129.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160214.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160301.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160317.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160402.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160418.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160504.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160520.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160605.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160621.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160707.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160723.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160808.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160824.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160909.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20160925.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20161011.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20161027.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20161112.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20161128.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20161214.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20161230.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170115.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170131.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170216.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170304.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170320.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170405.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170421.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170507.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170523.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170608.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170624.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170710.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170726.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170811.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170827.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170912.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20170928.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20171014.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20171030.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20171115.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20171201.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20171217.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180102.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180118.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180203.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180219.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180307.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180323.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180408.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180424.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180510.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180526.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180611.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180627.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180713.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180729.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180814.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180830.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20180915.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20181001.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20181017.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20181102.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20181118.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20181204.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20181220.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190105.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190121.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20190206.json
    #>     ✓ Uploaded
    #>   Uploading: vi_20201209.json
    #>   Uploading: vi_20201225.json
    #>   Uploading: vi_20210110.json
    #>   Uploading: vi_20210126.json
    #>   Uploading: vi_20210211.json
    #>   Uploading: vi_20210227.json
    #>   Uploading: vi_20210315.json
    #>   Uploading: vi_20210331.json
    #>   Uploading: vi_20210416.json
    #>   Uploading: vi_20210502.json
    #>   Uploading: vi_20210518.json
    #>   Uploading: vi_20210603.json
    #>   Uploading: vi_20210619.json
    #>   Uploading: vi_20210705.json
    #>   Uploading: vi_20210721.json
    #>   Uploading: vi_20210806.json
    #>   Uploading: vi_20210822.json
    #>   Uploading: vi_20210907.json
    #>   Uploading: vi_20210923.json
    #>   Uploading: vi_20211009.json
    #>   Uploading: vi_20211025.json
    #>   Uploading: vi_20211110.json
    #>   Uploading: vi_20211126.json
    #>   Uploading: vi_20211212.json
    #>   Uploading: vi_20211228.json
    #>   Uploading: vi_20220113.json
    #>   Uploading: vi_20220129.json
    #>   Uploading: vi_20220214.json
    #>   Uploading: vi_20220302.json
    #>   Uploading: vi_20220318.json
    #>   Uploading: vi_20220403.json
    #>   Uploading: vi_20220419.json
    #>   Uploading: vi_20220505.json
    #>   Uploading: vi_20220521.json
    #>   Uploading: vi_20220606.json
    #>   Uploading: vi_20220622.json
    #>   Uploading: vi_20220708.json
    #>   Uploading: vi_20220724.json
    #>   Uploading: vi_20220809.json
    #>   Uploading: vi_20220825.json
    #>   Uploading: vi_20220910.json
    #>   Uploading: vi_20220926.json
    #>   Uploading: vi_20221012.json
    #>   Uploading: vi_20221028.json
    #>   Uploading: vi_20221113.json
    #>   Uploading: vi_20221129.json
    #>   Uploading: vi_20221215.json
    #>   Uploading: vi_20221231.json
    #>   Uploading: vi_20230116.json
    #>   Uploading: vi_20230201.json
    #>   Uploading: vi_20230217.json
    #>   Uploading: vi_20230305.json
    #>   Uploading: vi_20230321.json
    #>   Uploading: vi_20230406.json
    #>   Uploading: vi_20230422.json
    #>   Uploading: vi_20230508.json
    #>   Uploading: vi_20230524.json
    #>   Uploading: vi_20230609.json
    #>   Uploading: vi_20230625.json
    #>   Uploading: vi_20230711.json
    #>   Uploading: vi_20230727.json
    #>   Uploading: vi_20230812.json
    #>   Uploading: vi_20230828.json
    #>   Uploading: vi_20230913.json
    #>   Uploading: vi_20230929.json
    #>   Uploading: vi_20231015.json
    #>   Uploading: vi_20231031.json
    #>   Uploading: vi_20231116.json
    #>   Uploading: vi_20231202.json
    #>   Uploading: vi_20231218.json
    #>   Uploading: vi_20240103.json
    #>   Uploading: vi_20240119.json
    #>   Uploading: vi_20240204.json
    #>   Uploading: vi_20240220.json
    #>   Uploading: vi_20240307.json
    #>   Uploading: vi_20240323.json
    #>   Uploading: vi_20240408.json
    #>   Uploading: vi_20240424.json
    #>   Uploading: vi_20240510.json
    #>   Uploading: vi_20240526.json
    #>   Uploading: vi_20240611.json
    #>   Uploading: vi_20240627.json
    #>   Uploading: vi_20240713.json
    #>   Uploading: vi_20240729.json
    #>   Uploading: vi_20240814.json
    #>   Uploading: vi_20240830.json
    #>   Uploading: vi_20240915.json
    #>   Uploading: vi_20241001.json
    #>   Uploading: vi_20241017.json
    #>   Uploading: vi_20241102.json
    #>   Uploading: vi_20241118.json
    #>   Uploading: vi_20241204.json
    #>   Uploading: vi_20241220.json
    #>   Uploading: vi_20250105.json
    #>   Uploading: vi_20250121.json
    #>   Uploading: vi_20250206.json
    #>   Uploading: vi_20250222.json
    #>   Uploading: vi_20250310.json
    #>   Uploading: vi_20250326.json
    #>   Uploading: vi_20250411.json
    #>   Uploading: vi_20250427.json
    #>   Uploading: vi_20250513.json
    #>   Uploading: vi_20250529.json
    #>   Uploading: vi_20250614.json
    #>   Uploading: vi_20250630.json
    #>   Uploading: vi_20250716.json
    #>   Uploading: vi_20250801.json
    #>   Uploading: vi_20250817.json
    #>   Uploading: vi_20250902.json
    #>   Uploading: vi_20250918.json
    #>   Uploading: vi_20251004.json
    #>   Uploading: vi_20251020.json
    #>   Uploading: vi_20251105.json
    #>   Uploading: vi_20251121.json
    #>   Uploading: vi_20251207.json
    #>   Uploading: vi_20251223.json
    #>   Uploading: vi_20260108.json
    #>   Uploading: vi_20260124.json
    #>   Uploading: vi_20260209.json
    #>   Uploading: vi_20260225.json
    #>   Uploading: vi_20260516.json
    #>   Uploading: vi_20260601.json
    #>   Uploading: vi_20260617.json
    #>   Uploading: vi_20260703.json
    #>   Uploading: vi_20260719.json
    #>   Uploading: vi_20260804.json
    #>   Uploading: vi_20260820.json
    #> ✓ Uploaded 993 small file(s) (no polling needed)
    #> Uploading checksum file: stac_SHA256SUMS.txt
    #>   (checksum upload skipped: Unprocessable Entity (WebDAV; RFC 4918) (HTTP 422).)
    #> stac release now has 999 assets (expected >= 1121)
    #> Loaded 40 packages from DESCRIPTION
    #> + burn_viirs_task_ids declared [176 branches]
    #> + vi_modis_task_ids declared [107 branches]
    #> + burn_modis_task_ids declared [320 branches]
    #> + vi_viirs_task_ids declared [4 branches]
    #> + burn_viirs_geotiff declared [176 branches]
    #> + vi_modis_geotiff declared [107 branches]
    #> + burn_modis_geotiff declared [320 branches]
    #> + vi_viirs_geotiff declared [4 branches]
    #> + burn_viirs_grid declared [176 branches]
    #> + vi_modis_grid declared [107 branches]
    #> + burn_modis_grid declared [320 branches]
    #> + vi_viirs_grid declared [4 branches]
    #> + burn_viirs_parquet declared [176 branches]
    #> + vi_modis_parquet declared [107 branches]
    #> + burn_modis_parquet declared [320 branches]
    #> + vi_viirs_parquet declared [4 branches]
    #> There were 50 or more warnings (use warnings() to see the first 50)

![Pipeline
Network](https://github.com/eco-emma/emma_envdata/releases/download/readme-assets/network.png)

## Pipeline Health

| Status     | Count | Percent (%) |
|:-----------|------:|------------:|
| never run  |   114 |         1.2 |
| up-to-date |  9522 |        98.8 |

Pipeline Target Status Summary {.table .table-striped .table-hover
quarto-postprocess="true"
style="margin-left: auto; margin-right: auto;"}

[![Build
Status](https://github.com/eco-emma/emma_envdata/workflows/targets/badge.svg)](https://github.com/eco-emma/emma_envdata/actions)
**Last pipeline run:** 2026-09-22 18:05:06.339883

## Data Inventory

| Dataset | Source | Type | Format | Release Tag | Time Steps | Date Updated |
|:---|:---|:---|:---|:---|---:|:---|
| MODIS VI (Terra + Aqua) | MOD13A1 + MYD13A1 | Dynamic | COG GeoTIFF + Parquet | vi_modis_terra_raster + vi_modis_aqua_raster | 606 | 2026-08-20T23:59:59Z |
| VIIRS VI (S-NPP + NOAA-20) | VNP13A1 + VJ113A1 | Dynamic | COG GeoTIFF + Parquet | vi_viirs_raster | 606 | 2026-08-20T23:59:59Z |
| MODIS Burned Area | MCD64A1 | Dynamic | COG GeoTIFF + Parquet | burn_modis_raster | 320 | NULL |
| VIIRS Burned Area | VNP64A1 | Dynamic | COG GeoTIFF + Parquet | burn_viirs_raster | 176 | NULL |
| Fire History (derived) | Multi-sensor merge | Dynamic | COG GeoTIFF | firehistory_dynamic | 1 | 2026-09-22 |
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
