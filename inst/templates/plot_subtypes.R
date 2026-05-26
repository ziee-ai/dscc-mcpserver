# Subtype plotting template — sourced by a job script with `params` set.
# params: clusters_path, survival_path (or NULL), omics_paths (list,
#         possibly empty), plot_type ("kaplan_meier" | "silhouette"),
#         png_path

ts <- function() format(Sys.time(), "[%H:%M:%S]")

cl <- read.csv(params$clusters_path, stringsAsFactors = FALSE,
               check.names = FALSE)
samp_col <- if ("sample" %in% colnames(cl)) "sample" else colnames(cl)[1]
cluster <- cl$cluster
names(cluster) <- as.character(cl[[samp_col]])
levs <- sort(unique(cluster))
palette_cols <- grDevices::hcl.colors(max(length(levs), 2L), palette = "Dark 3")

if (identical(params$plot_type, "kaplan_meier")) {
  suppressMessages(suppressWarnings(library(survival)))

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
  if (length(common) < 2L) stop("Not enough shared samples for a survival plot.")
  sdat <- surv[common, , drop = FALSE]
  grp <- factor(cluster[common], levels = levs)

  fit <- survfit(Surv(time = os, event = isDead) ~ grp, data = sdat)
  grDevices::png(params$png_path, width = 1000, height = 760, res = 130)
  on.exit(grDevices::dev.off(), add = TRUE)
  plot(fit, col = palette_cols[seq_along(levs)], lwd = 2, lty = 1,
       xlab = "Time", ylab = "Survival probability",
       main = "Kaplan-Meier survival by DSCC subtype")
  legend("topright", legend = paste("Subtype", levs),
         col = palette_cols[seq_along(levs)], lwd = 2, bty = "n")
  cat(sprintf("%s Wrote Kaplan-Meier plot (%d subtypes, %d samples)\n",
              ts(), length(levs), length(common)))

} else if (identical(params$plot_type, "silhouette")) {
  suppressMessages(suppressWarnings(library(cluster)))

  omics_paths <- unlist(params$omics_paths)
  if (length(omics_paths) < 1L) stop("silhouette requires at least one omics layer.")

  mats <- lapply(omics_paths, function(p) {
    df <- as.matrix(read.csv(p, row.names = 1L, check.names = FALSE))
    m <- t(df)                      # samples x features
    storage.mode(m) <- "numeric"
    m[is.na(m)] <- 0
    if (min(m) >= 0 && max(m) > 100) m <- log2(m + 1)
    m
  })
  common <- Reduce(intersect, lapply(mats, rownames))
  common <- intersect(common, names(cluster))
  if (length(common) < 2L) {
    stop("Not enough samples shared across the omics layers and clusters.")
  }
  concat <- do.call(cbind, lapply(mats, function(m) {
    sub <- m[common, , drop = FALSE]
    sub <- scale(sub)
    sub[, apply(sub, 2L, function(col) all(is.finite(col))), drop = FALSE]
  }))
  d <- dist(concat)
  sil <- silhouette(as.integer(factor(cluster[common], levels = levs)), d)
  grDevices::png(params$png_path, width = 1000, height = 760, res = 130)
  on.exit(grDevices::dev.off(), add = TRUE)
  plot(sil, col = palette_cols[seq_along(levs)],
       main = "Silhouette of DSCC subtypes")
  cat(sprintf("%s Wrote silhouette plot (%d subtypes, %d samples)\n",
              ts(), length(levs), length(common)))

} else {
  stop(sprintf("Unknown plot_type: %s", params$plot_type))
}
