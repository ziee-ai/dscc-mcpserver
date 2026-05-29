.DSCC_DEFAULT_MAX_CLUSTERS <- 10L

tool_run_dscc_subtyping <- function() {
  mcpserver::new_tool(
    name = "run_dscc_subtyping",
    description = paste(
      "Run DSCC multi-omics cancer subtyping. Provide one URL per omics",
      "layer (each a features x samples matrix); DSCC integrates them into",
      "consensus networks and assigns every shared sample to a subtype.",
      "Returns a CSV of sample-to-subtype assignments. Optionally pass a",
      "survival table URL to also get a Cox p-value for the subtypes.",
      "An elicitation-capable client is prompted for the maximum number of",
      "clusters (and, when there are 2+ layers, optional layer labels) when",
      "not provided. All *_uri parameters must be URLs from your platform -",
      "do not construct or modify them."),
    input_schema = mcpserver::schema(list(
      omics_uris = mcpserver::property_array(
        items = mcpserver::property_string(),
        description = paste(
          "Array of URLs, one per omics layer (e.g. expression, methylation,",
          "proteomics). Each is a features x samples CSV. Two or more layers",
          "are recommended. Pass URLs exactly as provided."),
        required = TRUE),
      survival_uri = mcpserver::property_string(
        description = paste(
          "Optional URL to a survival table (sample / os / isDead).",
          "When provided, a Cox proportional-hazards p-value for the",
          "discovered subtypes is computed and returned.")),
      max_clusters = mcpserver::property_integer(
        description = paste(
          "Maximum number of subtypes to consider (DSCC 'defk'; it",
          "auto-selects the best k up to this bound). Omit to be prompted",
          "interactively; defaults to 10."),
        minimum = 2L, maximum = 15L),
      omics_names = mcpserver::property_array(
        items = mcpserver::property_string(),
        description = paste(
          "Optional labels for the omics layers, in the same order as",
          "omics_uris. With 2+ layers you may be prompted to label them;",
          "defaults to omics_1, omics_2, ..."))
    )),
    annotations = list(
      readOnlyHint = FALSE,
      destructiveHint = FALSE,
      idempotentHint = FALSE,
      openWorldHint = TRUE,
      title = "Run DSCC Subtyping"
    ),
    bidirectional = TRUE,
    handler = run_dscc_subtyping_handler
  )
}

run_dscc_subtyping_handler <- function(args, ctx) {
  filled <- elicit_subtyping_args(args, ctx)
  if (is_tool_error(filled)) return(filled)
  prep <- subtyping_prepare(filled)
  if (!is.null(prep$error)) return(prep$error)
  job <- run_job_sync(prep$script_path, prep$job_name)
  safe_unlink_all(prep$tmp_files)
  subtyping_build_response(job, prep)
}

