temp_directory = "data/temp/raw_data/ndvi_modis_extent/"
tag = "raw_ndvi_modis"
max_layers = NULL
sleep_time = 1
verbose=TRUE


# code to fix raster extent issues

# MODIS 6.1 fire rasters from 2000 to 2019 have one set of extents, 2020 another, and 2021 - present another.
#' @description to check the Extent of MODIS products downloaded from rgee
#' @author Brian Maitner
#' @param temp_directory The directory the layers should be temporarily saved in
#' @param tag tag associated with the Github release
#' @param max_layers the maximum number of layers to correct at once.  Default (NULL) is to use all.
#' @param sleep_time amount of time to pause after using pb_upload/download.  Used to keep Git happy
process_fix_modis_NDVI_release_extent <- function(temp_directory,
                                             tag,
                                             max_layers = NULL,
                                             sleep_time = 0.1,
                                             verbose=FALSE,
                                             ...){

  # get a list of released files

  if(verbose){message("Downloading list of releases")}

    released_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                               tag = tag)

  #  #Ensure directory is empty if it exists

      if(dir.exists(temp_directory)){

        if(verbose){message("Emptying directory")}

        unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
      }


  # make a directory if one doesn't exist yet

  if(!dir.exists(temp_directory)){

    if(verbose){message("Creating directory")}

    dir.create(temp_directory, recursive = TRUE)

  }

  #set up a  change log if needed

  if("extent_log.csv" %in% released_files$file_name){

    if(verbose){message("Downloading log")}


    robust_pb_download(file =  "extent_log.csv",
                       dest = temp_directory,
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = tag,
                       overwrite = TRUE,
                       max_attempts = 10,
                       sleep_time = sleep_time)


  }else{

    if(verbose){message("Creating log")}

    suppressWarnings(expr =
                       cbind("file","original_extent","final_extent") %>%
                       write.table(x = .,
                                   file = file.path(temp_directory,"extent_log.csv"),
                                   append = FALSE,
                                   col.names = FALSE,
                                   row.names=FALSE,
                                   sep = ",")
    )


  }


  # Get a list of raster that haven't been fixed by comparison with the log

  if(verbose){message("Identifying rasters in need of processing")}

  rasters <- released_files$file_name[grep(x = released_files$file_name, pattern = ".tif")]

  log <- read.csv(file.path(temp_directory, "extent_log.csv"))

  rasters <- rasters[which(!rasters %in% log$file)]

  if(!is.null(max_layers)){

    if(max_layers < length(rasters)){

      rasters <- rasters[1:max_layers]

    }



  }


  # check whether there is anything left to fix

  if(length(rasters) == 0){

    message(paste("Finished checking ",tag," extents",sep = ""))

    return(
      released_files %>%
        filter(tag == tag) %>%
        dplyr::select(file_name) %>%
        filter(file_name != "") %>%
        filter(grepl(pattern = ".tif$", x = file_name)) %>%
        mutate(date_format = gsub(pattern = ".tif",
                                  replacement = "",
                                  x = file_name))%>%
        mutate(date_format = gsub(pattern = "_", replacement = "-",
                                  x = date_format)) %>%
        dplyr::pull(date_format) %>%
        max()
    )


  }

  # IF extent checking is required, load the template used for comparison

  if(verbose){message("Using first MODIS layer as template")}



  robust_pb_download(file = released_files$file_name[1],
                     dest = file.path(temp_directory),
                     repo =   paste(released_files$owner[1],
                                    released_files$repo[1],sep = "/"),
                     tag = released_files$tag[1],
                     overwrite = TRUE,
                     max_attempts = 10,
                     sleep_time = sleep_time)


  template <- rast(file.path(temp_directory,released_files$file_name[1]))

  template_extent <- ext(template) |> as.character()

  # iterate and fix

  for(i in 1:length(rasters)){

    if(verbose){message("Checking raster ", i, " of ", length(rasters))}

    # download ith raster

    robust_pb_download(file = rasters[i],
                       dest = temp_directory,
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = tag,
                       overwrite = TRUE,
                       max_attempts = 10,
                       sleep_time = sleep_time)

    Sys.sleep(sleep_time)

    # load ith raster

    rast_i <- terra::rast(x = file.path(temp_directory,rasters[i]))

    # get the extent

    original_extent <- ext(rast_i) |> as.character()

    # check whether the raster matches the correct extent

    if(!identical(template_extent, original_extent)){

      message("Detected error in MODIS extent, correcting and logging the change")

      rast_i <- terra::resample(rast_i,y = template,method="near")

      # write a new raster with a different name

      terra::writeRaster(x = rast_i,
                         filename = file.path(temp_directory,gsub(pattern = ".tif$",
                                                                  replacement =".temp.tif",
                                                                  x =  rasters[i])),
                         filetype="GTiff",
                         overwrite = TRUE)

      # delete old raster

      unlink(file.path(temp_directory,rasters[i]))


      # update new name

      file.rename(from = file.path(temp_directory,gsub(pattern = ".tif$",
                                                       replacement =".temp.tif",
                                                       x =  rasters[i])),
                  to = file.path(temp_directory, rasters[i]))

      #log the change


      data.frame(file = rasters[i],
                 original_extent = original_extent,
                 final_extent = template_extent) %>%

        write.table(x = .,
                    file = file.path(temp_directory,"extent_log.csv"),
                    append = TRUE,
                    col.names = FALSE,
                    row.names=FALSE,
                    sep = ",")

      # push the updated raster

      # pb_upload(file = file.path(temp_directory,rasters[i]),
      #           repo = "AdamWilsonLab/emma_envdata",
      #           tag = tag,
      #           name = rasters[i], overwrite = TRUE)

      robust_pb_upload(files = file.path(temp_directory,rasters[i]),
                repo = "AdamWilsonLab/emma_envdata",
                tag = tag,
                name = rasters[i],
                overwrite = TRUE,
                sleep_time = sleep_time)


      #Sys.sleep(sleep_time)

      # push the updated log

      # pb_upload(file = file.path(temp_directory,"extent_log.csv"),
      #           repo = "AdamWilsonLab/emma_envdata",
      #           tag = tag)

      robust_pb_upload(file = file.path(temp_directory,"extent_log.csv"),
                repo = "AdamWilsonLab/emma_envdata",
                tag = tag,
                sleep_time = sleep_time)

      #Sys.sleep(sleep_time)

      # Delete the new raster

      unlink(file.path(temp_directory,rasters[i]))

    }else{

      #if the projection is correct, log it

      data.frame(file = rasters[i],
                 original_extent = original_extent,
                 final_extent = template_extent) %>%

        write.table(x = .,
                    file = file.path(temp_directory,"extent_log.csv"),
                    append = TRUE,
                    col.names = FALSE,
                    row.names=FALSE,
                    sep = ",")

      # pb_upload(file = file.path(temp_directory,"extent_log.csv"),
      #           repo = "AdamWilsonLab/emma_envdata",
      #           tag = tag)

      # robust_pb_upload(file = file.path(temp_directory,"extent_log.csv"),
      #           repo = "AdamWilsonLab/emma_envdata",
      #           tag = tag)

      robust_pb_upload(file = file.path(temp_directory,"extent_log.csv"),
                       repo = "AdamWilsonLab/emma_envdata",
                       tag = tag,
                       sleep_time = sleep_time)


      # Sys.sleep(sleep_time)

      unlink(file.path(temp_directory,rasters[i]))


    }

  } #for i rasters loop

  # Cleanup and end

  if(verbose){message("Cleaning up")}


  # Delete temp files
  unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)

  # Finish up

  message(paste("Finished checking ",tag," extents",sep = ""))

  return(
    rasters |>
      gsub(pattern = ".tif", replacement = "") |>
      gsub(pattern = "_",replacement = "-") |>
      max()
  )






} #end fx
