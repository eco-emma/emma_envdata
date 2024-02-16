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
                                        sleep_time = 30,
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

    message("Getting list of rasters to include ", Sys.time())

    raster_list <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                           tag = input_tag) %>%
      filter(file_name != "template.tif")

    message("Starting Raster Download ", Sys.time())

    robust_pb_download(file = raster_list$file_name,
                       dest = temp_directory,
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = input_tag,
                       max_attempts = 10,
                       sleep_time = 10)

    message("Finished Raster Download ", Sys.time())

  # Check that all raster projections, resolution, ext are identical (these will throw errors if they aren't identical)

    message("Checking raster metadata ", Sys.time())

      raster_list |>
        dplyr::filter(grepl(pattern = ".tif$",x = file_name)) -> raster_list

      terra::ext(rast(file.path(temp_directory,raster_list$file_name)))
      terra::res(rast(file.path(temp_directory,raster_list$file_name)))
      terra::crs(rast(file.path(temp_directory,raster_list$file_name)),proj=TRUE)

  # process data

    for(i in 1:length(raster_list$file_name)){

      message("Creating gzip file ",raster_list$file_name[i]," ", Sys.time())

      file.path(temp_directory,raster_list$file_name[i]) |>
        stars::read_stars() |>
        as.data.frame() |>
        mutate(cellID = row_number()) %>%
        #filter(SA_NLC_2020_GEO.tif != 0) %>%
        write_parquet(sink = file.path(temp_directory,paste(raster_list$file_name[i],".gz.parquet",sep = "")),
                      compression = "gzip") #note: chunk size here details the number of chunks written at once


      message("Uploading gzip files ",raster_list$file_name[i]," ", Sys.time())

      pb_upload(file = file.path(temp_directory,paste(raster_list$file_name[i],".gz.parquet",sep = "")),
                repo = "AdamWilsonLab/emma_envdata",
                tag = output_tag,
                show_progress = TRUE)

      Sys.sleep(sleep_time)


    }



    #Note: switched from uploading a single file to multiples as github was having problems with the big file

    # message("Creating gzip file ", Sys.time())

    # file.path(temp_directory,raster_list$file_name) |>
    # stars::read_stars() |>
    # as.data.frame() |>
    # mutate(cellID = row_number()) %>%
    # filter(SA_NLC_2020_GEO.tif != 0) %>%
    # write_parquet(sink = file.path(temp_directory,"stable_data.gz.parquet"),
    #               compression = "gzip",
    #               chunk_size = 1000) #note: chunk size here details the number of chunks written at once


  #The following line of code can be used to break things down by a grouping variable
  # write_dataset(path = output_dir,
  #               format = "parquet",
  #               basename_template = "stable_data{i}.parquet.gz",
  #               compression = "gzip",
  #               existing_data_behavior = "delete_matching")


  # Release

    # message("Starting upload of stable parquet ", Sys.time())
    #
    # pb_upload(file = file.path(temp_directory,"stable_data.gz.parquet"),
    #           repo = "AdamWilsonLab/emma_envdata",
    #           tag = output_tag,
    #           show_progress = TRUE)
    #
    # message("Finished upload of stable parquet ", Sys.time())


  #cleanup

    unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)

    gc()



  # Return filename

  message("Finished processing stable model data")
  return(invisible(NULL))

}
