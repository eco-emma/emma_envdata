# National Boundary

#' @author Adam M. Wilson
#' @description Download national boundary file from the UN
#' @source  https://data.humdata.org/dataset/cod-ab-zaf

national_boundary <- function(){

  #Adjust timeout to allow for slow internet
  if(getOption('timeout') < 1000){
    options(timeout = 1000)
  }


    url="https://data.humdata.org/dataset/061d4492-56e8-458c-a3fb-e7950991adf0/resource/69c947ad-dc17-416c-bafa-b66fb523c322/download/zaf_admin_boundaries.gdb.zip"
    tmpfile1=tempfile()
    tmpdir1=tempdir()
    download.file(url,destfile = tmpfile1)
    unzip(tmpfile1,exdir=tmpdir1)

    country=vect(file.path(tmpdir1,"zaf_admin_boundaries.gdb"),"zaf_admin0")|>
    st_union() |>
    vect()

    return(country)
}
# end function



