
library(arrow)
library(tidyverse)


#############################################################
#' @author Brian Maitner
#' @description this function takes in tif file from the input, converts them to tidy format, and saves as .gz.parquet
#' @param input_dir Directory containing input files.
#' @param output_dir Directory to stick output files in
#' @param variable_name This is included in the tidy file output
#' @param ... Does nothing.  Used for targets.
#' @note Output dataframes have three columns: CellID, date, variable, value.  ALso note that cells with NA values are omitted.
process_release_dynamic_data_to_parquet <- function(temp_directory = "data/temp/raw_data/ndvi_modis/",
                                                    input_tag = "raw_ndvi_modis",
                                                    output_tag = "current",
                                                    variable_name = "ndvi",
                                                    sleep_time = 30,
                                                    ...){


  #  #Ensure directory is empty if it exists

    if(dir.exists(temp_directory)){
      unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
    }

  # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }

  #get release assets
  release_assetts <- pb_list(repo = "AdamWilsonLab/emma_envdata")

  # load files

  raster_list <-
    release_assetts %>%
    filter(tag == input_tag) %>%
    filter(file_name != "log.csv") %>%
    mutate(parquet_name = lubridate::as_date(x = gsub(pattern = ".tif",replacement = "",x = file_name,)))%>%
    mutate(parquet_name = as.numeric(parquet_name))%>%
    mutate(parquet_name = paste("-dynamic_parquet-",variable_name,"-",parquet_name,".gz.parquet",sep = ""))

  #-dynamic_parquet-ndvi-11005.gz.parquet

  # get files


  # figure out which files have been processed

  processed_list <-
    release_assetts %>%
    filter(tag == output_tag)%>%
    filter(grepl(pattern = paste("-",variable_name,"-",sep = ""),
                 x = file_name))

  #Don't worry about files that have been processed already

   raster_list <- raster_list[which(!raster_list$parquet_name %in% processed_list$file_name),]

  #end if things are already done

    if(nrow(raster_list) == 0){

      message(paste("Finished converting ",
                    variable_name,
                    " files to parquet", sep = ""))

      return(
        release_assetts %>%
          filter(tag == input_tag) %>%
          dplyr::select(file_name) %>%
          filter(file_name != "") %>%
          filter(grepl(pattern = ".tif$", x = file_name)) %>%
          mutate(date_format = gsub(pattern = ".tif",
                                    replacement = "",
                                    x = file_name))%>%
          mutate(date_format = gsub(pattern = "_", replacement = "-", x = date_format)) %>%
          dplyr::pull(date_format) %>%
          max()
      )



    }


  # process the files that haven't been done yet


  for(i in 1:nrow(raster_list)){

    #Download the ith raster
      robust_pb_download(file = raster_list$file_name[i],
                         dest = temp_directory,
                         repo = "AdamWilsonLab/emma_envdata",
                         tag = raster_list$tag[i],
                         overwrite = TRUE,
                         max_attempts = 10,
                         sleep_time = sleep_time)

    #Pause to keep Github happy

      Sys.sleep(sleep_time)

    # Get the date in integer format (will append to the data)

      raster_list$file_name[i] |>
        gsub(pattern = "/", replacement = "")|>
        gsub(pattern = ".tif", replacement = "")|>
        lubridate::as_date()|>
        as.numeric() -> integer_date_i

    # Process ith file

      file.path(temp_directory,raster_list$file_name[i]) |>
        stars::read_stars() |>
        as.data.frame() %>%
        mutate(cellID = row_number(),
               date = integer_date_i,
               variable = variable_name) %>%
        rename( value := 3) %>%
        dplyr::select(cellID, date, variable, value ) %>%
        drop_na() %>%
        write_parquet(sink = file.path(temp_directory,
                                       paste("-dynamic_parquet-",
                                             variable_name,"-",
                                             integer_date_i,
                                             ".gz.parquet", sep = "")),
                      compression = "gzip")

    # Upload ith file

    pb_upload(file = file.path(temp_directory,
                               paste("-dynamic_parquet-",
                                     variable_name,"-",
                                     integer_date_i,
                                     ".gz.parquet", sep = "")),
              repo = "AdamWilsonLab/emma_envdata",
              tag = output_tag,
              overwrite = TRUE
              )

    #clean up

      unlink(file.path(temp_directory,raster_list$file_name[i]))

      unlink( file.path(temp_directory,
                        paste("-dynamic_parquet-",
                              variable_name,"-",
                              integer_date_i,
                              ".gz.parquet", sep = "")) )

      rm(integer_date_i)

    #Pause to keep Github happy

      Sys.sleep(sleep_time)

  } #end i loop

  #Clean up

   unlink(file.path(temp_directory),
          recursive = TRUE,
          force = TRUE)

  #End fx

    message(paste("Finished converting ",variable_name, " files to parquet",sep = ""))
    return(
      raster_list %>%
        filter(tag == input_tag) %>%
        dplyr::select(file_name) %>%
        filter(file_name != "") %>%
        filter(grepl(pattern = ".tif$", x = file_name)) %>%
        mutate(date_format = gsub(pattern = ".tif",
                                  replacement = "",
                                  x = file_name))%>%
        mutate(date_format = gsub(pattern = "_", replacement = "-", x = date_format)) %>%
        dplyr::pull(date_format) %>%
        max()
    )


}#end fx
