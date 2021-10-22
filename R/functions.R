#tidy up
clean_data <- function(raw_data_file){
  raw_data_file %>%
  filter(ND>0) %>% #remove impossible NDVI values
  filter(nid %in% as.numeric(sample(levels(as.factor(raw_data_file$nid)),50))) %>% #subset plots
  mutate(age=DA/365.23) %>% #convert age from days to years
  select(age=age,nd=ND,pid=nid,x,y,env1=map,env2=tmax01) %>%
  mutate(pid = as.numeric(as.factor(pid))) %>%
  mutate(env1 = (env1 - mean(env1))/sd(env1),env2 = (env2 - mean(env2))/sd(env2)) #standardize env variables
}



# group data
#plots level data on env conditions
group_data_function <- function(data){
  data %>%
  group_by(pid) %>%
  summarise(envg1 = max(env1),envg2 = max(env2))
}

#prep data for stan
stan_data_function <- function(data,group_data){
  list(N = nrow(data),
                      J= nrow(group_data),
                      nd=data$nd,
                      age= data$age,
                      pid=data$pid,
                      envg1 = group_data$envg1,
                      envg2 = group_data$envg2)
}


# fit model
fit_model<- function(model,data){
  model_results=
    model$variational(
    data = data,
    adapt_engaged=FALSE,
    eta=0.1,
    tol_rel_obj = 0.001,
    seed = 123)

  model_results$draws()
  try(model_results$sampler_diagnostics(), silent = TRUE)
  try(model_results$init(), silent = TRUE)
  try(model_results$profiles(), silent = TRUE)
#  model_results$save_object(file)
  return(model_results)
}


# Summarize posteriors
summarize_posteriors <- function(model_output,data){
    #posterior predictive
  tdata<- model_output$summary("nd_new","mean","quantile2") %>%
#    mutate(pid=gsub("[]]","",gsub(".*[[]","",variable))) %>%  #extract pid from parameter names
    bind_cols(select(data,x,y,pid,age,nd))  # be careful - this just binds and not a full join - don't change row order!!!!!

  #wrangle
#  stan_ndvi <- rbind(stan_vb) %>%
#    select(age=age,NDVI=nd,pid,mean,upper=q95,lower=q5) %>%
#    filter(pid %in% as.numeric(sample(levels(as.factor(stan_vb$pid)),20)))

  return(tdata)
}

# Spatial Predictions

spatial_outputs <- function(posteriors) {
message("This function doesn't work - need to get actual dates from the original data!!!!!")
  stan_spatial <- stan_vb %>%
  mutate(pid=gsub("[]]","",gsub(".*[[]","",variable))) %>%
  bind_cols(select(data,x,y,age,nd))

foreach(t=unique(raw_data$DA),.combine=stack) %do% {
  stan_spatial %>%
    filter(DA=t) %>%
    select(x,y,age,nd,mean,q5) %>%
    rasterFromXYZ()
}
}
