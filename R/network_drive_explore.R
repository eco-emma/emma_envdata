# box code not working
library(boxr)
library(tidyverse)

# library(fs)
# dir_create("~/.boxr-auth")

# from https://github.com/r-box/boxr/issues/166
# options(boxr.retry.times = 10)

#box_auth()

# sometimes this fails for no apparent reason - must just wait for it to work again!
# https://github.com/r-box/boxr/issues/166
box_auth_service()
#box_auth_service(token_text = unlist(read_lines('~/.boxr-auth/token.json')))

# root directory


box_setwd()


# create new directory to hold results
dir_name="emmabox"
box_dir_create(dir_name = dir_name)

eid <- box_ls() %>% as.data.frame() %>% filter(name==dir_name)

# Share folder with
uid=271686873  # adamw@buffalo.edu


box_collab_create(
  dir_id = eid$id,
  user_id = uid,
  role = "co-owner",
  can_view_path = TRUE
)

# set box working directory
box_setwd(eid$id)
box_setwd("..")

boxr_options()
box_ls()

# test writing to folder
box_write(
  iris,
  "iris.csv")

files <- box_ls() %>% as.data.frame

files %>%
  filter(name=="iris.csv") %>%
  select(id) %>% unlist() %>%
  box_delete_file()




