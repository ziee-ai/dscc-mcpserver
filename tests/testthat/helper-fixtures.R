file_uri <- function(path) {
  paste0("file://", normalizePath(path, mustWork = FALSE))
}

# Tests load via load_all so tests/testthat.R doesn't run; set the
# opt-in here as well for safety.
Sys.setenv(DSCC_ALLOW_LOCAL_URIS = "TRUE")

# Path to a fixture installed under inst/fixtures/.
fixture_path <- function(name) {
  p <- system.file("fixtures", name, package = "dscc.mcpserver")
  if (!nzchar(p) || !file.exists(p)) {
    p <- file.path("inst", "fixtures", name)
  }
  if (!file.exists(p)) {
    stop(sprintf("fixture '%s' not found", name))
  }
  p
}

write_omics_csv <- function(n_features = 10L, n_samples = 6L,
                            sample_names = paste0("sample", seq_len(n_samples)),
                            feature_prefix = "feat") {
  tmp <- tempfile(fileext = ".csv")
  m <- matrix(stats::rnorm(n_features * n_samples, mean = 5, sd = 1),
              nrow = n_features, ncol = n_samples,
              dimnames = list(paste0(feature_prefix, seq_len(n_features)),
                              sample_names))
  utils::write.csv(m, tmp, row.names = TRUE)
  tmp
}

write_survival_csv <- function(sample_names, os = NULL, is_dead = NULL) {
  n <- length(sample_names)
  if (is.null(os)) os <- seq_len(n) + 5L
  if (is.null(is_dead)) is_dead <- rep(c(1L, 0L), length.out = n)
  df <- data.frame(sample = sample_names, os = os, isDead = is_dead,
                   stringsAsFactors = FALSE)
  tmp <- tempfile(fileext = ".csv")
  utils::write.csv(df, tmp, row.names = FALSE)
  tmp
}

write_clusters_csv <- function(sample_names, clusters = NULL) {
  n <- length(sample_names)
  if (is.null(clusters)) clusters <- rep(1:2, length.out = n)
  df <- data.frame(sample = sample_names, cluster = clusters,
                   stringsAsFactors = FALSE)
  tmp <- tempfile(fileext = ".csv")
  utils::write.csv(df, tmp, row.names = FALSE)
  tmp
}

# Mock McpCtx: stubs out everything tool handlers might call.
# request_elicitation returns canned values from `elicit_returns`
# (a list of `list(action=, content=)` objects, consumed in order).
build_mock_ctx <- function(elicit_returns = list(),
                           cancelled = FALSE) {
  e <- new.env(parent = emptyenv())
  e$session_id <- "test-session"
  e$client_capabilities <- list(elicitation = list())
  e$auth_subject <- NULL
  e$auth_scopes <- NULL
  e$progress_token <- NULL
  e$msg_meta <- NULL
  e$.elicit_queue <- elicit_returns
  e$.elicit_calls <- list()
  e$.cancel <- cancelled
  e$.logs <- list()
  e$send_log <- function(level, message, logger = NULL, data = NULL) {
    e$.logs[[length(e$.logs) + 1L]] <-
      list(level = level, message = message, logger = logger, data = data)
    invisible()
  }
  e$send_progress <- function(progress, total = NULL, message = NULL) invisible()
  e$cancelled <- function() isTRUE(e$.cancel)
  e$on_cancel <- function(fn) invisible()
  e$request_elicitation <- function(message, requested_schema, timeout = 30) {
    e$.elicit_calls[[length(e$.elicit_calls) + 1L]] <-
      list(message = message, schema = requested_schema)
    if (length(e$.elicit_queue) == 0L) {
      stop("mock ctx: no elicitation response queued")
    }
    resp <- e$.elicit_queue[[1L]]
    e$.elicit_queue <- e$.elicit_queue[-1L]
    resp
  }
  # NOTE: deliberately NOT setting class to McpCtx - a plain environment
  # uses normal $ access and returns the assigned function.
  e
}

error_text <- function(err) {
  if (!is.list(err)) return("")
  if (!is.null(err$content) && is.list(err$content)) {
    return(paste(vapply(err$content, function(c) c$text %||% "",
                        character(1L)),
                 collapse = "\n"))
  }
  ""
}
