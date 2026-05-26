# Subtyping evaluation template — sourced by a job script with `params` set.
# params: clusters_path, survival_path, empirical (logical),
#         n_permutations (integer), eval_json
#
# Ports the prognostic evaluation from the DSCC repo (GetCoxPv.R /
# GetEmpPv.R): a Cox proportional-hazards score-test p-value and an
# optional empirical log-rank p-value via subtype-label permutation.

suppressMessages({ suppressWarnings({
  library(survival)
}) })

ts <- function() format(Sys.time(), "[%H:%M:%S]")

resolve_survival <- function(path) {
  sdf <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  time_aliases  <- c("os", "OS", "time", "os_time", "survival", "OS.time")
  event_aliases <- c("isDead", "OSstatus", "status", "event", "vital_status")
  tcol <- intersect(time_aliases, colnames(sdf))[1]
  ecol <- intersect(event_aliases, colnames(sdf))[1]
  samp <- if ("sample" %in% colnames(sdf)) as.character(sdf$sample) else as.character(sdf[[1]])
  data.frame(os = as.numeric(sdf[[tcol]]),
             isDead = as.numeric(sdf[[ecol]]),
             row.names = samp)
}

cl <- read.csv(params$clusters_path, stringsAsFactors = FALSE,
               check.names = FALSE)
samp_col <- if ("sample" %in% colnames(cl)) "sample" else colnames(cl)[1]
cluster <- cl$cluster
names(cluster) <- as.character(cl[[samp_col]])

surv <- resolve_survival(params$survival_path)
common <- intersect(names(cluster), rownames(surv))
cat(sprintf("%s Evaluating %d shared samples\n", ts(), length(common)))

if (length(common) < 2L || length(unique(cluster[common])) < 2L) {
  stop("Need at least 2 shared samples spanning at least 2 subtypes to evaluate.")
}

sdat <- surv[common, , drop = FALSE]
grp <- as.factor(cluster[common])
n_events <- sum(sdat$isDead == 1, na.rm = TRUE)

cox_pvalue <- NA_real_
fit <- try(summary(coxph(Surv(time = os, event = isDead) ~ grp,
                         data = sdat, ties = "exact")), silent = TRUE)
if (!inherits(fit, "try-error")) {
  cox_pvalue <- unname(fit$sctest[3])
}

logrank <- try(survdiff(Surv(time = os, event = isDead) ~ grp, data = sdat),
               silent = TRUE)
logrank_pvalue <- NA_real_
obs_stat <- NA_real_
if (!inherits(logrank, "try-error")) {
  obs_stat <- unname(logrank$chisq)
  logrank_pvalue <- 1 - pchisq(obs_stat, length(logrank$n) - 1)
}

result <- list(
  cox_pvalue     = cox_pvalue,
  logrank_pvalue = logrank_pvalue,
  n_clusters     = length(unique(cluster[common])),
  n_samples      = length(common),
  n_events       = as.integer(n_events)
)

if (isTRUE(params$empirical) && !is.na(obs_stat)) {
  n_perm <- as.integer(params$n_permutations)
  cat(sprintf("%s Running %d permutations for empirical log-rank p-value\n",
              ts(), n_perm))
  cl_names <- names(cluster)
  perm_stats <- vapply(seq_len(n_perm), function(i) {
    set.seed(i)
    cluster_perm <- cluster
    names(cluster_perm) <- cl_names[sample(seq_along(cluster))]
    lr <- try(survdiff(Surv(time = os, event = isDead) ~
                         as.factor(cluster_perm[common]), data = sdat),
              silent = TRUE)
    if (inherits(lr, "try-error")) return(-Inf)
    unname(lr$chisq)
  }, numeric(1L))
  result$empirical_pvalue <- sum(perm_stats >= obs_stat) / length(perm_stats)
  result$n_permutations   <- n_perm
}

jsonlite::write_json(result, params$eval_json, auto_unbox = TRUE)
cat(sprintf("%s Evaluation complete: cox=%s logrank=%s%s\n", ts(),
            format(cox_pvalue), format(logrank_pvalue),
            if (!is.null(result$empirical_pvalue))
              paste0(" empirical=", format(result$empirical_pvalue)) else ""))
