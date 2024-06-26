# Latent network model creator
tsdlvm1 <- function(
  data, # Dataset
  
  lambda, # May not be missing
  
  # Type:
  contemporaneous = c("cov","chol","prec","ggm"), 
  residual = c("cov","chol","prec","ggm"), 
  
  # Temporal effects:
  beta = "full",
  
  # Contemporaneous effects:
  omega_zeta = "full", # (only lower tri is used) "zero", "full" or kappa structure, array (nvar * nvar * ngroup). NA indicates free, numeric indicates equality constraint, numeric indicates constraint
  delta_zeta = "diag", # If missing, just full for both groups or equal
  kappa_zeta = "full",
  sigma_zeta = "full",
  lowertri_zeta = "full",
  
  # Residual effects:
  omega_epsilon = "zero", # (only lower tri is used) "zero", "full" or kappa structure, array (nvar * nvar * ngroup). NA indicates free, numeric indicates equality constraint, numeric indicates constraint
  delta_epsilon = "diag", # If missing, just full for both groups or equal
  kappa_epsilon = "diag",
  sigma_epsilon = "diag",
  lowertri_epsilon = "diag",
  
  # The rest:
  nu,
  mu_eta,
  
  # Identification:
  identify = TRUE,
  identification = c("loadings","variance"),
  
  # Latents:
  # latents,
  # latents,
  latents,
  
  beepvar,
  dayvar,
  idvar,
  vars, # character indicating the variables Extracted if missing from data - group variable
  groups, # ignored if missing. Can be character indicating groupvar, or vector with names of groups
  covs, # alternative covs (array nvar * nvar * ngroup)
  means, # alternative means (matrix nvar * ngroup)
  nobs, # Alternative if data is missing (length ngroup)
  missing = "listwise",
  equal = "none", # Can also be any of the matrices
  baseline_saturated = TRUE, # Leave to TRUE! Only used to stop recursive calls
  # fitfunctions, # Leave empty
  estimator = "ML",
  optimizer,
  storedata = FALSE,
  sampleStats,
  covtype = c("choose","ML","UB"),
  centerWithin = FALSE,
  standardize = c("none","z","quantile"),
  verbose = FALSE,
  bootstrap = FALSE,
  boot_sub,
  boot_resample
  # bootstrap = FALSE
){
  contemporaneous <- match.arg(contemporaneous)
  residual <- match.arg(residual)
  identification <- match.arg(identification)
  
  # FIXME: Not sure why needed...
  if (missing(vars)) vars2 <- NULL else vars2 <- vars
  if (missing(idvar)) idvar <- NULL
  if (missing(dayvar)) dayvar <- NULL
  if (missing(beepvar)) beepvar <- NULL
  if (missing(groups)) groups <- NULL
  
  # If data is missing with rawts, stop:
  if (!missing(data)){
    data <- as.data.frame(data)
    if (is.null(names(data))){
      names(data) <- paste0("V",seq_len(ncol(data)))
    }
  }
  
  # If data is not missing, make augmented data:
  data <- tsData(data, vars = vars2, beepvar = beepvar, dayvar = dayvar, idvar = idvar, groupvar = groups, centerWithin = centerWithin)
  
  # # Bootstrap the data if needed:
  # if (bootstrap){
  #   browser()
  # }
  
  # Extract var names:
  if (is.null(groups)){
    vars <- colnames(data)  
  } else {
    vars <- colnames(data)[colnames(data)!=groups]
  }
  
  # Obtain sample stats:
  if (missing(sampleStats)){
    sampleStats <- samplestats(data = data, 
                               vars = vars, 
                               groups = groups,
                               covs = covs, 
                               means = means, 
                               nobs = nobs, 
                               missing  = ifelse(estimator == "FIML","pairwise",missing),
                               fimldata = estimator == "FIML",
                               storedata = storedata,
                               covtype=covtype,
                               standardize=standardize,
                               verbose=verbose,
                               weightsmatrix = ifelse(!estimator %in% c("WLS","ULS","DWLS"), "none",
                                                      switch(estimator,
                                                             "WLS" = "full",
                                                             "ULS" = "identity",
                                                             "DWLS" = "diag"
                                                      )),
                               bootstrap=bootstrap,
                               boot_sub = boot_sub,
                               boot_resample = boot_resample)    
  }
  
  
  # Check if number of variables is an even number:
  if ( nrow(sampleStats@variables) %% 2 != 0){
    stop("Number of variables is not an even number: variance-covariance matrix cannot be a Toeplitz matrix. ")
  }
  
  
  # Check some things:
  nNode <- nrow(sampleStats@variables) / 2
  
  nVar <- nNode * 2
  
  # Number of latents:
  nLat <- ncol(lambda)
  
  # Variable names:
  varnames <- vars[(nNode+1):nVar]
  
  # Latent names:
  if (missing(latents)){
    latents <- paste0("Eta_",seq_len(nLat))
  }
  if (length(latents) != nLat){
    stop("Length of 'latents' is not equal to number of latent variables in model.")
  }
  
  # Generate model object:
  model <- generate_psychonetrics(model = "tsdlvm1",
                                  identification = identification,
                                  types = list(zeta = contemporaneous,
                                               epsilon = residual),
                                  sample = sampleStats,computed = FALSE, 
                                  equal = equal,
                                  optimizer =  defaultoptimizer(), estimator = estimator, distribution = "Gaussian",
                                  verbose=verbose)
  
  # Number of groups:
  nGroup <- nrow(model@sample@groups)
  
  # FIXME: Keep this the same for now for rawts = TRUE
  
  # Add number of observations:
  model@sample@nobs <-  
    nVar * (nVar+1) / 2 * nGroup + # Covariances per group
    nVar * nGroup # Means per group
  
  # Model matrices:
  modMatrices <- list()
  
  expMeans1 <- lapply(model@sample@means,'[',1:nNode)
  expMeans2 <- lapply(model@sample@means,'[',(nNode+1):nVar)
  
  # Fix exo means
  modMatrices$exo_means <- matrixsetup_mu(, nNode = nNode, nGroup = nGroup, labels = varnames, equal = "exo_means" %in% equal,
                                          expmeans = expMeans1, sampletable = sampleStats, name = "exo_means")
  
  
  # Fix nu
  modMatrices$nu <- matrixsetup_mu(nu, nNode = nNode, nGroup = nGroup, labels = varnames,equal = "nu" %in% equal,
                                   expmeans = expMeans2, sampletable = sampleStats, name = "nu")
  
  # Fix between-subject means:
  modMatrices$mu_eta <- matrixsetup_mu(mu_eta,nNode = nLat, nGroup = nGroup, labels = latents, equal = "mu_eta" %in% equal,
                                       expmeans = lapply(1:nGroup,function(x)rep(0, nLat)), sampletable = sampleStats, name = "mu_eta")
  
  
  # Exogenous block:
  shiftCovs <- lapply(sampleStats@covs,spectralshift)
  
  # Exogenous block covariances:
  exoCovs <- lapply(shiftCovs,function(x)spectralshift(x[1:nNode,1:nNode]))
  
  # Fix exo cholesky:
  modMatrices$exo_cholesky <- matrixsetup_lowertri("full", 
                                                   name = "exo_cholesky",
                                                   expcov=exoCovs,
                                                   nNode = nNode, 
                                                   nGroup = nGroup, 
                                                   labels = sampleStats@variables$label[1:nNode],
                                                   equal = "exo_cholesky" %in% equal, sampletable = sampleStats)
  
  
  # S1 and S0 estimates:
  S0est <- lapply(shiftCovs,function(x)spectralshift(x[nNode + (1:nNode),nNode + (1:nNode)]))
  S1est <- lapply(shiftCovs,function(x)x[nNode + (1:nNode),1:nNode])
  S0inv <- lapply(S0est,solve_symmetric)
  
  
  # Setup lambda:
  modMatrices$lambda <- matrixsetup_lambda(lambda, expcov=S0est, nGroup = nGroup, observednames = varnames, latentnames = latents,
                                           sampletable = sampleStats, name = "lambda", equal = "lambda" %in% equal)
  
  
  # Quick and dirty sigma_zeta estimate:
  # prior_sig_zeta <- lapply(seq_along(S0est),function(i){
  #   # Let's take a pseudoinverse:
  #   curLam <- matrix(as.vector(modMatrices$lambda$start[,,i,drop=FALSE]),nNode,nLat)
  # 
  #   inv <- corpcor::pseudoinverse(as.matrix(kronecker(curLam,curLam)))
  # 
  #   # And obtain psi estimate:
  #   matrix(inv %*% as.vector(S0est[[i]])/2,nLat,nLat)
  # })
  prior_sig_zeta <- lapply(seq_len(nGroup),function(g){
    modMatrices$lambda$sigma_zeta_start[,,g]
  })
  
  # Setup latent varcov:
  modMatrices <- c(modMatrices,
                   matrixsetup_flexcov(sigma = sigma_zeta,lowertri = lowertri_zeta,omega = omega_zeta,delta = delta_zeta,kappa = kappa_zeta,
                                       type = contemporaneous,
                                       name= "zeta",
                                       sampleStats= sampleStats,
                                       equal = equal,
                                       nNode = nLat,
                                       expCov = prior_sig_zeta,
                                       nGroup = nGroup,
                                       labels = latents
                   ))
  
  # Setup Beta:
  modMatrices$beta <- matrixsetup_beta(beta, 
                                       name = "beta",
                                       nNode = nLat, 
                                       nGroup = nGroup, 
                                       labels = latents,
                                       equal = "beta" %in% equal, sampletable = sampleStats)
  
  
  prior_sig_epsilon <- lapply(seq_len(nGroup),function(g){
    modMatrices$lambda$sigma_epsilon_start[,,g]
  })
  
  # Setup residuals:
  modMatrices <- c(modMatrices,
                   matrixsetup_flexcov(sigma_epsilon,lowertri_epsilon,omega_epsilon,delta_epsilon,kappa_epsilon,
                                       type = residual,
                                       name= "epsilon",
                                       sampleStats= sampleStats,
                                       equal = equal,
                                       nNode = nNode,
                                       expCov = prior_sig_epsilon,
                                       nGroup = nGroup,
                                       labels = varnames
                   ))
  
  # Generate the full parameter table:
  pars <- do.call(generateAllParameterTables, modMatrices)
  
  
  # Store in model:
  model@parameters <- pars$partable
  model@matrices <- pars$mattable
  # 
  #   model@extramatrices <- list(
  #     D =  psychonetrics::duplicationMatrix(nNode*2), # Toeplitz matrix D 
  #     D2 = psychonetrics::duplicationMatrix(nNode), # non-strict duplciation matrix
  #     L = psychonetrics::eliminationMatrix(nNode), # Elinimation matrix
  #     Dstar = psychonetrics::duplicationMatrix(nNode,diag = FALSE), # Strict duplicaton matrix
  #     In = Diagonal(nNode), # Identity of dim n
  #     In2 = Diagonal(nNode), # Identity of dim n^2
  #     A = psychonetrics::diagonalizationMatrix(nNode),
  #     C = as(lavaan::lav_matrix_commutation(nNode,nNode),"sparseMatrix")
  #     # P=P # Permutation matrix
  #   )
  #   
  
  model@extramatrices <- list(
    # Entire duplication matrix needed for likelihood:
    D = psychonetrics::duplicationMatrix(nVar),
    
    # Duplication matrices:
    D_y = psychonetrics::duplicationMatrix(nNode),
    D_eta = psychonetrics::duplicationMatrix(nLat),
    # D_within = psychonetrics::duplicationMatrix(nLat),
    # D_between = psychonetrics::duplicationMatrix(nLat),
    
    # Strict duplication matrices:
    Dstar_y = psychonetrics::duplicationMatrix(nNode,diag = FALSE),
    Dstar_eta = psychonetrics::duplicationMatrix(nLat,diag = FALSE),
    # Dstar_within = psychonetrics::duplicationMatrix(nLat,diag = FALSE),
    # Dstar_between = psychonetrics::duplicationMatrix(nLat,diag = FALSE),  
    
    # Identity matrices:
    I_y = as(diag(nNode),"dMatrix"),
    I_eta = as(diag(nLat),"dMatrix"),
    # I_within = Diagonal(nLat),
    # I_between = Diagonal(nLat),
    
    # Diagonalization matrices:
    A_y = psychonetrics::diagonalizationMatrix(nNode),
    A_eta = psychonetrics::diagonalizationMatrix(nLat),
    # A_within = psychonetrics::diagonalizationMatrix(nLat),
    # A_between = psychonetrics::diagonalizationMatrix(nLat),
    
    # Commutation matrices:
    C_y_y = as(lavaan::lav_matrix_commutation(nNode, nNode),"dMatrix"),
    C_y_eta = as(lavaan::lav_matrix_commutation(nNode, nLat),"dMatrix"),
    C_eta_eta = as(lavaan::lav_matrix_commutation(nLat, nLat),"dMatrix"),
    
    # 
    # C_y_within = as(lavaan::lav_matrix_commutation(nVar, nLat),"sparseMatrix"),
    # C_within_within = as(lavaan::lav_matrix_commutation(nLat, nLat),"sparseMatrix"),
    # C_y_between = as(lavaan::lav_matrix_commutation(nVar, nLat),"sparseMatrix"),
    # C_between_between = as(lavaan::lav_matrix_commutation(nLat, nLat),"sparseMatrix"),
    # 
    # Elimination matrices:
    L_y = psychonetrics::eliminationMatrix(nNode),
    L_eta = psychonetrics::eliminationMatrix(nLat)
  )
  
  # Come up with P...
  # Dummy matrix to contain indices:
  dummySigma <- matrix(0,nNode*2,nNode*2)
  smallMat <- matrix(0,nNode,nNode)
  dummySigma[1:nNode,1:nNode][lower.tri(smallMat,diag=TRUE)] <- seq_len(nNode*(nNode+1)/2)
  dummySigma[nNode + (1:nNode),nNode + (1:nNode)][lower.tri(smallMat,diag=TRUE)] <- max(dummySigma) + seq_len(nNode*(nNode+1)/2)
  dummySigma[nNode + (1:nNode),1:nNode] <- max(dummySigma) + seq_len(nNode^2)
  inds <- dummySigma[lower.tri(dummySigma,diag=TRUE)]
  
  # P matrix:
  # P <- bdiag(Diagonal(nNode*2),sparseMatrix(j=seq_along(inds),i=inds))
  model@extramatrices$P <- bdiag(Diagonal(nNode*2),sparseMatrix(j=seq_along(inds),i=order(inds)))
  model@extramatrices$P  <- as(as.matrix(model@extramatrices$P), "dMatrix")
  
  # Form the model matrices
  model@modelmatrices <- formModelMatrices(model)
  
  
  ### Baseline model ###
  if (baseline_saturated){
    
    # Baseline GGM should be block matrix:
    basGGM <- diag(nNode*2)
    basGGM[1:nNode,1:nNode] <- 1
    
    model@baseline_saturated$baseline <- cholesky(data = data,
                                                  lowertri = basGGM,
                                                  vars = vars,
                                                  groups = groups,
                                                  covs = covs,
                                                  means = means,
                                                  nobs = nobs,
                                                  missing = missing,
                                                  equal = equal,
                                                  estimator = estimator,
                                                  baseline_saturated = FALSE,
                                                  sampleStats = sampleStats)
    
    # Add model:
    # model@baseline_saturated$baseline@fitfunctions$extramatrices$M <- Mmatrix(model@baseline_saturated$baseline@parameters)
    ### Saturated model ###
    model@baseline_saturated$saturated <- cholesky(data = data, 
                                                   lowertri = "full", 
                                                   vars = vars,
                                                   groups = groups,
                                                   covs = covs,
                                                   means = means,
                                                   nobs = nobs,
                                                   missing = missing,
                                                   equal = equal,
                                                   estimator = estimator,
                                                   baseline_saturated = FALSE,
                                                   sampleStats = sampleStats)
    
    # if not FIML, Treat as computed:
    if (estimator != "FIML"){
      model@baseline_saturated$saturated@computed <- TRUE
      
      # FIXME: TODO
      model@baseline_saturated$saturated@objective <- psychonetrics_fitfunction(parVector(model@baseline_saturated$saturated),model@baseline_saturated$saturated)      
    }
    
  }
  
  # Identify model:
  if (identify){
    model <- identify(model)
  }
  
  if (missing(optimizer)){
    model <- setoptimizer(model, "default")
  } else {
    model <- setoptimizer(model, optimizer)
  }
  
  # Return model:
  return(model)
}
