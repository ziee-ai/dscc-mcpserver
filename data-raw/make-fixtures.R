# Regenerate the small synthetic fixtures under inst/fixtures/.
# Deterministic (fixed seed). Three latent sample groups with omics signal
# and a group-linked survival outcome, sized so DSCC subtyping and the
# evaluation/plot templates run quickly during Tier-3 tests.
#
# Run:  Rscript data-raw/make-fixtures.R
set.seed(42)

n_per_group <- 10L
groups <- rep(1:3, each = n_per_group)
n <- length(groups)
samples <- sprintf("sample%02d", seq_len(n))

# Build one features x samples matrix: `n_signal` features separate the
# groups (group-specific means), the rest are noise.
make_layer <- function(n_features, n_signal, feat_prefix, base = 6, sd = 1) {
  m <- matrix(rnorm(n_features * n, mean = base, sd = sd),
              nrow = n_features, ncol = n)
  for (f in seq_len(n_signal)) {
    shift <- c(0, 2.5, -2.5)[((f - 1L) %% 3L) + 1L]
    # rotate which group this signal feature separates
    g <- ((f - 1L) %% 3L) + 1L
    m[f, groups == g] <- m[f, groups == g] + 3
  }
  rownames(m) <- sprintf("%s%03d", feat_prefix, seq_len(n_features))
  colnames(m) <- samples
  m
}

omics1 <- make_layer(50L, 18L, "gene")
omics2 <- make_layer(40L, 15L, "prot", base = 8, sd = 1.2)

out <- "inst/fixtures"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
write.csv(omics1, file.path(out, "omics1.csv"))
write.csv(omics2, file.path(out, "omics2.csv"))

# Survival: group 1 has the worst prognosis, group 3 the best.
group_scale <- c(8, 18, 30)[groups]
os <- round(rexp(n, rate = 1 / group_scale)) + 1L
is_dead <- rbinom(n, 1L, prob = c(0.8, 0.5, 0.3)[groups])
survival <- data.frame(sample = samples, os = os, isDead = is_dead,
                       stringsAsFactors = FALSE)
write.csv(survival, file.path(out, "survival.csv"), row.names = FALSE)

cat("Wrote omics1.csv (50x30), omics2.csv (40x30), survival.csv (30)\n")
