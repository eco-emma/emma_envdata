tif_debug <- function(directory = "scratch_code"){


  if(file.exists(paste(directory,"/wc2.1_10m_tmin_01.tif",sep = ""))){

    #File found

    raster::raster(paste(directory,"/wc2.1_10m_tmin_01.tif",sep = ""))


  }else{

    message("File not found, downloading")

    download.file(url = "https://biogeo.ucdavis.edu/data/worldclim/v2.1/base/wc2.1_10m_tmin.zip",
                  destfile = paste(directory,"/test.zip",sep = ""))

    message("file downloaded")



    unzip(zipfile = paste(directory,"/test.zip",sep = ""),
          exdir = "scratch_code",overwrite = TRUE)

    raster::raster(paste(directory,"/wc2.1_10m_tmin_01.tif",sep = ""))

  }




}