# ── Elicitation flow ─────────────────────────────────────────────────────
elicit_subtyping_args <- function(args, ctx) {
  max_clusters <- args$max_clusters
  if (!is.null(max_clusters)) {
    max_clusters <- suppressWarnings(as.integer(max_clusters))
    if (is.na(max_clusters)) max_clusters <- NULL
  }

  if (is.null(max_clusters)) {
    caps <- ctx$client_capabilities %||% list()
    can_elicit <- !is.null(caps$elicitation)
    if (!can_elicit) {
      max_clusters <- .DSCC_DEFAULT_MAX_CLUSTERS
    } else {
      res <- tryCatch(ctx$request_elicitation(
        message = paste(
          "What is the maximum number of subtypes DSCC should consider?",
          "DSCC automatically selects the best number of clusters up to",
          "this bound (default 10)."),
        requested_schema = dscc_max_clusters_schema()),
        error = function(e) e)
      if (inherits(res, "error")) {
        return(mcp_tool_error(paste("Elicitation failed:",
                                     conditionMessage(res))))
      }
      if (!identical(res$action %||% "accept", "accept")) {
        return(mcp_tool_error("User declined to choose the maximum number of clusters."))
      }
      max_clusters <- suppressWarnings(
        as.integer(res$content$max_clusters %||% .DSCC_DEFAULT_MAX_CLUSTERS))
      if (is.na(max_clusters)) max_clusters <- .DSCC_DEFAULT_MAX_CLUSTERS
    }
  }
  if (max_clusters < 2L) max_clusters <- 2L
  args$max_clusters <- max_clusters

  # omics_names: optional per-layer labels. Only worth eliciting when there
  # are 2+ layers to tell apart; a single layer is always just "omics_1".
  omics_uris <- args$omics_uris
  if (is.character(omics_uris)) omics_uris <- as.list(omics_uris)
  n_layers <- length(omics_uris %||% list())

  names_ok <- function(nm) {
    length(nm) == n_layers &&
      all(vapply(nm, function(x) nzchar(trimws(as.character(x))), logical(1L)))
  }

  omics_names <- args$omics_names
  if (is.character(omics_names)) omics_names <- as.list(omics_names)
  omics_names <- omics_names %||% list()

  if (!names_ok(omics_names) && n_layers >= 2L) {
    caps <- ctx$client_capabilities %||% list()
    if (!is.null(caps$elicitation)) {
      res <- tryCatch(ctx$request_elicitation(
        message = paste(
          sprintf("Optionally label the %d omics layers, in the same order", n_layers),
          "as the URLs (e.g. expression, methylation). Accept the defaults",
          "to use omics_1, omics_2, ..."),
        requested_schema = dscc_omics_names_schema(n_layers)),
        error = function(e) e)
      if (inherits(res, "error")) {
        return(mcp_tool_error(paste("Elicitation failed:",
                                     conditionMessage(res))))
      }
      # Labels are optional, so a decline just keeps the defaults below.
      if (identical(res$action %||% "accept", "accept")) {
        elicited <- res$content$omics_names
        if (is.character(elicited)) elicited <- as.list(elicited)
        elicited <- lapply(elicited %||% list(),
                           function(x) trimws(as.character(x)))
        if (names_ok(elicited)) omics_names <- elicited
      }
    }
  }

  if (!names_ok(omics_names) && n_layers > 0L) {
    omics_names <- as.list(sprintf("omics_%d", seq_len(n_layers)))
  }
  args$omics_names <- omics_names
  args
}

dscc_omics_names_schema <- function(n) {
  list(
    type = "object",
    required = I("omics_names"),
    properties = list(
      omics_names = list(
        type = "array",
        title = "Omics layer labels",
        description = "One label per omics layer, in the same order as the URLs.",
        items = list(type = "string"),
        minItems = n, maxItems = n,
        default = I(sprintf("omics_%d", seq_len(n)))
      )
    )
  )
}

dscc_max_clusters_schema <- function() {
  list(
    type = "object",
    required = I("max_clusters"),
    properties = list(
      max_clusters = list(
        type = "integer",
        title = "Maximum number of clusters",
        description = paste("Upper bound on the number of subtypes DSCC will",
                            "consider (2-15)."),
        minimum = 2L, maximum = 15L,
        default = .DSCC_DEFAULT_MAX_CLUSTERS
      )
    )
  )
}

