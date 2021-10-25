# box code not working

# library(fs)
# dir_create("~/.boxr-auth")

# from https://github.com/r-box/boxr/issues/166
options(boxr.retry.times = 10)

library(boxr)
library(tidyverse)
box_auth()
box_auth_service()
box_auth_service(token_text = unlist(read_lines('~/.boxr-auth/token.json')))






# FTP - code below not working

# url <- "ftps://ftp.box.com"
# opts = curlOptions(header = TRUE, userpwd = userpwd, netrc = TRUE)
# filenames1 <- getURL(url, .opts=opts,
#                     ftp.use.epsv=FALSE, crlf = TRUE,dirlistonly = TRUE)
# filenames <-paste(url, strsplit(filenames, "\r*\n")[[1]], sep = "")
#
# data=data.frame(x=1:10)
# save(data,file="data.Rds")
# ftpUpload("data.Rds", paste0(userpwd,"@",url,"/data.Rda"), .opts=opts)#curl = getCurlHandle())
#
# ftpUpload(I("Some text to be uploaded into a file\nwith several lines"),
#           to=paste0(userpwd,"@",url,"/data"),
# )
