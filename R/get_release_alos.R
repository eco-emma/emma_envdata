#ALOS

#' @author Brian Maitner

#make a function to reduce code duplication

#' @param image_text is the text string used by gee to refer to an image, e.g. "CSP/ERGo/1_0/Global/ALOS_mTPI"
#' @param dir directory to save data in
#' @param domain domain (sf polygon) used for masking
#' @note This code is only designed to work with a handful of images by CSP/ERGo
get_alos_data <- function(image_text, dir, domain,
                          json_token){

  #Load the image

  focal_image <- ee$Image(image_text)

  focal_name <- focal_image$getInfo()$properties$visualization_0_name

  focal_name <- tolower(focal_name)

  focal_name <-gsub(pattern = " ", replacement = "_", x = focal_name)

  #Format the domain
  domain <- sf_as_ee(x = domain)
  domain <- domain$geometry()

  #get CRS
  crs <- focal_image$getInfo()$bands[[1]]$crs

  #Download the raster
  ee_as_raster(image = focal_image,
               region = domain,
               #scale = 100, #used to adjust the scale. commenting out uses the default
               dsn = file.path(dir,focal_name),
               maxPixels = 10000000000,
               drive_cred_path = json_token)


}# end function



#' @description This function makes use of the previous helper function to download data
#' @param domain domain (sf polygon) used for masking
#' @param temp_directory Where to save the files, defaults to "data/raw_data/alos/"
#' @param tag tag for the release you want the data stored in
get_release_alos <- function(temp_directory = "data/temp/raw_data/alos/",
                             tag = "raw_static",
                             domain,
                             json_token){

  #make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory, recursive = TRUE)
    }


  #Make sure there is a release by attempting to create one.  If it already exists, this will fail

    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  tag),
             error = function(e){message("Previous release found")})


  #Initialize earth engine (for targets works better if called here)

    #ee_Initialize()

  # Get files that have been downloaded

    alos_files <- list.files(temp_directory, pattern = ".tif$")

  #Download files that have not previously been downloaded

  # mTPI
    if(!length(grep(pattern = "mtpi",x = alos_files)) > 0){

      get_alos_data(image_text = "CSP/ERGo/1_0/Global/ALOS_mTPI",
                    dir = temp_directory,
                    domain = domain,
                    json_token = json_token)

    }

      # release
        pb_upload(repo = "AdamWilsonLab/emma_envdata",
                  file = file.path(temp_directory,"alos_mtpi.tif"),
                  tag = tag,
                  name = "alos_mtpi.tif")

      # delete
        file.remove(file.path(temp_directory,"alos_mtpi.tif"))


  # CHILI
    if(!length(grep(pattern = "chili",x = alos_files)) > 0){

      get_alos_data(image_text = "CSP/ERGo/1_0/Global/ALOS_CHILI",
                    dir = temp_directory,
                    domain = domain,
                    json_token = json_token)

    }

        # release
          pb_upload(repo = "AdamWilsonLab/emma_envdata",
                    file = file.path(temp_directory,"alos_chili.tif"),
                    tag = tag,
                    name = "alos_chili.tif")

        # delete
          file.remove(file.path(temp_directory,"alos_chili.tif"))


  # landforms
    if(!length(grep(pattern = "landforms",x = alos_files)) > 0){
      get_alos_data(image_text = 'CSP/ERGo/1_0/Global/ALOS_landforms',
                    dir = temp_directory,
                    domain = domain,
                    json_token = json_token)
    }

        # release
        pb_upload(repo = "AdamWilsonLab/emma_envdata",
                  file = file.path(temp_directory,"landforms.tif"),
                  tag = tag,
                  name = "alos_landforms.tif")

        # delete
        file.remove(file.path(temp_directory,"landforms.tif"))


  # topo diversity
    if(!length(grep(pattern = "topographic",x = alos_files)) > 0){
      get_alos_data(image_text = 'CSP/ERGo/1_0/Global/ALOS_topoDiversity',
                    dir = temp_directory,
                    domain = domain,
                    json_token = json_token)
    }

        # release
        pb_upload(repo = "AdamWilsonLab/emma_envdata",
                  file = file.path(temp_directory,"alos_topographic_diversity.tif"),
                  tag = tag,
                  name = "alos_topodiversity.tif")

        # delete
        file.remove(file.path(temp_directory,"alos_topographic_diversity.tif"))


    # Clean up
        unlink(x = file.path(temp_directory), recursive = TRUE)


  message("Finished downloading ALOS layers")


  return(tag)

}



##################################

