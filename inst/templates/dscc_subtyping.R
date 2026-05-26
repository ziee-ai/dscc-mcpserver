# DSCC subtyping template — sourced by a job script with `params` already set
# (parsed with simplifyVector = FALSE).
# params: omics_paths (list of CSV paths, features x samples),
#         omics_names (list), max_clusters, survival_path (or NULL),
#         clusters_csv, clusters_rds, cox_json, nemo_src, dscc_src

suppressMessages({ suppressWarnings({
  if (requireNamespace("RhpcBLASctl", quietly = TRUE)) {
    RhpcBLASctl::blas_set_num_threads(1)
    RhpcBLASctl::omp_set_num_threads(1)
  }
  library(magrittr)
  library(matrixStats)
  library(SNFtool)
  library(igraph)
  library(cluster)
}) })

ts <- function() format(Sys.time(), "[%H:%M:%S]")

# Vendored scientific code: nemo.num.clusters + runDSCC and its helpers.
source(params$nemo_src)
source(params$dscc_src)

omics_paths <- unlist(params$omics_paths)
omics_names <- unlist(params$omics_names)
if (length(omics_names) != length(omics_paths)) {
  omics_names <- sprintf("omics_%d", seq_along(omics_paths))
}
max_clusters <- as.integer(params$max_clusters)

cat(sprintf("%s Loading %d omics layer(s)\n", ts(), length(omics_paths)))

dataList <- list()
for (i in seq_along(omics_paths)) {
  # features x samples -> transpose to samples x features.
  df <- as.matrix(read.csv(omics_paths[[i]], row.names = 1L, check.names = FALSE))
  mat <- t(df)
  storage.mode(mat) <- "numeric"
  mat[is.na(mat)] <- 0
  if (min(mat) >= 0 && max(mat) > 100) {
    mat <- log2(mat + 1)
  }
  dataList[[omics_names[[i]]]] <- mat
  cat(sprintf("%s   %s: %d samples x %d features\n",
              ts(), omics_names[[i]], nrow(mat), ncol(mat)))
}

all_samples <- unique(unlist(lapply(dataList, rownames)))
cat(sprintf("%s Running DSCC on %d samples (max_clusters = %d)\n",
            ts(), length(all_samples), max_clusters))

cluster <- runDSCC(dataList = dataList,
                   nSamples = length(all_samples),
                   defk = max_clusters)
cluster <- cluster[order(names(cluster))]

clusters_df <- data.frame(sample = names(cluster),
                          cluster = as.integer(cluster),
                          stringsAsFactors = FALSE)
utils::write.csv(clusters_df, params$clusters_csv, row.names = FALSE)
saveRDS(cluster, params$clusters_rds)
cat(sprintf("%s Wrote %d sample assignments across %d subtypes\n",
            ts(), nrow(clusters_df), length(unique(clusters_df$cluster))))

# Optional inline Cox evaluation when a survival table is supplied.
if (!is.null(params$survival_path)) {
  ok <- requireNamespace("survival", quietly = TRUE)
  if (!ok) {
    cat(sprintf("%s survival package not available; skipping Cox p-value\n", ts()))
  } else {
    sdf <- read.csv(params$survival_path, stringsAsFactors = FALSE,
                    check.names = FALSE)
    time_aliases  <- c("os", "OS", "time", "os_time", "survival", "OS.time")
    event_aliases <- c("isDead", "OSstatus", "status", "event", "vital_status")
    tcol <- intersect(time_aliases, colnames(sdf))[1]
    ecol <- intersect(event_aliases, colnames(sdf))[1]
    samp <- if ("sample" %in% colnames(sdf)) as.character(sdf$sample) else as.character(sdf[[1]])
    surv <- data.frame(os = as.numeric(sdf[[tcol]]),
                       isDead = as.numeric(sdf[[ecol]]),
                       row.names = samp)
    common <- intersect(names(cluster), rownames(surv))
    cox_pvalue <- NA_real_
    if (length(common) >= 2L && length(unique(cluster[common])) >= 2L) {
      fit <- try(summary(survival::coxph(
        survival::Surv(time = os, event = isDead) ~ as.factor(cluster[common]),
        data = surv[common, , drop = FALSE], ties = "exact")), silent = TRUE)
      if (!inherits(fit, "try-error")) {
        cox_pvalue <- unname(fit$sctest[3])
      }
    }
    jsonlite::write_json(list(cox_pvalue = cox_pvalue,
                              n_evaluated = length(common)),
                         params$cox_json, auto_unbox = TRUE)
    cat(sprintf("%s Cox p-value: %s (n = %d)\n",
                ts(), format(cox_pvalue), length(common)))
  }
}
cat(sprintf("%s DSCC subtyping complete\n", ts()))
