matrixsetup_lambda <- function(
    lambda, # lambda argument
    nGroup, # Number of groups
    expcov, # Expected covariance matrices (list).
    observednames, latentnames,
    equal = FALSE,
    sampletable,
    name = "lambda",
    start,
    identification = c("loadings","variance"),
    simple = FALSE
){
  identification <- match.arg(identification)
  
  # Fix lambda:
  lambda <- fixMatrix(lambda,nGroup,equal)
  
  nLat <- ncol(lambda)
  nObs <- nrow(lambda)
  
  # For each group, form starting values:
  if (missing(start)){
    
    lambdaStart <- lambda
    sigma_epsilon_start <- array(0, dim = c(nObs, nObs, nGroup))
    sigma_zeta_start <- array(0, dim = c(nLat, nLat, nGroup))
    
    for (g in 1:nGroup){
      
      # Current cov estimate:
      curcov <- as.matrix(spectralshift(expcov[[g]]))
      if (nObs == nLat){
        
        
        # Equal number of observations and latents (likely no measurement error modeled):
        simple <- FALSE
        
        # Sigma_zeta start:
        sigma_zeta_start[,,g] <- curcov
        
        # Identity matrix:
        lambdaStart[,,g] <- lambda[,,g] <- diag(nObs)
        
        # If variance identification, I need to rescale ...
        if (identification == "variance"){
          # Obtain SDs:
          S <- diag(sqrt(diag(sigma_zeta_start[,,g])))
          
          # Standardize sigma_zeta:
          sigma_zeta_start[,,g] <- cov2cor(sigma_zeta_start[,,g])
          
          # Rescale lambda:
          lambdaStart[,,g] <- lambda[,,g] <-  lambda[,,g] %*% S
        }
        
      } else if (!(nObs > 3 && nObs >= nLat) || simple){
        simple <- TRUE
      } else {
        simple <- FALSE
        
        tryres <- try({
          # Residual and latent varcov:
          suppressMessages(suppressWarnings(
            fa <- psych::fa(r = curcov, nfactors = nLat, rotate = "promax", covar = TRUE, smooth = FALSE, warnings = FALSE)
          ))
          
          # Sigma_epsilon start:
          sigma_epsilon_start[,,g] <- diag(fa$uniquenesses)
          
          load <- fa$loadings
          
  
          # Correlation between factor loadings:
          # Generate 100 different permutations and choose the best:
          if (nLat > 1){
            
            
            ### FIXME: OLD CODE FROM VERSION 0.10 ###
            # perms <- combinat::permn(1:nLat)
            # # fit <- sapply(perms, function(x)sum(diag(stats::cor(abs(load[,x]), lambda[,,g]))))
            # fit <- sapply(perms, function(x)sum(abs(load)[,x] * (lambda[,,g]!=0)))
            # best <- perms[[which.max(fit)]]        
            
            ### FIXME: NEW CODE (CHECK):
            # REMOVED IN VERSION 0.12, make simpler#
            # corFL_LY <- cor(lambda[,,g] + rnorm(prod(dim(lambda[,,g])),0,0.0001), load)
            # 
            # 
            # best_per_lat <- apply(corFL_LY, 1, order, decreasing=TRUE)
            # 
            # # FIXME: Not optimal, but put all duplicated factors to second choice (better is to do optimisation algoritm)
            # row <- 1
            # 
            # while (any(duplicated(best_per_lat[1,]))){
            #   row <- row + 1
            #   if (row > nrow(best_per_lat)){
            #     warning("No proper starting values found for lambda, using simple starting values.")
            #     simple <- TRUE
            #     break
            #   } 
            #   best_per_lat[1,duplicated(best_per_lat[1,])] <- best_per_lat[row,duplicated(best_per_lat[1,])]
            # }
            # 
            # 
            # 
            # best <- best_per_lat[1,]
            
            ### FIXME: NEWER NEW CODE:
            # Simply pick the factor with strongest loadings for each latent variable:
            best <- numeric(nLat)
            
            for (l in seq_len(nLat)){
              best[l] <- which.max(colSums(abs(lambda[,l,g] * load)))
            }
            
            
          } else {
            best <- 1
          }
          
          sigma_zeta_start[,,g] <- fa$r.scores[best,best]
          
          # If there are duplicated latents here, reduce the covariances by 20%:
          if (any(duplicated(best))){
            doubles <- duplicated(best)|rev(duplicated(rev(best)))
            doublesmat <- outer(doubles,doubles,"==")
            diag(doublesmat) <- FALSE
            sigma_zeta_start[,,g][doublesmat] <- sigma_zeta_start[,,g][doublesmat] * 0.8
          }
          
          # Force positive definite:
          sigma_zeta_start[,,g] <- spectralshift(sigma_zeta_start[,,g])
          
          
          lambdaStart[,,g] <- lambda[,,g] * load[,best]
          
          # Fix potentially low  and high factor loadings:
          ind <- abs(lambdaStart[,,g]) < 0.25 & abs(lambdaStart[,,g]) > 0
          lambdaStart[,,g][ind] <- sign(lambdaStart[,,g][ind]) * 0.25
          
          ind <- abs(lambdaStart[,,g]) > 2 & abs(lambdaStart[,,g]) > 0
          lambdaStart[,,g][ind] <- sign(lambdaStart[,,g][ind]) * 2
          
          # If loadings identification, I need to rescale ...
          if (identification == "loadings"){
            scaleMat <- matrix(0, nLat, nLat)
            for (i in 1:nLat){
              scaleMat[i,i] <- 1/lambdaStart[,,g,drop=FALSE][,i,1][lambdaStart[,,g,drop=FALSE][,i,1]!=0][1]
            }
            
            lambdaStart[,,g] <- lambdaStart[,,g] %*% scaleMat
            sigma_zeta_start[,,g] <- solve(scaleMat) %*% sigma_zeta_start[,,g] %*% solve(scaleMat)
          }
        })
        if (is (tryres, "try-error")) simple <- TRUE
      }

      if (simple){
        sigma_epsilon_start[,,g] <- diag(nObs)
        sigma_zeta_start[,,g] <- diag(nLat)
        lambdaStart[,,g] <- lambda[,,g]
      }
      
    }
  } else {
    lambdaStart <- lambda
    for (g in seq_along(start)){
      lambdaStart[,,g] <- (lambda[,,g]!=0) * start[[g]]
    }
  }
  
  # 
  #     # For all laodings:
  #     for (f in seq_len(ncol(lambdaStart))){
  #       # # First principal component of sub cov:
  #       # if (any(lambda[,f,g]!=0)){
  #       #   ev1 <- eigen(curcov[lambda[,f,g]!=0,lambda[,f,g]!=0])$vectors[,1]
  #       #   lambdaStart[lambdaStart[,f,g]!=0,f,g] <- ev1 / ev1[1]        
  #       # } 
  #       # Univariate factor model:
  #       if (any(lambda[,f,g]!=0)){
  #         fa <- psych::fa(r = curcov[lambda[,f,g]!=0,lambda[,f,g]!=0], factors = 1, covar = TRUE)
  #         load1 <- fa$loadings[,1]
  #         
  #         if (identification == "loadings"){
  #           lambdaStart[lambdaStart[,f,g]!=0,f,g] <- load1 / abs(load1[1])
  #         } else {
  #           lambdaStart[lambdaStart[,f,g]!=0,f,g] <- load1
  #         }
  #         
  #         # thetaStart[lambdaStart[,f,g]!=0,lambdaStart[,f,g]!=0, g] <- pmin(thetaStart[lambdaStart[,f,g]!=0,lambdaStart[,f,g]!=0, g] , fa$uniquenesses)
  #         
  #       }
  #     }
  #     
  #  
  #     # Now finally:
  #     # This means that the factor-part is expected to be:
  #     factorPart <- curcov - sigma_epsilon_start[,,g]
  #     
  #     # Let's take a pseudoinverse:
  #     inv <- corpcor::pseudoinverse(kronecker(lambdaStart[,,g],lambdaStart[,,g]))
  #     
  #     # And obtain psi estimate:
  #     sigma_zeta_start[,,g] <- matrix(inv %*% as.vector(factorPart),nLat,nLat)
  
  
  # Form the model matrix part:
  retlist <- list(lambda,
                  mat = name,
                  op =  "~=",
                  rownames = observednames,
                  colnames = latentnames,
                  sparse = TRUE,
                  start = lambdaStart,
                  # sigma_epsilon_start = sigma_epsilon_start,
                  # sigma_zeta_start = sigma_zeta_start,
                  sampletable=sampletable
  )
  
  if (missing(start)){
    retlist$sigma_epsilon_start <- sigma_epsilon_start
    retlist$sigma_zeta_start <- sigma_zeta_start
  }
  
  return(retlist)
}