#https://books.ropensci.org/targets/walkthrough.html

#Install stuff I may not have already
  install.packages("cubelyr")

# Inspect the pipeline
  tar_manifest()

#visualize the pipeline
  tar_glimpse()
  tar_visnetwork()

#run the pipeline
  tar_make()

