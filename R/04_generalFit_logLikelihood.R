# General log-likelihood!
psychonetrics_logLikelihood <- function(model){
  # What distribution to use:
  distribution <- model@distribution
  
  # Prepare model:
  prep <- prepareModel(parVector(model), model)
  
  
  # Obtain log likelihood:
  loglikFun <- switch(
    distribution,
    "Gaussian" = logLikelihood_gaussian,
    "Ising" = logLikelihood_Ising
  )
  
  # Run and return:
  loglikFun(prep)
}