#' @description to correct the projection and extent of MODIS products downloaded from rgee
#' @author Brian Maitner
#' @param temp_directory The directory the layers should be temporarily saved in
#' @param input_tag tag associated with the Github release
#' @param output_tag
#' @param max_layers the maximum number of layers to correct at once.  Default (NULL) is to use all.
#' @param sleep_time amount of time to pause after using pb_upload/download.  Used to keep Git happy
#' @param verbose.  More messages are shown
process_fix_modis_release_projection_and_extent <-
  function(temp_directory,
           input_tag,
           output_tag,
           max_layers = NULL,
           sleep_time = 0.1,
           verbose = TRUE,
           ...){


    # specify the correct projection
      nasa_proj <- "+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +R=6371007.181 +units=m +no_defs"


    # get a list of released files
      released_files  <- pb_list(repo = "AdamWilsonLab/emma_envdata",
                                 tag = c(input_tag,output_tag,"raw_ndvi_modis"))

    # filter to only tifs

      released_files %>%
        filter(grepl(x = file_name, pattern = ".tif")) -> released_files

    #  #Ensure directory is empty if it exists

      if(dir.exists(temp_directory)){
        unlink(file.path(temp_directory), recursive = TRUE, force = TRUE)
      }


    # make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }

    # make releases if needed

      #Make sure there is an input release

      if(!input_tag %in% released_files$tag){

        if(verbose){message("Creating a new release")}

        tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                         tag =  input_tag),
                 error = function(e){message("Previous release found")})


      }

      #Make sure there is an output release

      if(!output_tag %in% released_files$tag){

        if(verbose){message("Creating a new release")}

        tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                         tag =  output_tag),
                 error = function(e){message("Previous release found")})


      }

    #Get a list of raster that haven't been fixed by comparing input and output

      input_rasters <- released_files %>% filter(tag == input_tag)

      output_rasters <- released_files %>% filter(tag == output_tag)

      rasters <- input_rasters %>%
        filter(!file_name %in% output_rasters$file_name) %>%
        pull(file_name)

    # Only do the first n layers if max_layers specified, otherwise do all of them

      if(!is.null(max_layers)){

        if(max_layers < length(rasters)){

          rasters <- rasters[1:max_layers]

        }
        }

    # check whether there is anything left to fix

      if(length(rasters) == 0){

            message(paste("Finished updating ",tag," projections",sep = ""))

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

    # get template raster to align extent to

      # IF extent checking is required, load the template used for comparison

      if(verbose){message("Using first MODIS layer as template")}

      template <-
      released_files %>%
        filter(tag == "raw_ndvi_modis") %>%
        arrange(file_name) %>%
        slice_head(n=1)

      robust_pb_download(file = template$file_name[1],
                         dest = file.path(temp_directory),
                         repo =   paste(template$owner[1],
                                        template$repo[1],sep = "/"),
                         tag = template$tag[1],
                         overwrite = TRUE,
                         max_attempts = 10,
                         sleep_time = sleep_time)

      #rename the file being used as template.  This is done for rare instances where it might confict with other names
      file.rename(from = file.path(temp_directory,template$file_name[1]),
                  to = file.path(temp_directory,"template.tif"))

      template <- rast(file.path(temp_directory,"template.tif"))

      template_extent <- ext(template) |> as.character()


    # iterate and fix

      for(i in 1:length(rasters)){

        if(verbose){message("Checking raster ", i, " of ", length(rasters))}

        # download ith raster

        robust_pb_download(file = rasters[i],
                           dest = temp_directory,
                           repo = "AdamWilsonLab/emma_envdata",
                           tag = input_tag,
                           overwrite = TRUE,
                           max_attempts = 10,
                           sleep_time = sleep_time)

        # load ith raster

          rast_i <- terra::rast(x = file.path(temp_directory,rasters[i]))

        # get the projection

          original_proj <- crs(rast_i, proj = TRUE)

        # check whether the raster matches the correct projection

          if(!identical(nasa_proj, original_proj)){

            message("Detected error in MODIS projection for raster ",rasters[i],
                    " correcting")

            crs(rast_i) <- nasa_proj

            }else{

              if(verbose){message("Raster ", rasters[i], " projection looks good")}

            }

        # check get the extent

          original_extent <- ext(rast_i) |> as.character()

        # check whether the raster matches the correct extent

          if(!identical(template_extent, original_extent)){

            message("Detected error in MODIS extent, correcting")

            rast_i <- terra::resample(rast_i,y = template,method="near")

          }else{

            if(verbose){message("Raster ", rasters[i], " extent looks good")}

          }


        # write a new raster with a different name

          terra::writeRaster(x = rast_i,
                             filename = gsub(pattern = ".tif$",
                                             replacement =".temp.tif",
                                             x =  file.path(temp_directory,rasters[i])),
                             filetype="GTiff",
                             overwrite = TRUE)

        # delete old raster

          unlink(file.path(temp_directory,rasters[i]))

        # update new name

          file.rename(from = gsub(pattern = ".tif$",
                                  replacement =".temp.tif",
                                  x =  file.path(temp_directory,rasters[i])),
                      to = file.path(temp_directory, rasters[i]))

        # push the updated raster

          pb_upload(file = file.path(temp_directory,rasters[i]),
                    repo = "AdamWilsonLab/emma_envdata",
                    tag = output_tag,
                    name = rasters[i],
                    overwrite = TRUE)

          Sys.sleep(sleep_time)

        # Using the regular pb_upload because it uses fewer queries

          # robust_pb_upload(file = file.path(temp_directory,rasters[i]),
          #                  repo = "AdamWilsonLab/emma_envdata",
          #                  tag = tag,
          #                  name = rasters[i],
          #                  overwrite = TRUE,
          #                  sleep_time = sleep_time)


          # Delete the new raster

          unlink(file.path(temp_directory,rasters[i]))


      } #for i rasters loop

    # Cleanup and end

      if(verbose){message("Cleaning up")}

      # Delete temp files

        unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)

      # Finish up

        message(paste("Finished checking ",input_tag," extents and projections",sep = ""))

        return(
          rasters |>
            gsub(pattern = ".tif", replacement = "") |>
            gsub(pattern = "_",replacement = "-") |>
            max()
        )


  } #end fx
