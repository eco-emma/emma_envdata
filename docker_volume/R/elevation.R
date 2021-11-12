#Code for extracting elevation data from google earth engine

#' @author Brian Maitner

#NASADEM

#Initialize
ee_Initialize()


# Load the image
dem <- ee$Image("NASA/NASADEM_HGT/001")

#Cut down to the one band we need
dem<- dem$select("elevation")

#Get metadata
deminfo <- dem %>% ee$Image$getInfo()

#get CRS
crs <- deminfo$bands[[1]]$crs

#Make a bounding box of South Africa so we can download just the relevant data
# Note: it would be better to use a polygon of just the focal regions instead
sabb <- ee$Geometry$Rectangle(
  coords = c(16.3449768409, -34.8191663551, 32.830120477, -22.0913127581),
  proj = crs,
  geodesic = FALSE
)

#Set Visualization parameters

demviz <- list(
  bands = "elevation",
  min = -500,
  max = 9000,
  palette = c('00FFFF','FF00FF')
)

# Display the image.
Map$centerObject(dem)
Map$addLayer(dem, name = "DEM",visParams = demviz)


#Download the raster
ee_as_raster(image = dem,
             region = sabb,
             #scale = 100, #used to adjust the scale. commenting out uses the default
             dsn = "docker_volume/raw_data/NASADEM",
             maxPixels = 10000000000)


library(raster)
sadem1 <- raster::raster("docker_volume/raw_data/NASADEM-0001.tif")
sadem2 <- raster::raster("docker_volume/raw_data/NASADEM-0002.tif")
sadem <- raster::mosaic(x = sadem1,
                        y = sadem2,
                        fun = mean)

#Cleanup intermediate files
rm(sadem1,sadem2)

#Plot
plot(sadem)

#Save combined files
writeRaster(x = sadem,
            filename = "docker_volume/raw_data/NASADEM.tif")

#Remove bits
file.remove(c("docker_volume/raw_data/NASADEM-0001.tif",
              "docker_volume/raw_data/NASADEM-0002.tif"))


