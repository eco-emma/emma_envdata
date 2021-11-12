#Fire Data

#' @author Brian Maitner




ee_Initialize()


#CCI not working

# Load the image
  fire_cci <- ee$ImageCollection("ESA/CCI/FireCCI/5_1")
  # fire_cci <- ee$ImageCollection$Dataset$ESA_CCI_FireCCI_5_1 #This is equivalent to the above

#Get metadata
  cci_info <- fire_cci %>% ee$ImageCollection$getInfo()
  cci_features <- cci_info$features
  cci_features[[3]]$id #ID seems to correspond to the y_m_d
  cci_features[[1]]$properties

  fire_cci[[1]] %>% ee$Date()


fire_cci$Dataset$ESA_CCI_FireCCI_5_1()
fire_cci %>% filte

?ee

filterDate('2019-01-01', '2019-12-31')

#Get metadata
cci_info <- fire_cci %>% ee$Image$getInfo()

##################################################

#SA fire data


