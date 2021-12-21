# National Boundary

#' @author Adam M. Wilson
#' @description Download national boundary file from the UN
#' @source  https://data.humdata.org/dataset/south-africa-admin-level-1-boundaries

national_boundary <- function(file="data/south_africa.gpkg"){

    url="https://data.humdata.org/dataset/061d4492-56e8-458c-a3fb-e7950991adf0/resource/f5b08257-8d03-48dc-92c8-aaa4fb7285f0/download/zaf_adm_sadb_ocha_20201109_shp.zip"
    tmpfile1=tempfile()
    tmpdir1=tempdir()
    download.file(url,destfile = tmpfile1)
    unzip(tmpfile1,exdir=tmpdir1)

    country=st_read(file.path(tmpdir1,"zaf_adm_sadb_ocha_20201109_SHP/zaf_admbnda_adm0_sadb_ocha_20201109.shp"))
    st_write(country,dsn=file,append=F)

      return(file)
}
# end function



