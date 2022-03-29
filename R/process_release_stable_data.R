library(arrow)

#' @param output_dir directory (no file name) in which to save the csv that is returned
#' @param precip_dir directory containing the precipitation layers
#' @param landcover_dir directory containing the landcover layers
#' @param elevation_dir directory containing the elevation layer
#' @param cloud_dir directory containing the could layers
#' @param climate_dir directory containing the climate layers
#' @param alos_dir directory containing the alos layers
#' @param remnant_distace_dir directory containing remnant distance layer
#' @param ... Does nothing, used to ensure upstream changes impact things
process_release_stable_data <- function(temp_directory = "data/temp/processed_data/static/",
                                        input_tag = "processed_static",
                                        output_tag = "current",
                                        ...) {


  #  #Ensure directory is empty if it exists

    if(dir.exists(temp_directory)){
      unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
    }

  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }


  # load files

    raster_list <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                           tag = input_tag) %>%
      filter(file_name != "template.tif")


    robust_pb_download(file = raster_list$file_name,
                       dest = temp_directory,
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = input_tag,
                       max_attempts = 10,
                       sleep_time = 10)

  # process data

    file.path(temp_directory,raster_list$file_name) |>
    stars::read_stars() |>
    as.data.frame() |>
    mutate(cellID = row_number()) %>%
    filter(SA_NLC_2020_GEO.tif != 0) %>%
    write_parquet(sink = file.path(temp_directory,"stable_data.gz.parquet"),
                  compression = "gzip")


  #The following line of code can be used to break things down by a grouping variable
  # write_dataset(path = output_dir,
  #               format = "parquet",
  #               basename_template = "stable_data{i}.parquet.gz",
  #               compression = "gzip",
  #               existing_data_behavior = "delete_matching")


  # Release


    pb_upload(file = file.path(output_dir,"stable_data.gz.parquet"),
              repo = "AdamWilsonLab/emma_envdata",
              tag = output_tag)


  #cleanup
  gc()




  # Return filename

  message("Finished processing stable model data")
  return(paste(output_dir,"stable_data.gz.parquet",sep = ""))

}
