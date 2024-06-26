# Simple wrapper around lvm
bifactor <- function(data, lambda, latents,  bifactor = "g", ...){
  if (missing (lambda)){
    stop("lambda argument may not be missing")
  }
  
  # Number of latents:
  nLatent <- ncol(lambda)
  
  
  # If latents is not provided, make it:
  if (missing(latents)){
    latents <- paste0("Eta_",seq_len(nLatent))
  }
  if (length(latents) != nLatent){
    stop("Length of 'latents' is not equal to number of latent variables in model.")
  }
  
  # Augment lambda:
  lambda <- cbind(lambda,1)
  
  latents <- c(latents, bifactor)
  
  # Return model:
  mod <- lvm(data, lambda = lambda,  latents=latents, ...,
      sigma_zeta = "diag", #
      kappa_zeta = "diag", # Precision
      omega_zeta = "zero", # Partial correlations
      lowertri_zeta = "diag", # Cholesky
      delta_zeta = "diag")
  
  # FIXME: Bad starting values
  # Adjust factor loading start values:
  ind <- mod@parameters$matrix == "lambda" & !mod@parameters$fixed
  mod@parameters$est[ind] <- rnorm(sum(ind),0,0.01) # 0.05 * sign(mod@parameters$est[ind])
  
  # Adjust other start values:
  ind <- mod@parameters$matrix != "lambda" &mod@parameters$matrix != "nu" & !mod@parameters$fixed & mod@parameters$row != mod@parameters$col
  mod@parameters$est[ind] <-  rnorm(sum(ind),0,0.01) #0.05 * sign(mod@parameters$est[ind])
  ind <- mod@parameters$matrix != "lambda" &mod@parameters$matrix != "nu" & !mod@parameters$fixed & mod@parameters$row == mod@parameters$col
  mod@parameters$est[ind] <- 0.5 #* sign(mod@parameters$est[ind])
  
  
  # Return:
  mod
}