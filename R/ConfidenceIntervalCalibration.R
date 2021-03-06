# @file ConfidenceIntervalCalibration.R
#
# Copyright 2018 Observational Health Data Sciences and Informatics
#
# This file is part of EmpiricalCalibration
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' Fit a systematic error model
#'
#' @details
#' Fit a model of the systematic error as a function of true effect size. This model is an extension
#' of the method for fitting the null distribution. The mean and log(standard deviations) of the error
#' distributions are assumed to be linear with respect to the true effect size, and each component is
#' therefore represented by an intercept and a slope.
#'
#' @param logRr                      A numeric vector of effect estimates on the log scale.
#' @param seLogRr                    The standard error of the log of the effect estimates. Hint: often
#'                                   the standard error = (log(<lower bound 95 percent confidence
#'                                   interval>) - log(<effect estimate>))/qnorm(0.025).
#' @param estimateCovarianceMatrix   should a covariance matrix be computed? If so, confidence
#'                                   intervals for the model parameters will be available.
#' @param trueLogRr                  A vector of the true effect sizes.
#'
#' @return
#' An object of type \code{systematicErrorModel}.
#'
#' @examples
#' controls <- simulateControls(n = 50 * 3, mean = 0.25, sd = 0.25, trueLogRr = log(c(1, 2, 4)))
#' model <- fitSystematicErrorModel(controls$logRr, controls$seLogRr, controls$trueLogRr)
#' model
#'
#' @export
fitSystematicErrorModel <- function(logRr, seLogRr, trueLogRr, estimateCovarianceMatrix = TRUE) {
  if (any(is.infinite(seLogRr))) {
    warning("Estimate(s) with infinite standard error detected. Removing before fitting error model")
    trueLogRr <- trueLogRr[!is.infinite(seLogRr)]
    logRr <- logRr[!is.infinite(seLogRr)]
    seLogRr <- seLogRr[!is.infinite(seLogRr)]
  }
  if (any(is.infinite(logRr))) {
    warning("Estimate(s) with infinite logRr detected. Removing before fitting error model")
    trueLogRr <- trueLogRr[!is.infinite(logRr)]
    seLogRr <- seLogRr[!is.infinite(logRr)]
    logRr <- logRr[!is.infinite(logRr)]
  }
  if (any(is.na(seLogRr))) {
    warning("Estimate(s) with NA standard error detected. Removing before fitting error model")
    trueLogRr <- trueLogRr[!is.na(seLogRr)]
    logRr <- logRr[!is.na(seLogRr)]
    seLogRr <- seLogRr[!is.na(seLogRr)]
  }
  if (any(is.na(logRr))) {
    warning("Estimate(s) with NA logRr detected. Removing before fitting error model")
    trueLogRr <- trueLogRr[!is.na(logRr)]
    seLogRr <- seLogRr[!is.na(logRr)]
    logRr <- logRr[!is.na(logRr)]
  }
  
  gaussianProduct <- function(mu1, mu2, sd1, sd2) {
    (2 * pi)^(-1/2) * (sd1^2 + sd2^2)^(-1/2) * exp(-(mu1 - mu2)^2/(2 * (sd1^2 + sd2^2)))
  }
  
  LL <- function(theta, logRr, seLogRr, trueLogRr) {
    result <- 0
    for (i in 1:length(logRr)) {
      mean <- theta[1] + theta[2] * trueLogRr[i]
      sd <- exp(theta[3] + theta[4] * trueLogRr[i])
      result <- result - log(gaussianProduct(logRr[i], mean, seLogRr[i], sd))
    }
    if (is.infinite(result))
      result <- 99999
    result
  }
  theta <- c(0, 1, -2, 0)
  fit <- optim(theta,
               LL,
               logRr = logRr,
               seLogRr = seLogRr,
               trueLogRr = trueLogRr,
               method = "BFGS",
               hessian = TRUE,
               control = list(parscale = c(1, 1, 10, 10)))
  model <- fit$par
  names(model) <- c("meanIntercept", "meanSlope", "logSdIntercept", "logSdSlope")
  if (estimateCovarianceMatrix) {
    fisher_info <- solve(fit$hessian)
    prop_sigma <- sqrt(diag(fisher_info))
    attr(model, "CovarianceMatrix") <- fisher_info
    attr(model, "LB95CI") <- fit$par + qnorm(0.025) * prop_sigma
    attr(model, "UB95CI") <- fit$par + qnorm(0.975) * prop_sigma
  }
  class(model) <- "systematicErrorModel"
  model
}

