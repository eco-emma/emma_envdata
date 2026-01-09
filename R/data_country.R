# National Boundary

#' @author Adam M. Wilson
#' @description Download national boundary file from the UN
#' @source  https://data.humdata.org/dataset/cod-ab-zaf

get_country <- function(){

  #Adjust timeout to allow for slow internet
  if(getOption('timeout') < 1000){
    options(timeout = 1000)
  }

  url="https://data.humdata.org/dataset/061d4492-56e8-458c-a3fb-e7950991adf0/resource/37175ff4-41a3-4753-a2c3-ced24142a96c/download/zaf_admin_boundaries.geojson.zip"
  tmpfile1=tempfile()
  tmpdir1=tempdir()
  download.file(url,destfile = tmpfile1)
  unzip(tmpfile1,exdir=tmpdir1)

  # Read the converted GeoJSON, union, and convert to SpatVector
  country <- st_read(file.path(tmpdir1, "zaf_admin0.geojson"), quiet = TRUE) |>
    st_union() |>
    st_as_sf() |>
    vect()

  return(country)
}
# end function



