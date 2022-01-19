
#' @param output_dir directory (no file name) in which to save the csv that is returned
#' @param precip_dir directory containing the precipitation layers
#' @param landcover_dir directory containing the landcover layers
#' @param elevation_dir directory containing the elevation layer
#' @param cloud_dir directory containing the could layers
#' @param climate_dir directory containing the climate layers
#' @param alos_dir directory containing the alos layers
#' @param ... Does nothing, used to ensure upstream changes impact things
process_stable_data <- function(output_dir = "data/processed_data/model_data/",
                                precip_dir = "data/processed_data/precipitation_chelsa/",
                                landcover_dir = "data/processed_data/landcover_za/",
                                elevation_dir = "data/processed_data/elevation_nasadem/",
                                cloud_dir = "data/processed_data/clouds_wilson/",
                                climate_dir = "data/processed_data/climate_chelsa/",
                                alos_dir = "data/processed_data/alos/",
                                ...) {


  # make a directory if one doesn't exist yet

    if(!dir.exists(output_dir)){
      dir.create(output_dir)
    }



  c(precip_dir,
    landcover_dir,
    elevation_dir,
    cloud_dir,
    climate_dir,
    alos_dir) |>

      lapply(FUN = function(x){
        list.files(path = x,
                   pattern = ".tif$",
                   full.names = T,
                   recursive = T)}) |>
    unlist() |>
    stars::read_stars() |>
    as.data.frame() |>
    mutate(cellID = row_number()) %>%
    mutate(count_na = apply(., 1,FUN = function(x){sum(is.na(x))} )) %>%
    filter(count_na < 20) |>
    write.csv(file = paste(output_dir,"stable_data.csv",sep = ""))

    gc()

    # Return filename
      message("Finished processing stable model data")
      return(paste(output_dir,"stable_data.csv",sep = ""))


}
