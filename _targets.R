library(targets)
library(tarchetypes)
source("R/functions.R")
options(tidyverse.quiet = TRUE)
options(clustermq.scheduler = "multicore")

#install.packages("cmdstanr", repos = c("https://mc-stan.org/r-packages/", getOption("repos")))

tar_option_set(packages = c("cmdstanr", "posterior", "bayesplot", "tidyverse", "stringr","knitr"))

list(
  tar_target(
    raw_data_file,
    "data/postfire.csv",
    format = "file"
  ),
  tar_target(
    raw_data,
    read_csv(raw_data_file)[-1,]
  ),
  tar_target(
    data,
    raw_data %>%
      clean_data()
  ),
  tar_target(
    group_data,
    data %>%
      group_data_function()
  ),
  tar_target(
    stan_data,
    stan_data_function(data,group_data)
  ),

  tar_target(model,
             cmdstan_model('firemodel_predict.stan',
                           compile = TRUE)),

  tar_target(model_fit, fit_model(model, stan_data)),

  tar_target(posterior_summary,
           summarize_posteriors(model_fit,data)),


  tar_render(report, "index.Rmd")

)
