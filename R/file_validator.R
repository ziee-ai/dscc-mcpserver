# Validators for the two DSCC input file kinds. Both accept CSV or TSV
# (separator auto-detected from the header line) and return a list with a
# `valid` flag, human-readable `issues`, and metadata used by the
# validate_input_file tool and the subtyping/evaluation prepare paths.

# An omics matrix is features x samples: first column = feature ID
# (row names), header row = sample names, remaining cells numeric.
validate_omics_matrix <- function(path) {
  # Read with the feature IDs as a regular first column (not row.names) so
  # duplicate feature IDs can be reported cleanly rather than erroring in
  # read.csv ("duplicate 'row.names' are not allowed").
  read_res <- tryCatch({
    first_line <- readLines(path, n = 1L, warn = FALSE)
    sep <- if (grepl("\t", first_line)) "\t" else ","
    utils::read.csv(path, sep = sep, check.names = FALSE,
                    stringsAsFactors = FALSE)
  }, error = function(e) e)
  if (inherits(read_res, "error")) {
    return(list(valid = FALSE,
                issues = paste("Cannot read file:", conditionMessage(read_res)),
                sample_names = character(0L),
                n_features = 0L, n_samples = 0L, preview = ""))
  }
  df <- read_res

  if (nrow(df) == 0L || ncol(df) < 1L) {
    return(list(valid = FALSE,
                issues = "File is empty or has no feature rows",
                sample_names = character(0L),
                n_features = 0L, n_samples = 0L, preview = ""))
  }

  feature_ids  <- as.character(df[[1L]])
  value_df     <- df[, -1L, drop = FALSE]
  sample_names <- colnames(value_df)
  n_features   <- nrow(df)
  n_samples    <- ncol(value_df)

  issues <- character(0L)
  if (n_samples < 2L) {
    issues <- c(issues, sprintf(
      "Only %d sample column(s) found - at least 2 samples are required",
      n_samples))
  }
  if (n_features < 2L) {
    issues <- c(issues, sprintf(
      "Only %d feature row(s) found - at least 2 features are required",
      n_features))
  }

  for (col in sample_names) {
    vals <- suppressWarnings(as.numeric(value_df[[col]]))
    bad <- which(is.na(vals) & !is.na(value_df[[col]]))
    if (length(bad) > 0L) {
      examples <- utils::head(value_df[[col]][bad], 2L)
      issues <- c(issues, sprintf(
        "Sample column '%s' contains non-numeric values (e.g. %s) - replace with 0 or NA",
        col, paste(examples, collapse = ", ")))
    }
  }

  dup_ids <- feature_ids[duplicated(feature_ids)]
  if (length(dup_ids) > 0L) {
    issues <- c(issues, sprintf(
      "Duplicate feature IDs detected: %s - remove or merge duplicate rows",
      paste(utils::head(unique(dup_ids), 3L), collapse = ", ")))
  }

  preview <- tryCatch(
    paste(utils::capture.output(
      print(utils::head(df[, seq_len(min(5L, ncol(df))), drop = FALSE], 3L))),
      collapse = "\n"),
    error = function(e) ""
  )

  list(valid = length(issues) == 0L,
       issues = issues,
       sample_names = sample_names,
       n_features = n_features,
       n_samples = n_samples,
       preview = preview)
}

# Column aliases accepted for the survival event indicator.
.SURVIVAL_EVENT_ALIASES <- c("isDead", "OSstatus", "status", "event", "vital_status")
.SURVIVAL_TIME_ALIASES  <- c("os", "OS", "time", "os_time", "survival", "OS.time")

# A survival table has one row per sample with a sample identifier, an
# overall-survival time (>= 0), and a binary event indicator (0/1).
validate_survival_table <- function(path) {
  first_line <- tryCatch(readLines(path, n = 1L, warn = FALSE),
                         error = function(e) character(0L))
  if (length(first_line) == 0L) {
    return(list(valid = FALSE,
                issues = "File is empty or could not be parsed as CSV/TSV"))
  }
  sep <- if (grepl("\t", first_line)) "\t" else ","
  df <- tryCatch(
    utils::read.csv(path, sep = sep, stringsAsFactors = FALSE,
                    check.names = FALSE),
    error = function(e) NULL
  )
  if (is.null(df) || nrow(df) == 0L) {
    return(list(valid = FALSE,
                issues = "File is empty or could not be parsed as CSV/TSV"))
  }

  found <- colnames(df)
  issues <- character(0L)

  time_col  <- intersect(.SURVIVAL_TIME_ALIASES, found)
  event_col <- intersect(.SURVIVAL_EVENT_ALIASES, found)
  if (length(time_col) == 0L) {
    issues <- c(issues, sprintf(
      paste("No survival time column found. Provide one named 'os'.",
            "Columns present: %s"),
      paste(found, collapse = ", ")))
  }
  if (length(event_col) == 0L) {
    issues <- c(issues, sprintf(
      paste("No event column found. Provide one named 'isDead' (1 = event,",
            "0 = censored). Columns present: %s"),
      paste(found, collapse = ", ")))
  }
  if (length(issues) > 0L) {
    return(list(valid = FALSE, issues = issues))
  }
  time_col  <- time_col[[1L]]
  event_col <- event_col[[1L]]

  # Sample IDs: a 'sample' column if present, otherwise the first column.
  if ("sample" %in% found) {
    samples <- trimws(as.character(df$sample))
  } else {
    samples <- trimws(as.character(df[[1L]]))
  }

  os_vals <- suppressWarnings(as.numeric(df[[time_col]]))
  if (any(is.na(os_vals) & !is.na(df[[time_col]]))) {
    issues <- c(issues, sprintf(
      "Survival time column '%s' contains non-numeric values", time_col))
  } else if (any(os_vals < 0, na.rm = TRUE)) {
    issues <- c(issues, sprintf(
      "Survival time column '%s' contains negative values", time_col))
  }

  ev_vals <- suppressWarnings(as.numeric(df[[event_col]]))
  if (any(is.na(ev_vals) & !is.na(df[[event_col]]))) {
    issues <- c(issues, sprintf(
      "Event column '%s' contains non-numeric values", event_col))
  } else if (!all(stats::na.omit(ev_vals) %in% c(0, 1))) {
    issues <- c(issues, sprintf(
      "Event column '%s' must be 0 (censored) or 1 (event)", event_col))
  }

  dupes <- unique(samples[duplicated(samples)])
  if (length(dupes) > 0L) {
    issues <- c(issues, sprintf("Duplicate sample names: %s",
                                paste(utils::head(dupes, 3L), collapse = ", ")))
  }

  if (length(issues) > 0L) {
    return(list(valid = FALSE, issues = issues))
  }

  n_events <- sum(ev_vals == 1, na.rm = TRUE)
  preview <- tryCatch(
    paste(utils::capture.output(
      print(utils::head(df, 3L), row.names = FALSE)),
      collapse = "\n"),
    error = function(e) ""
  )
  list(valid = TRUE,
       issues = character(0L),
       n_samples = nrow(df),
       n_events = as.integer(n_events),
       sample_names = samples,
       time_col = time_col,
       event_col = event_col,
       preview = preview)
}
