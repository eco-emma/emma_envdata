# Clouds

#####################################################################################
# http://www.earthenv.org/cloud


library(xml2)
library(rvest)
library(raster)


#Set up directories if need be
if(!dir.exists("docker_volume/raw_data/clouds_wilson")){
  dir.create("docker_volume/raw_data/clouds_wilson")
}

if(!dir.exists("docker_volume/raw_data/clouds_wilson/clipped")){
  dir.create("docker_volume/raw_data/clouds_wilson/clipped")
}

#Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

  if(getOption('timeout') < 1000){
    options(timeout = 1000)  
  }


#Get a list of the available files
  URL <- "http://www.earthenv.org/cloud"
  links <- html_attr(html_nodes(read_html(URL), "a"), "href")
  links <- links[grep(pattern = "MODCF", x = links)]

#Download each file (note: we might also consider updating this to ignore layers that are already present)
  for( i in 1:length(links)){
    
    layer_i <- links[i]
    
    # split out the filename from the location    
    filename <- strsplit(x = layer_i,split = "/")[[1]][length(strsplit(x = layer_i,split = "/")[[1]])]
    
    # download the full file
    download.file(url = links[i],
                 destfile = paste("docker_volume/raw_data/clouds_wilson/",filename,sep = ""))
    
    # Load in the downloaded file
    raster_i <- raster(paste("docker_volume/raw_data/clouds_wilson/",filename,sep = ""))
    
    # Make an extent for cropping
    sabb <- as(extent(16.3449768409,32.830120477,
                      -34.8191663551, -22.0913127581),
               'SpatialPolygons')
    
    crs(sabb) <- crs(raster_i)
    
    # Crop the raster to the specified extent and save
      #Note that cropping and then writing doesn't work for some reason
    cropped_i <- raster::crop(x = raster_i,
                              y =  sabb,
                              filename = paste("docker_volume/raw_data/clouds_wilson/clipped/",
                                               filename,
                                               sep = ""),
                              overwrite = TRUE)
    
    # Delete the larger file
    file.remove(paste("docker_volume/raw_data/clouds_wilson/",
                      filename,sep = ""))
    
  }#end of for i loop

#Cleanup
  rm(layer_i,filename,URL,links,i,sabb,raster_i)
  
################################################################################
