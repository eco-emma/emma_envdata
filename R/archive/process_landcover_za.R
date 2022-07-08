#' @author Brian Maitner
#' @param input_dir directory where the input files live
#' @param output_dir directory for the output files
#' @param template path to raster file to use as a template for reprojection
#' @param ... Does nothing, but is used in making connections between files in the targets framework
#' @note This function uses method = bilinear at present
process_landcover_za <- function(input_dir = "data/raw_data/landcover_za/",
                                      output_dir = "data/processed_data/landcover_za/",
                                      template,
                                      ...){

  # make a directory if one doesn't exist yet

  if(!dir.exists(input_dir)){
    dir.create(input_dir, recursive = TRUE)
  }

  if(!dir.exists(output_dir)){
    dir.create(output_dir, recursive = TRUE)
  }

  # get template raster

    template <- terra::rast(template)

  # get input rasters

    files <- list.files(path = input_dir,pattern = ".tif$",full.names = T)


  #reformat and save each

  for(i in 1:length(files)){

    raster_i <- terra::rast(files[i])

    #get file name
    file_name <- gsub(pattern = input_dir,replacement = "",x = files[i])
    file_name <- gsub(pattern = "/",replacement = "",x = file_name,fixed = TRUE)


    #Use bilinear for everything

    method <- "near"

    terra::project(x = raster_i,
                   y = template,
                   method = method,
                   filename = paste(output_dir, file_name, sep = ""),
                   overwrite = TRUE)



  } #i loop


  #End functions

  message("Finished processing landcover layer")
  return(invisible(NULL))


} #end fx



#################################

