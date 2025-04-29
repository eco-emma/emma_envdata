#Code for downloading raw data used by the EMMA project

#' @author Brian Maitner


# This code was written to work with a particular docker instance, to set it up (modifying your directory accordingly):
# docker run -d -e DISABLE_AUTH=true -p 8787:8787 -v C:/Users/"Brian Maitner"/Desktop/current_projects/emma_envdata:/home/rstudio/emma_envdata adamwilsonlab/emma:latest


# Code to ensure the directory in docker matches the directory in the github project in rstudio
if(getwd() == "/home/rstudio"){setwd("/home/rstudio/emma_envdata/")}

#Install packages not in docker image
#install.packages("bibtex", "rdryad")
#install.packages("cmdstanr", repos = c("https://mc-stan.org/r-packages/", getOption("repos")))

#Load packages
library(rgee)
library(targets)

library(remotes)
install_github("r-spatial/rgee")

#Note!! For setting up rgee the first time (on an interactive docker instance), see the file "auth_on_server.R"

# source all files in R folder
lapply(list.files("R",pattern="[.]R",full.names = T), source)


#For updating github credentials

#drive_auth(path = "/path/to/your/service-account-token.json")
library(googledrive)
googledrive::drive_deauth()

googledrive::drive_auth(path = "scratch_code/maitner-f590bfc7be54.json")

################################
# Setting up encrypted credentials: see https://docs.github.com/en/enterprise-server@3.5/actions/security-guides/encrypted-secrets

  # Encrypting

    # $gpg --symmetric --cipher-algo AES256 my_secret.json

  # Decrypting

    # $gpg --quiet --batch --yes --decrypt --passphrase="SecretPhrase" --output my_secret.json my_secret.json.gpg



################################################################################

# Notes:

# https://lpdaac.usgs.gov/products/vnp64a1v001/ VIIRS fire data is forthcoming but not available yet

#https://books.ropensci.org/targets/walkthrough.html

#Install stuff I may not have already
  install.packages("cubelyr","visNetwork","rdryad")
  install.packages("arrow")

library(targets)
library(rgee)

#?#curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-415.0.0-linux-x86_64.tar.gz

  #tar -xf google-cloud-cli-415.0.0-linux-x86.tar.gz

  #./google-cloud-sdk/install.sh

ee_clean_pyenv()
rgee::ee_install()
rgee::ee_install_upgrade()
rgee::ee_Initialize()

ee_users()
ee_clean_credentials("ndef")


# Inspect the pipeline
  tar_manifest()

#visualize the pipeline
  tar_glimpse(level_separation = 200)
  tar_visnetwork()



curr_network <- tar_glimpse()
#curr_network <- tar_visnetwork()
htmlwidgets::saveWidget(widget = curr_network,
                        file = "scratch_code/current_network.html")
webshot::install_phantomjs()
webshot::webshot(url = "scratch_code/current_network.html",
                 file = "scratch_code/current_network.png",delay = 2,zoom = 10,vwidth = 400,vheight = 200)


?webshot
#run the pipeline
  tar_make()

  #tar_destroy("meta",ask = FALSE)

##################

#need to update rgee functions to use correct filename if only one layer
#need to update rgee functions to skip download if there is nothing TO download (since it takes a while to upload the domain)


###########################

#usethis::create_github_token()
#
  gitcreds::gitcreds_set()




library(arrow)
# Example code for working with arrow library


x <- open_dataset(sources = "data/processed_data/dynamic_parquet/")

x$schema
x$metadata

x  %>%
  filter(variable != "ndvi")%>%
  filter(date == 11261)%>%
  summarise(mean = mean(value))%>%
  head() %>%
  collect()

gitcreds::gitcreds_set()

#############################
#Whats in the repo?

all_releases <- pb_list("AdamWilsonLab/emma_envdata")

all_releases %>%
  group_by(tag)%>%
  summarize(n=n())



#######################

#clean up drive (note: should add this code to targets)
googledrive::drive_trash(file = googledrive::drive_ls("rgee_backup"))

