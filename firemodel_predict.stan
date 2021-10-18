data {
  int<lower=0> N;
  int<lower=0> J;
  int<lower=1,upper=J> pid[N];
  vector[N] age;
  vector[N] nd;
  vector[J] envg1;
  vector[J] envg2;

}
parameters {
  vector[J] alpha;
  vector[J] gamma;
  vector[J] lambda;
  real alpha_mu;
  real gamma_b1;
  real gamma_b2;
  real lambda_b1;
  real lambda_b2;
  real<lower=0> tau_sq;
  real<lower=0> gamma_tau_sq;
  real<lower=0> lambda_tau_sq;
  real<lower=0> alpha_tau_sq;
}

transformed parameters {
  vector[N] mu;
  vector[J] gamma_mu;
  vector[J] lambda_mu;
  real tau = sqrt(tau_sq);
  real gamma_tau = sqrt(gamma_tau_sq);
  real lambda_tau = sqrt(lambda_tau_sq);
  real alpha_tau = sqrt(alpha_tau_sq);

  for (j in 1:J){
    gamma_mu[j] = (envg1[j]*gamma_b1) + (envg2[j]*gamma_b2);
    lambda_mu[j] = (envg1[j]*lambda_b1) + (envg2[j]*lambda_b2);
  }

  for (i in 1:N){
    mu[i] = exp(alpha[pid[i]])+exp(gamma[pid[i]])-exp(gamma[pid[i]])*exp(-(age[i]/exp(lambda[pid[i]])));
  }
}

model {

  tau ~  inv_gamma(0.01, 0.01);
  gamma_tau ~ inv_gamma(0.01, 0.01);
  lambda_tau ~ inv_gamma(0.01, 0.01);
  alpha_tau ~ inv_gamma(0.01, 0.01);

  alpha_mu ~ normal(0.15,3);
  gamma_b1 ~ normal(0,3);
  gamma_b2 ~ normal(0,3);
  lambda_b1 ~ normal(0,3);
  lambda_b2 ~ normal(0,3);


  alpha ~ normal(alpha_mu, alpha_tau);
  gamma ~ normal(gamma_mu,gamma_tau);
  lambda ~ normal(lambda_mu,lambda_tau);

  nd ~ normal(mu, tau);

}

generated quantities {
  vector[N] nd_new;

  for (n in 1:N){
    nd_new[n] = normal_rng(mu[n], tau);
  }
}
