#' @author Brian Maitner
#' @description This code converts the modis fire dates from a numeric day of the year (e.g. jan 2 is 2), to the number of days in the unix era (days since jan 1 1970)
#' @note The goal is to replace this with earth engine code, but this is needed for double checking at present
#' @param input_tag Github release tag associated with input files
#' @param output_tag Github release tag to use with output files
#' @param temp_directory Where to store the files while working?  The directory is deleted at the end.
#' @param sleep_time Amount of time to wait between attempts.  Needed to keep github happy

process_release_fire_doy_to_unix_date <- function( input_tag = "raw_fire_modis",
                                                   output_tag = "processed_fire_dates",
                                                   temp_directory = "data/temp/processed_data/fire_dates/",
                                                   template_release = template_release,
                                                   sleep_time = 1,
                                                   ...) {
  # Ensure directory is empty if it exists

    if(dir.exists(temp_directory)){
      unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
    }



  #make folder if needed

    if(!dir.exists(temp_directory)){dir.create(temp_directory, recursive = TRUE)}

  # check on releases

    release_assetts <- pb_list(repo = "AdamWilsonLab/emma_envdata")

  #Make sure there is an input release or make one

    if(!input_tag %in% release_assetts$tag){

      tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                       tag =  input_tag),
               error = function(e){message("Previous release found")})

      Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

    }

  #Make sure there is an output release or make one

    if(!output_tag %in% release_assetts$tag){

      #Make sure there is a release by attempting to create one.  If it already exists, this will fail
      tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                       tag =  output_tag),
               error = function(e){message("Previous release found")})

    }

  #get files

    input_files  <-
    release_assetts %>%
      filter(tag == input_tag) %>%
      filter(file_name != "") %>%
      filter(grepl(pattern = ".tif$",x = file_name))


    output_files  <-
      release_assetts %>%
      filter(tag == output_tag) %>%
      filter(file_name != "") %>%
      filter(grepl(pattern = ".tif$",x = file_name))

  #prune input files to only ones not in output

    input_files <- input_files[which(!input_files$file_name %in% output_files$file_name),]


    if(nrow(input_files) == 0) {
      message("Finished processing fire day-of-year to date")

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


  # IF extent checking is required, load the template used for comparison

    robust_pb_download(file = template_release$file,
                       dest = file.path(temp_directory),
                       repo = template_release$repo,
                       tag = template_release$tag,
                       overwrite = TRUE,
                       max_attempts = 10,
                       sleep_time = 10)

    template <- rast(file.path(temp_directory,template_release$file))

  #Do the actual processing of the fire day-of-year rasters into UNIX dates

    for(i in 1:nrow(input_files)){

      # download file i
        robust_pb_download(file = input_files$file_name[i],
                           dest = temp_directory,
                           repo = "AdamWilsonLab/emma_envdata",
                           tag = input_tag,
                           overwrite = TRUE,
                           max_attempts = 10)

      #Get raster

        raster_i <- rast(file.path(temp_directory, input_files$file_name[i]))

      #Get year and convert to numeric

        date_i <- input_files$file_name[i]

        date_i <- gsub(pattern = ".tif", replacement = "", x = date_i)

        year_i <- strsplit(x = date_i,split = "_")[[1]][1]

        year_i <- as.numeric(as_date(paste(year_i, "-01-01")))

      # Add numeric year to raster cells

        mask_i <- raster_i > 0

        raster_i <- terra::mask(x = raster_i,
                                 mask = mask_i,
                                 maskvalue = 0,
                                 updatevalue = NA)


    # Get some metadata for inspecting the dates for common sense

        ceiling_date_i <- ceiling_date(as_date(date_i),unit = "month")-1

        floor_date_i <- floor_date(as_date(date_i),unit = "month")

        raster_vals <- values(raster_i) |> unique() |> na.omit()

    # 2021-03-01 raster appears to be in UNIX date instead of DOY. Detect such issues and handle

      if( all(raster_vals >= as.numeric(floor_date_i)) &
          all(raster_vals <= as.numeric(ceiling_date_i))){


        terra::writeRaster(x = raster_i,
                            filename = file.path(temp_directory,input_files$file_name[i]),
                            overwrite = TRUE)

        pb_upload(file = file.path(temp_directory,input_files$file_name[i]),
                  repo = "AdamWilsonLab/emma_envdata",
                  tag = output_tag,
                  name = input_files$file_name[i],
                  overwrite = TRUE)

        file.remove(file.path(temp_directory, input_files$file_name[i]))

        Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy

        next


      }



      # Check that input raster dates make sense

        if(any(raster_vals > 366)){stop("Impossible date values found: > 366")}

        if(any(raster_vals < 1)){
          stop("Impossible date values found: Less than 0")}


        if(any(raster_vals > yday(ceiling_date_i))){
          stop("Impossible date values found: After the month")}

        if(any(raster_vals < yday(floor_date_i))){
          stop("Impossible date values found: Before the month")}

      #convert to linux date

        raster_i <- raster_i + year_i - 1

        raster_i[!mask_i] <- 0

      #save output

        terra::writeRaster(x = raster_i,
                           filename = file.path(temp_directory,input_files$file_name[i]),
                           filetype="GTiff",
                           overwrite = TRUE)

      # check raster extent

        rast_i <- rast(file.path(temp_directory,input_files$file_name[i]))

        if(ext(rast_i) != ext(template)){stop("Extent incorrect")}


        pb_upload(file = file.path(temp_directory,input_files$file_name[i]),
                  repo = "AdamWilsonLab/emma_envdata",
                  tag = output_tag,
                  name = input_files$file_name[i],
                  overwrite = TRUE)

        file.remove(file.path(temp_directory,input_files$file_name[i]))

        Sys.sleep(sleep_time) #We need to limit our rate in order to keep Github happy


    }#for loop

  # Delete temp files

    unlink(x = gsub(pattern = "/$",replacement = "",x = temp_directory), #sub used to delete any trailing slashes, which interfere with unlink
           recursive = TRUE)

  #End function

    message("Finished processing fire day-of-year to date")

      return(
        input_files %>%
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
