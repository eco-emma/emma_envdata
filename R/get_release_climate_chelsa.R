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

  #make a directory if one doesn't exist yet

    if(!dir.exists(temp_directory)){
      dir.create(temp_directory)
    }

  #check for files

    # if( length(list.files(directory,pattern = "clipped.tif", recursive = T)) == 19){
    #   message("CHELSA files found, skipping download")
    #   return(invisible(NULL))
    # }
    #

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



    dirs <- list.dirs(file.path(temp_directory,"bio/"),
                      recursive = TRUE,
                      full.names = TRUE)

    dirs <-dirs[grep(pattern = "clipped",x = dirs)]

    file.rename(from = dirs,
                to = paste(strsplit(x = dirs,
                                    split = "clipped")[[1]][1],
                           "clipped",
                           sep = "")
    )

    file.rename(from = list.files(dirs,full.names = TRUE,pattern = ".tif"),
                to = gsub(pattern = "_clipped",replacement = "",x = list.files(dirs,full.names = TRUE,pattern = ".tif"))
    )


    rm(dirs)

    stop("Code goes here to release and delete files")

    # release
        pb_upload(repo = "AdamWilsonLab/emma_envdata",
                  file = list.files(file.path(temp_directory),
                                    recursive = TRUE,
                                    full.names = TRUE),
                  tag = tag)

    # delete directory and contents
        unlink(x = file.path(temp_directory), recursive = TRUE, force = TRUE)



  message("CHELSA climate files downloaded")
  return(directory)


} # end fx

