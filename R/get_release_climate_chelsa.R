#R script to download climate data (CHELSA)

library(ClimDatDownloadR)

#' @author Brian Maitner
#' @description This function will download CHELSA climate data if it isn't present, and (invisibly) return a NULL if it is present
#' @param temp_directory Where to save the files, defaults to "data/raw_data/climate_chelsa/"
#' @param domain domain (sf polygon) used for masking
#' @param tag Tag for the release
#' @import ClimDatDownloadR
get_release_climate_chelsa <- function(temp_directory = "data/temp/raw_data/climate_chelsa/",
                                       tag = "raw_static",
                                       domain){

  #ensure temp directory is empty

    if(!dir.exists(temp_directory)){
      unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)
    }

  #make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory)
    }


  #Make sure there is a release by attempting to create one.  If it already exists, this will fail

    tryCatch(expr =   pb_new_release(repo = "AdamWilsonLab/emma_envdata",
                                     tag =  tag),
             error = function(e){message("Previous release found")})

  #Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

    if(getOption('timeout') < 1000){
      options(timeout = 1000)
    }


  #Transform domain to wgs84 to get the coordinates

    domain_extent <- sf::sf_project(from = crs(domain)@projargs,
                                    to =   crs("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")@projargs,
                                    pts = t(as.matrix(extent(domain))))


  # Download the data
  # Note that it would be useful to clip these to a polygon to save space
  # It would also be useful if only the relevant data could be downloaded (rather than downloading and THEN pruning)


      ClimDatDownloadR::Chelsa.Clim.download(save.location = temp_directory,
                                             parameter = "bio",
                                             clip.extent = domain_extent[c(1,2,3,4)],
                                             clipping = TRUE,
                                             delete.raw.data = TRUE
      )

    #fix names

      to_rename <- list.files(path = file.path(temp_directory),
                              pattern = "_clipped.tif",full.names = TRUE,recursive = TRUE)

      for(i in 1:length(to_rename)){
        file.rename(from = to_rename[i],
                    to = gsub(pattern = "_clipped.tif",
                              replacement = "",
                              x = to_rename[i]))
        }

    # release
      to_release <-
        list.files(path = file.path(temp_directory),
                   recursive = TRUE,
                   full.names = TRUE)


      to_release <-
        to_release[grepl(pattern = "CHELSA",
                         ignore.case = TRUE,
                         x = basename(to_release))]

        pb_upload(repo = "AdamWilsonLab/emma_envdata",
                  file = to_release,
                  tag = tag)

    # delete directory and contents
        unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)



  message("CHELSA climate files downloaded")
  return(tag)


} # end fx

