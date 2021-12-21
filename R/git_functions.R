# Git functions

if(F){
  gitcreds::gitcreds_get()

}


update_git <- function(){
  system("git lfs track data/*")
}


