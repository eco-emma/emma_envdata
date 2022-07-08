
#'@description to check the projection of MODIS products downloaded from rgee
#'@author Brian Maitner
#'@param A directory containing MODIS files with incorrect projections

process_fix_modis_projection <-
function(directory, ...){

  #specify the correct projection
    nasa_proj <- "+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +R=6371007.181 +units=m +no_defs"

  #get a vector of rasters
    rasters <- list.files(path = directory,
                          pattern = ".tif$",
                          full.names = TRUE)

  #set up a  change log if needed
    if(exists(paste(directory,"log.csv",sep = ""))){

      suppressWarnings(expr =
                         cbind("file","original_proj","assigned_proj") %>%
                         write.table(x = .,
                                     file = paste(directory,"log.csv",sep = ""),
                                     append = TRUE,
                                     col.names = FALSE,
                                     row.names=FALSE,
                                     sep = ",")
                       )


    }


  #iterate and fix
    for(i in 1:length(rasters)){

      #load ith raster
        rast_i <- terra::rast(x = rasters[i])

      #get the projection

        original_proj <- crs(rast_i, proj = TRUE)

      #check whether the raster matches the correct projection
        if(!identical(nasa_proj, original_proj)){

          message("Detected error in MODIS projection, correcting and logging the change")

          crs(rast_i) <- nasa_proj

          #write a new raster with a different name
            terra::writeRaster(x = rast_i,
                               filename = gsub(pattern = ".tif$",
                                               replacement =".temp.tif",
                                               x =  rasters[i]),
                               filetype="GTiff",
                               overwrite = TRUE)

          #delete old raster
            file.remove(rasters[i])

          #update new name
            file.rename(from = gsub(pattern = ".tif$",
                                    replacement =".temp.tif",
                                    x =  rasters[i]),
                        to = rasters[i])

          #log the change


          data.frame(file = rasters[i],
                     original_proj = original_proj,
                     assigned_proj = nasa_proj) %>%

          write.table(x = .,
                      file = paste(directory,"log.csv",sep = ""),
                      append = TRUE,
                      col.names = FALSE,
                      row.names=FALSE,
                      sep = ",")



        }

    }



}




