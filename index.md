EMMA Prototype
================
true
10-13-2021

``` r
library(targets)
library(tidyverse)
# load data saved in the pipeline
tar_load(c(model,  model_output, posterior_summary)) #data, stan_data,
```

The details are given in
\[@slingsby\_near-real\_2020;@wilson\_climatic\_2015\], but in short
what we do is estimate the age of a site by calculating the years since
the last fire. We then fit a curve to model the recovery of vegetation
(measured using NDVI) as a function of it’s age. For this we use a
negative exponential curve with the following form:

$$\\mu\_{i,t}=\\alpha\_i+\\gamma\_i\\Big(1-e^{-\\frac{age\_{i,t}}{\\lambda\_i}}\\Big)$$

where *μ*<sub>*i*, *t*</sub> is the expected NDVI for site *i* at time
*t*

The observed greenness *N**D**V**I*<sub>*i*, *t*</sub> is assumed to
follow a normal distribution with mean *μ*<sub>*i*, *t*</sub>
*N**D**V**I*<sub>*i*, *t*</sub> ∼ 𝒩(*μ*<sub>*i*, *t*</sub>, *σ*<sub>)</sub>

An additional level models the parameters of the negative exponential
curve as a function of environmental variables. This means that sites
with similar environmental conditions should have similar recovery
curves. The full model also includes a sinusoidal term to capture
seasonal variation, but lets keep it simple here.

## ADVI

We have `age` in years, a plot identifier `pid`. the observed ndvi `nd`
and two plot level environmental variable `env1`, which is mean annual
precipitation, and `env2`, which is the summer maximum temperature.

Lets load up our Stan model which codes the model described above. This
is not a particularly clever or efficient way of coding the model, but
it is nice and readable and works fine on this example dataset

``` r
model_output$print()
```

    ##     variable      mean    median     sd    mad        q5       q95
    ##  lp__        193260.38 193312.00 338.23 111.19 193021.95 193459.00
    ##  lp_approx__   -632.95   -631.33  24.93  25.67   -676.25   -595.35
    ##  alpha[1]        -1.47     -1.47   0.02   0.02     -1.51     -1.44
    ##  alpha[2]        -1.27     -1.27   0.02   0.02     -1.31     -1.24
    ##  alpha[3]        -2.22     -2.22   0.04   0.04     -2.29     -2.15
    ##  alpha[4]        -1.08     -1.08   0.01   0.01     -1.10     -1.06
    ##  alpha[5]        -1.24     -1.24   0.02   0.02     -1.28     -1.20
    ##  alpha[6]        -1.23     -1.23   0.01   0.01     -1.26     -1.21
    ##  alpha[7]        -1.45     -1.45   0.02   0.02     -1.48     -1.43
    ##  alpha[8]        -0.76     -0.76   0.01   0.01     -0.78     -0.75
    ## 
    ##  # showing 10 of 275466 rows (change via 'max_rows' argument or 'cmdstanr_max_rows' option)

How long did that take?

``` r
model_output$time()$total
```

    ## [1] 243.9702

``` r
params=c("tau","alpha_mu","gamma_b2","gamma_b1","lambda_b1","lambda_b2")
posteriors=model_output$draws(params) %>% 
  as_tibble() %>% 
  gather(parameter)
ggplot(posteriors,aes(x=value))+
  geom_density(fill="grey")+
  facet_wrap(~parameter,scales = "free")
```

![](index_files/figure-gfm/p1-1.png)<!-- -->

When we make this comparison, the posterior predictive intervals from
ADVI and MCMC are almost identical

``` r
posterior_summary %>% 
    filter(pid %in% as.numeric(sample(levels(as.factor(posterior_summary$pid)),20))) %>% # just show a few
  ggplot(aes(x=age)) +
  geom_line(aes(y=mean),colour="blue") +
  geom_line(aes(y=nd),colour="black",lwd=0.5,alpha=0.3) +
  geom_ribbon(aes(ymin=q5,ymax=q95),alpha=0.5)+
  facet_wrap(~pid) +
  xlim(c(0,20))+
  labs(x="time since fire (years)",y="NDVI") +
  theme_bw()
```

![](index_files/figure-gfm/plot-1.png)<!-- -->

# Spatial Predictions

``` r
stan_spatial <- stan_vb %>% 
  mutate(pid=gsub("[]]","",gsub(".*[[]","",variable))) %>% 
  bind_cols(select(data,x,y,age,nd))

foreach(t=unique(raw_data$DA),.combine=stack) %do% {
stan_spatial %>% 
    filter(DA=t) %>%
    select(x,y,age,nd,mean,q5) %>% 
    rasterFromXYZ()
}
```
