#' @author Brian Maitner
#' @param input_dir directory where the input files live
#' @param output_dir directory for the output files
#' @param template raster to use for reprojection
#' @param ... Does nothing, but is used in making connections between files in the targets framework
#' @note This function uses bilinear for continuous variables and nearest neighbor for categorical
process_alos <- function(input_dir = "data/raw_data/alos/",
                         output_dir = "data/processed_data/alos/",
                         template,
                         ...){

# make a directory if one doesn't exist yet

  if(!dir.exists(input_dir)){
    dir.create(input_dir)
  }

  if(!dir.exists(output_dir)){
    dir.create(output_dir)
  }


# get input rasters

  alos_files <- list.files(path = input_dir,pattern = ".tif",full.names = T)


#reformat and save each

  for(i in 1:length(alos_files)){

    raster_i <- terra::rast(alos_files[i])

    #get file name
      file_name <- gsub(pattern = input_dir,replacement = "",x = alos_files[i])

    #Use bilinear for everything except landforms
      if(length(grep(pattern = "landforms", x = alos_files[i])) > 0){

        method <- "near"

      }else{

        method <- "bilinear"

      }

    terra::project(x = raster_i,
                   y = template,
                   method = method,
                   filename = paste(output_dir, file_name, sep = ""),
                   overwrite = TRUE)



  } #i loop


  #End functions

    message("Finished processing ALOS layers")
    return(invisible(NULL))



} #end fx



#################################


# CSP/ERGo/1_0/Global/ALOS_mTPI
  #continuous measure of hills vs valleys -> bilinear
  #270


# "CSP/ERGo/1_0/Global/ALOS_CHILI"
  #continuous -> bilinear
  #90

# 'CSP/ERGo/1_0/Global/ALOS_landforms'
  # categorical land classes -> near
  #90 meter

# 'CSP/ERGo/1_0/Global/ALOS_topoDiversity'
  #continuous -> bilinear
  #270 m