#' Calibrate confidence intervals
#'
#' @details
#' Compute calibrated confidence intervals based on a model of the systematic error.
#'
#' @param logRr     A numeric vector of effect estimates on the log scale.
#' @param seLogRr   The standard error of the log of the effect estimates. Hint: often the standard
#'                  error = (log(<lower bound 95 percent confidence interval>) - log(<effect
#'                  estimate>))/qnorm(0.025).
#' @param ciWidth   The width of the confidence interval. Typically this would be .95, for the 95
#'                  percent confidence interval.
#' @param model     An object of type \code{systematicErrorModel} as created by the
#'                  \code{\link{fitSystematicErrorModel}} function.
#'
#' @return
#' A data frame with calibrated confidence intervals and point estimates.
#'
#' @examples
#' data <- simulateControls(n = 50 * 3, mean = 0.25, sd = 0.25, trueLogRr = log(c(1, 2, 4)))
#' model <- fitSystematicErrorModel(data$logRr, data$seLogRr, data$trueLogRr)
#' newData <- simulateControls(n = 15, mean = 0.25, sd = 0.25, trueLogRr = log(c(1, 2, 4)))
#' result <- calibrateConfidenceInterval(newData$logRr, newData$seLogRr, model)
#' result
#'
#' @export
calibrateConfidenceInterval <- function(logRr, seLogRr, model, ciWidth = 0.95) {
  
  opt <- function(x,
                  z,
                  logRr,
                  se,
                  interceptMean,
                  slopeMean,
                  interceptLogSd,
                  slopeLogSd) {
    mean <- interceptMean + slopeMean * x
    sd <- exp(interceptLogSd + slopeLogSd * x)
    numerator <- mean - logRr
    denominator <- sqrt((sd)^2 + (se)^2)
    if (is.infinite(denominator)) {
      if (numerator > 0)
        return(z + 1e-10)
      else
        return(z - 1e-10)
    }
    return(z + numerator/denominator)
  }
  
  logBound <- function(ciWidth,
                       lb = TRUE,
                       logRr,
                       se,
                       interceptMean,
                       slopeMean,
                       interceptLogSd,
                       slopeLogSd) {
    z <- qnorm((1 - ciWidth)/2)
    if (lb) {
      z <- -z
    }
    # Simple grid search for upper bound where opt is still positive:
    if (slopeLogSd > 0) {
      lower <- -100
      upper <- lower
      while(opt(x = upper,
                z = z,
                logRr = logRr,
                se = se,
                interceptMean = interceptMean,
                slopeMean = slopeMean,
                interceptLogSd = interceptLogSd,
                slopeLogSd = slopeLogSd) < 0 && upper < 100) {
        upper <- upper + 1
      }
      if (upper == lower | upper == 100) {
        return(NA)
      } 
    } else {
      upper <- 100
      lower <- upper
      while(opt(x = lower,
                z = z,
                logRr = logRr,
                se = se,
                interceptMean = interceptMean,
                slopeMean = slopeMean,
                interceptLogSd = interceptLogSd,
                slopeLogSd = slopeLogSd) > 0 && lower > -100) {
        lower <- lower - 1
      }
      if (upper == lower | lower == -100) {
        return(NA)
      }  
    }
    return(uniroot(f = opt,
                   interval = c(lower, upper),
                   z = z,
                   logRr = logRr,
                   se = se,
                   interceptMean = interceptMean,
                   slopeMean = slopeMean,
                   interceptLogSd = interceptLogSd,
                   slopeLogSd = slopeLogSd)$root)
  }
  
  result <- data.frame(logRr = rep(0, length(logRr)), logLb95Rr = 0, logUb95Rr = 0)
  for (i in 1:nrow(result)) {
    if (is.infinite(logRr[i]) || is.na(logRr[i]) || is.infinite(seLogRr[i]) || is.na(seLogRr[i])) {
      result$logRr[i] <- NA
      result$logLb95Rr[i] <- NA
      result$logUb95Rr[i] <- NA
    } else {
      result$logRr[i] <- logBound(0,
                                  TRUE,
                                  logRr[i],
                                  seLogRr[i],
                                  model[1],
                                  model[2],
                                  model[3],
                                  model[4])
      result$logLb95Rr[i] <- logBound(ciWidth,
                                      TRUE,
                                      logRr[i],
                                      seLogRr[i],
                                      model[1],
                                      model[2],
                                      model[3],
                                      model[4])
      result$logUb95Rr[i] <- logBound(ciWidth,
                                      FALSE,
                                      logRr[i],
                                      seLogRr[i],
                                      model[1],
                                      model[2],
                                      model[3],
                                      model[4])
    }
  }
  result$seLogRr <- (result$logLb95Rr - result$logUb95Rr)/(2 * qnorm((1 - ciWidth)/2))
  return(result)
}

#' Compute the (traditional) confidence interval
#'
#' @description
#' \code{computeTraditionalCi} computes the traditional confidence interval based on the log of the
#' relative risk and the standerd error of the log of the relative risk.
#'
#' @param logRr     A numeric vector of one or more effect estimates on the log scale
#' @param seLogRr   The standard error of the log of the effect estimates. Hint: often the standard
#'                  error = (log(<lower bound 95 percent confidence interval>) - log(<effect
#'                  estimate>))/qnorm(0.025)
#' @param ciWidth   The width of the confidence interval. Typically this would be .95, for the 95
#'                  percent confidence interval.
#'
#' @return
#' The point estimate and confidence interval
#'
#' @examples
#' data(sccs)
#' positive <- sccs[sccs$groundTruth == 1, ]
#' computeTraditionalCi(positive$logRr, positive$seLogRr)
#'
#' @export
computeTraditionalCi <- function(logRr, seLogRr, ciWidth = .95) {
  return(c(rr = exp(logRr), 
           lb = exp(logRr - qnorm(1  -ciWidth/2)*seLogRr), 
           ub = exp(logRr + qnorm(1 - ciWidth/2)*seLogRr)))
}
