# generate the model data object


get_model_data <- function(remnant_distance, file="data/model_data.csv"){

  tar_load(remnant_distance)

  env=bind_cols(
    remnant_distance=as.data.frame(stars::read_stars(remnant_distance))
  ) %>%
    filter(remnant_distance>0)

write_csv(env,file=file)

return(file)

}
