# Git functions

if(F){
  gitcreds::gitcreds_get()

}


update_git <- function(){

  for(x in list.files("data",recursive=T,full=T))
    system(paste0("git lfs track ",x))

}


