#ifndef ML_LVM_IMPLIED_H
#define ML_LVM_IMPLIED_H

#include <RcppArmadillo.h>
#include <math.h>
#include <vector>
#include <pbv.h>
#include <cmath>

// [[Rcpp::depends(RcppArmadillo)]]
using namespace Rcpp;
using namespace arma;

Rcpp::List implied_ml_lvm_cpp(
    const S4& model,
    bool all = false
);

#endif
