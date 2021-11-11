# land cover from https://egis.environment.gov.za/sa_national_land_cover_datasets

  #Note: I'm not sure if this is a permanent link or not, so this might not be a permanent solution

  url <- "https://sfiler.environment.gov.za:8443/ssf/s/readFile/folderEntry/40906/8afbc1c77a484088017a4e8a1abd0052/1624802570000/last/SA_NLC_2020_Geographic.tif.vat.zip"
  filename <- strsplit(x = url,split = "/",fixed = T)[[1]][length(strsplit(x = url,split = "/",fixed = T)[[1]])]

#Adjust the download timeout duration (this needs to be large enough to allow the download to complete)

  if(getOption('timeout') < 1000){
    options(timeout = 1000)  
  }


#make a directory if one doesn't exist yet

  if(!dir.exists("docker_volume/raw_data/landcover")){
    dir.create("docker_volume/raw_data/landcover")
  }

#Download the file
  download.file(url = "https://sfiler.environment.gov.za:8443/ssf/s/readFile/folderEntry/40906/8afbc1c77a484088017a4e8a1abd0052/1624802570000/last/SA_NLC_2020_Geographic.tif.vat.zip",
                destfile = paste("docker_volume/raw_data/landcover/",filename,sep = ""))

#Unzip the file  
  unzip(zipfile = paste("docker_volume/raw_data/landcover/",filename,sep = ""),
        exdir = "docker_volume/raw_data/landcover/")

#Delete the zipped version (which isn't much smaller anyway)
  file.remove(paste("docker_volume/raw_data/landcover/",filename,sep = ""))



