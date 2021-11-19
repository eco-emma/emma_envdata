library(raster)
library(lubridate)
library(sf)
library(fasterize)

  l1 <- raster("docker_volume/raw_data/fire_modis/2000_11_01.tif")
  l2 <- raster("docker_volume/raw_data/fire_modis/2000_12_01.tif")
  plot(l1)
  unique(getValues(l1))

#First, we grab the historical fire data
  fire_sanbi <- st_read(dsn = "docker_volume/raw_data/fire_sanbi")
fire_sanbi$DATESTART


#Next, we need to make a list of all available files and the timestamps

  #Get the files
    fire_files <- list.files("docker_volume/raw_data/fire_modis/",pattern = ".tif",full.names = TRUE)

  #Make a lookup table for convenience
    fire_table <- data.frame(fire_file = fire_files,
                             date = gsub(pattern = ".tif",
                                         replacement = "",
                                         x = sapply(X = fire_files,FUN = function(x){strsplit(x,"/")[[1]][4]})))

    fire_table$date <- as_date(fire_table$date)

  #Ensure the table order is correct. This is probably not necessary, but it never hurts to be safe.
    fire_table <- fire_table[order(fire_table$date),]

#Process SANBI data to match modis format

  #The SA fire data are polygons, so I'll rasterize them to match the modis rasters

    sanbi_month <- fasterize(sf = st_transform(x = fire_sanbi,crs = crs(raster(fire_table$fire_file[1]))),
                             raster = raster(fire_table$fire_file[1]),
                             field = "MONTH",
                             fun = "max")

    sanbi_year <- fasterize(sf = st_transform(x = fire_sanbi,crs = crs(raster(fire_table$fire_file[1]))),
                             raster = raster(fire_table$fire_file[1]),
                             field = "YEAR",
                             fun = "max")

    #Make lookup table
      sanbi_stack <- stack(sanbi_month,sanbi_year)

      sanbi_values <- unique(getValues(sanbi_stack))
      sanbi_values <- as.data.frame(sanbi_values)
      sanbi_values$sanbi_integer_my <- apply(X = sanbi_values[,1:2],
                                             MARGIN = 1,
                                             FUN = function(x,...){ #Note that the ... doesn't do anything, but is needed for stackApply
                                               if(identical(as.numeric(x[1]),0)){
                                                 return(as.numeric(my(paste(c(1,x[2]),collapse = "/"))))
                                                 }
                                               suppressWarnings(as.numeric(my(paste(x,collapse = "/"))))
                                               })



    #Use merge to convert the month-year data into integer. I use merge vs. stackApply since it seems to be faster given the relatively few unique values.

      #Get month and year data
      sanbi_ym_df <- data.frame(ID= 1:ncell(sanbi_month),
                                month=getValues(sanbi_month),
                                year = getValues(sanbi_year))

      #Use merge to combine raster values with the lookup table
      sanbi_ym_df <-
        merge(x = sanbi_ym_df,
              y = sanbi_values,
              by.x = c("month","year"),
              by.y = c("layer.1","layer.2"),
              sort = F)

      #Ensure the order is correct
      sanbi_ym_df <- sanbi_ym_df[order(sanbi_ym_df$ID),]

      #Create the new raster
      sanbi_integer_my <- setValues(x = sanbi_month,
                                    values = sanbi_ym_df$sanbi_integer_my)

      #plot(sanbi_integer_my)

      #cleanup
      rm(fire_sanbi,fire_table,sanbi_month,sanbi_year,sanbi_ym_df,sanbi_values,sanbi_stack)

  #The modis fire products have the day of the year they burned on (or zero if they didn't burn)