# ── Prepare: validate + fetch + build the job ────────────────────────────
subtyping_prepare <- function(args) {
  omics_uris <- args$omics_uris
  if (is.character(omics_uris)) omics_uris <- as.list(omics_uris)
  omics_uris <- omics_uris %||% list()
  omics_uris <- lapply(omics_uris, function(u) trimws(as.character(u)))
  omics_uris <- omics_uris[vapply(omics_uris, nzchar, logical(1L))]

  survival_uri <- trimws(args$survival_uri %||% "")
  max_clusters <- as.integer(args$max_clusters %||% .DSCC_DEFAULT_MAX_CLUSTERS)

  tmp_files <- list()
  fail <- function(resp) {
    safe_unlink_all(tmp_files)
    list(error = resp)
  }

  if (length(omics_uris) < 1L) {
    return(fail(mcp_tool_error(
      "omics_uris is required - provide at least one omics matrix URL (two or more recommended).")))
  }

  # Labels for each layer.
  omics_names <- args$omics_names
  if (is.character(omics_names)) omics_names <- as.list(omics_names)
  omics_names <- omics_names %||% list()
  omics_names <- lapply(omics_names, function(x) trimws(as.character(x)))
  if (length(omics_names) != length(omics_uris)) {
    omics_names <- as.list(sprintf("omics_%d", seq_along(omics_uris)))
  }

  omics_paths <- character(0L)
  for (i in seq_along(omics_uris)) {
    tmp <- tryCatch(fetch_to_tempfile(omics_uris[[i]]), error = function(e) e)
    if (inherits(tmp, "error")) {
      return(fail(mcp_tool_error(sprintf(
        "Failed to fetch omics layer %d (%s): %s",
        i, omics_names[[i]], conditionMessage(tmp)))))
    }
    tmp_files[[length(tmp_files) + 1L]] <- tmp
    vr <- validate_omics_matrix(tmp)
    if (!vr$valid) {
      return(fail(mcp_tool_error(
        c(sprintf("Omics layer %d (%s) is invalid:", i, omics_names[[i]]),
          vr$issues),
        expected_format = .OMICS_FORMAT)))
    }
    omics_paths <- c(omics_paths, tmp)
  }

  survival_path <- NULL
  if (nzchar(survival_uri)) {
    survival_path <- tryCatch(fetch_to_tempfile(survival_uri),
                              error = function(e) e)
    if (inherits(survival_path, "error")) {
      return(fail(mcp_tool_error(paste("Failed to fetch survival_uri:",
                                        conditionMessage(survival_path)))))
    }
    tmp_files[[length(tmp_files) + 1L]] <- survival_path
    sr <- validate_survival_table(survival_path)
    if (!sr$valid) {
      return(fail(mcp_tool_error(sr$issues,
                                  expected_format = .SURVIVAL_FORMAT)))
    }
  }

  run <- make_run_dir()
  base_name <- "dscc_subtyping"
  clusters_csv <- file.path(run$dir, "clusters.csv")
  clusters_rds <- file.path(run$dir, "clusters.rds")
  cox_json     <- file.path(run$dir, "cox.json")
  clusters_url <- result_uri(run$run_id, "clusters.csv")

  job <- make_job_script(run$dir, base_name, "dscc_subtyping", list(
    omics_paths      = as.list(omics_paths),
    omics_names      = omics_names,
    max_clusters     = max_clusters,
    survival_path    = survival_path,
    clusters_csv     = clusters_csv,
    clusters_rds     = clusters_rds,
    cox_json         = cox_json,
    nemo_src         = dscc_source_path("nemo_helpers.R"),
    dscc_src         = dscc_source_path("DSCC_helper.R")
  ))

  list(
    error = NULL,
    script_path = job$script_path,
    job_name = base_name,
    clusters_csv = clusters_csv,
    clusters_url = clusters_url,
    cox_json = cox_json,
    n_omics = length(omics_paths),
    max_clusters = max_clusters,
    has_survival = !is.null(survival_path),
    run_id = run$run_id,
    tmp_files = tmp_files
  )
}

subtyping_build_response <- function(job_result, prep) {
  if (!job_result$success) {
    return(mcp_tool_error(paste("DSCC subtyping failed:", job_result$stderr)))
  }
  clusters <- tryCatch(utils::read.csv(prep$clusters_csv,
                                       stringsAsFactors = FALSE),
                       error = function(e) NULL)
  if (is.null(clusters) || !"cluster" %in% colnames(clusters)) {
    return(mcp_tool_error(paste(
      "DSCC subtyping produced no usable clusters.csv. stderr:",
      job_result$stderr)))
  }
  n_samples  <- nrow(clusters)
  n_clusters <- length(unique(clusters$cluster))

  response_data <- list(
    result_type = "dscc_subtyping",
    n_clusters  = n_clusters,
    n_samples   = n_samples,
    n_omics     = prep$n_omics,
    max_clusters = prep$max_clusters,
    run_id      = prep$run_id
  )
  if (isTRUE(prep$has_survival) && file.exists(prep$cox_json)) {
    cox <- tryCatch(jsonlite::fromJSON(prep$cox_json), error = function(e) NULL)
    if (!is.null(cox$cox_pvalue)) response_data$cox_pvalue <- cox$cox_pvalue
  }

  metadata_json <- jsonlite::toJSON(response_data, auto_unbox = TRUE)
  list(
    content = list(
      mcpserver::response_text(metadata_json),
      mcpserver::response_resource_link(
        uri = prep$clusters_url,
        name = "clusters.csv",
        mime_type = "text/csv")
    ),
    isError = FALSE
  )
}
