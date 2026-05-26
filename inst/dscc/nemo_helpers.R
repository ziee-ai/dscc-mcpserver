## Vendored from the NEMO package (Shamir-Lab/NEMO), R/NEMO.R.
## https://github.com/Shamir-Lab/NEMO  (Rappoport & Shamir, 2019).
##
## Only `nemo.num.clusters` is vendored — it is the single NEMO function
## that DSCC's runDSCC() depends on, and it uses base R only (no NEMO
## package install required). Sourced by the subprocess templates before
## DSCC_helper.R. Kept faithful to the upstream implementation.

#' Estimate the number of clusters in an affinity graph (NEMO).
#' @param W the affinity graph.
#' @param NUMC candidate cluster counts (default 2:15).
#' @return the estimated number of clusters.
nemo.num.clusters <- function(W, NUMC = 2:15) {
  if (min(NUMC) == 1) {
    warning("Note that we always assume there are more than one cluster.")
    NUMC = NUMC[NUMC > 1]
  }
  W = (W + t(W)) / 2
  diag(W) = 0
  if (length(NUMC) > 0) {
    degs = rowSums(W)
    degs[degs == 0] = .Machine$double.eps
    D = diag(degs)
    L = D - W
    Di = diag(1 / sqrt(degs))
    L = Di %*% L %*% Di
    eigs = eigen(L)
    eigs_order = sort(eigs$values, index.return = T)$ix
    eigs$values = eigs$values[eigs_order]
    eigs$vectors = eigs$vectors[, eigs_order]
    eigengap = abs(diff(eigs$values))
    eigengap = (1:length(eigengap)) * eigengap

    t1 <- sort(eigengap[NUMC], decreasing = TRUE, index.return = T)$ix
    return(NUMC[t1[1]])
  }
}
