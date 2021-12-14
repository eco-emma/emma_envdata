#ALOS

#' @author Brian Maitner


#make a directory if one doesn't exist yet

  if(!dir.exists("data/raw_data/alos")){
    dir.create("data/raw_data/alos")
  }

#Make a bounding box of the extent we want

  ext <- readRDS(file = "data/other_data/domain_extent.RDS")

  sabb <- ee$Geometry$Rectangle(
    coords = c(ext@xmin,ext@ymin,ext@xmax,ext@ymax),
    proj = "EPSG:4326",
    geodesic = FALSE
  )

  rm(ext)



#make a function to reduce code duplication
  get_alos_data <- function(image_text){


    focal_image <- ee$Image(image_text)


    focal_name <- focal_image$getInfo()$properties$visualization_0_name
    focal_name <- tolower(focal_name)
    focal_name <-gsub(pattern = " ", replacement = "_", x = focal_name)


    #get CRS
    crs <- focal_image$getInfo()$bands[[1]]$crs

    #Set Visualization parameters

    # focalviz <- list(
    #   min = focal_image$getInfo()$properties$visualization_0_min,
    #   max = focal_image$getInfo()$properties$visualization_0_max,
    #   palette = c('00FFFF','FF00FF')
    # )
    #
    #
    # # Display the image.
    # Map$centerObject(focal_image)
    # Map$addLayer(focal_image,visParams = focalviz)

    #Get name


    #Download the raster
    ee_as_raster(image = focal_image,
                 region = sabb,
                 #scale = 100, #used to adjust the scale. commenting out uses the default
                 dsn = paste("data/raw_data/alos/",focal_name,sep = ""),
                 maxPixels = 10000000000)


  }# end function


##################################

# mTPI
  get_alos_data(image_text = "CSP/ERGo/1_0/Global/ALOS_mTPI")

# CHILI

  get_alos_data(image_text = "CSP/ERGo/1_0/Global/ALOS_CHILI")

# landforms

  get_alos_data(image_text = 'CSP/ERGo/1_0/Global/ALOS_landforms')

# topo diversity

  get_alos_data(image_text = 'CSP/ERGo/1_0/Global/ALOS_topoDiversity')

