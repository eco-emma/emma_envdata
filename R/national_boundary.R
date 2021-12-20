#ALOS

#' @author Adam M. Wilson

#' Download national boundary file from the UN

#' @param url is the text string used by gee to refer to an image, e.g. "CSP/ERGo/1_0/Global/ALOS_mTPI"
#' @param sabb Bounding Box to constrain area downloaded
#' @note This code is only deisnged to work with a handful of images by CSP/ERGo
#' @source  https://data.humdata.org/dataset/south-africa-admin-level-1-boundaries

national_boundary <- function(){

  url="https://data.humdata.org/dataset/061d4492-56e8-458c-a3fb-e7950991adf0/resource/f5b08257-8d03-48dc-92c8-aaa4fb7285f0/download/zaf_adm_sadb_ocha_20201109_shp.zip"

  tmpfile=tempfile()
  download.file(url,destfile = tmpfile)
  unzip(tmpfile,exdir="data")

  za=st_read("data/zaf_adm_sadb_ocha_20201109_SHP/zaf_admbnda_adm0_sadb_ocha_20201109.shp")

  return(za)
}
# end function



