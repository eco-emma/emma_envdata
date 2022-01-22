
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
process_dynamic_data_to_parquet <- function(input_dir = "data/raw_data/ndvi_modis/",
                                            output_dir = "data/processed_data/dynamic_parquet/ndvi/",
                                            variable_name = "ndvi",
                                            ...){


  # make a directory if one doesn't exist yet

      if(!dir.exists(output_dir)){

        dir.create(output_dir)

      }

  # get files

    all_files <- list.files(path = input_dir,pattern = ".tif$",full.names = TRUE)

    all_files_int <-
    all_files %>%
      gsub(pattern = input_dir, replacement = "") %>%
      gsub(pattern = "/", replacement = "") %>%
      gsub(pattern = ".tif", replacement = "") %>%
      lubridate::as_date()|>
      as.numeric()


  # figure out which files have been processed

    output_files <-
      list.files(path = output_dir, pattern = ".gz.parquet", full.names = TRUE) %>%
      gsub(pattern = output_dir, replacement = "") %>%
      gsub(pattern = "/", replacement = "") %>%
      gsub(pattern = ".gz.parquet", replacement = "")

  #Don't worry about files that have been processed already

    all_files <- all_files[which(!all_files_int %in% output_files)]

    rm(output_files, all_files_int)

  #end if things are already done
    if(length(all_files) == 0){

      message(paste("Finished converting ",
                    variable_name,
                    " files to parquet", sep = ""))

      return(output_dir)

    }


  # process the files that haven't been done yet


    for(i in 1:length(all_files)){

      # Get the date in integer format (will append to the data)
        all_files[i] |>
          gsub(pattern = input_dir, replacement = "")|>
          gsub(pattern = "/", replacement = "")|>
          gsub(pattern = ".tif", replacement = "")|>
          lubridate::as_date()|>
          as.numeric()-> integer_date_i


    # Process ith file

      all_files[i] |>
        stars::read_stars() |>
        as.data.frame() %>%
        mutate(cellID = row_number(),
               date = integer_date_i,
               variable = variable_name) %>%
        rename( value := 3) %>%
        dplyr::select(cellID, date, variable, value ) %>%
        drop_na() %>%
        write_parquet(sink = paste(output_dir, integer_date_i, ".gz.parquet", sep = ""),
                      compression = "gzip")

  } #end i loop

  #End fx
    message(paste("Finished converting ",variable_name, " files to parquet",sep = ""))
    return(output_dir)

}#end fx
