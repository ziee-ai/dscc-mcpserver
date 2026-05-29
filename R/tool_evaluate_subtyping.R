.DSCC_DEFAULT_PERMUTATIONS <- 1000L

tool_evaluate_subtyping <- function() {
  mcpserver::new_tool(
    name = "evaluate_subtyping",
    description = paste(
      "Evaluate the prognostic value of a subtyping by linking the",
      "sample-to-subtype assignments to survival data. Computes a Cox",
      "proportional-hazards score-test p-value, and optionally an empirical",
      "log-rank p-value via label permutation. Provide a clusters CSV",
      "(sample / cluster, e.g. the output of run_dscc_subtyping) and a",
      "survival table (sample / os / isDead).",
      "An elicitation-capable client is prompted for whether to run the",
      "permutation test (and how many permutations) when not specified.",
      "All *_uri parameters must be URLs from your platform - do not",
      "construct or modify them."),
    input_schema = mcpserver::schema(list(
      clusters_uri = mcpserver::property_string(
        description = paste(
          "URL to a clusters CSV with 'sample' and 'cluster' columns.",
          "Pass it exactly as provided."),
        required = TRUE),
      survival_uri = mcpserver::property_string(
        description = paste(
          "URL to a survival table (sample / os / isDead).",
          "Pass it exactly as provided."),
        required = TRUE),
      empirical = mcpserver::property_boolean(
        description = paste(
          "Whether to also compute an empirical log-rank p-value by",
          "permuting subtype labels. Omit to be prompted; defaults to false.")),
      n_permutations = mcpserver::property_integer(
        description = paste(
          "Number of permutations for the empirical test (only used when",
          "empirical = true). Omit to be prompted; defaults to 1000."),
        minimum = 100L, maximum = 100000L)
    )),
    annotations = list(
      readOnlyHint = FALSE,
      destructiveHint = FALSE,
      idempotentHint = TRUE,
      openWorldHint = TRUE,
      title = "Evaluate Subtyping"
    ),
    bidirectional = TRUE,
    handler = evaluate_subtyping_handler
  )
}

evaluate_subtyping_handler <- function(args, ctx) {
  filled <- elicit_evaluate_args(args, ctx)
  if (is_tool_error(filled)) return(filled)
  prep <- evaluate_prepare(filled)
  if (!is.null(prep$error)) return(prep$error)
  job <- run_job_sync(prep$script_path, prep$job_name)
  safe_unlink_all(prep$tmp_files)
  evaluate_build_response(job, prep)
}

# ── Elicitation flow ─────────────────────────────────────────────────────
elicit_evaluate_args <- function(args, ctx) {
  empirical <- args$empirical
  n_perm    <- args$n_permutations

  caps <- ctx$client_capabilities %||% list()
  can_elicit <- !is.null(caps$elicitation)

  if (is.null(empirical)) {
    if (!can_elicit) {
      empirical <- FALSE
    } else {
      res <- tryCatch(ctx$request_elicitation(
        message = paste(
          "Also run a permutation log-rank test for an empirical p-value?",
          "It is more robust than the Cox test but slower."),
        requested_schema = dscc_empirical_schema()),
        error = function(e) e)
      if (inherits(res, "error")) {
        return(mcp_tool_error(paste("Elicitation failed:",
                                     conditionMessage(res))))
      }
      if (!identical(res$action %||% "accept", "accept")) {
        return(mcp_tool_error("User declined to choose the evaluation mode."))
      }
      empirical <- isTRUE(res$content$empirical)
    }
  }
  empirical <- isTRUE(as.logical(empirical))

  if (empirical && is.null(n_perm)) {
    if (!can_elicit) {
      n_perm <- .DSCC_DEFAULT_PERMUTATIONS
    } else {
      res <- tryCatch(ctx$request_elicitation(
        message = "How many permutations should the empirical test use?",
        requested_schema = dscc_permutations_schema()),
        error = function(e) e)
      if (inherits(res, "error")) {
        return(mcp_tool_error(paste("Elicitation failed:",
                                     conditionMessage(res))))
      }
      n_perm <- suppressWarnings(
        as.integer(res$content$n_permutations %||% .DSCC_DEFAULT_PERMUTATIONS))
      if (is.na(n_perm)) n_perm <- .DSCC_DEFAULT_PERMUTATIONS
    }
  }
  if (is.null(n_perm)) n_perm <- .DSCC_DEFAULT_PERMUTATIONS

  args$empirical <- empirical
  args$n_permutations <- as.integer(n_perm)
  args
}

dscc_empirical_schema <- function() {
  list(
    type = "object",
    required = I("empirical"),
    properties = list(
      empirical = list(
        type = "boolean",
        title = "Permutation log-rank test",
        description = paste("Compute an empirical p-value by permuting subtype",
                            "labels (slower, assumption-free)."),
        default = FALSE
      )
    )
  )
}

dscc_permutations_schema <- function() {
  list(
    type = "object",
    required = I("n_permutations"),
    properties = list(
      n_permutations = list(
        type = "integer",
        title = "Number of permutations",
        description = "More permutations give a more precise empirical p-value.",
        minimum = 100L, maximum = 100000L,
        default = .DSCC_DEFAULT_PERMUTATIONS
      )
    )
  )
}

# ── Prepare: validate + fetch + build the job ────────────────────────────
evaluate_prepare <- function(args) {
  clusters_uri <- trimws(args$clusters_uri %||% "")
  survival_uri <- trimws(args$survival_uri %||% "")
  empirical <- isTRUE(args$empirical)
  n_perm <- as.integer(args$n_permutations %||% .DSCC_DEFAULT_PERMUTATIONS)

  tmp_files <- list()
  fail <- function(resp) {
    safe_unlink_all(tmp_files)
    list(error = resp)
  }

  if (!nzchar(clusters_uri)) {
    return(fail(mcp_tool_error("clusters_uri is required.")))
  }
  if (!nzchar(survival_uri)) {
    return(fail(mcp_tool_error("survival_uri is required.")))
  }

  tmp_clusters <- tryCatch(fetch_to_tempfile(clusters_uri), error = function(e) e)
  if (inherits(tmp_clusters, "error")) {
    return(fail(mcp_tool_error(paste("Failed to fetch clusters_uri:",
                                      conditionMessage(tmp_clusters)))))
  }
  tmp_files[[length(tmp_files) + 1L]] <- tmp_clusters
  cl <- tryCatch(utils::read.csv(tmp_clusters, stringsAsFactors = FALSE),
                 error = function(e) e)
  if (inherits(cl, "error") || !"cluster" %in% colnames(cl)) {
    return(fail(mcp_tool_error(
      "clusters file must be a CSV with 'sample' and 'cluster' columns.")))
  }

  tmp_survival <- tryCatch(fetch_to_tempfile(survival_uri), error = function(e) e)
  if (inherits(tmp_survival, "error")) {
    return(fail(mcp_tool_error(paste("Failed to fetch survival_uri:",
                                      conditionMessage(tmp_survival)))))
  }
  tmp_files[[length(tmp_files) + 1L]] <- tmp_survival
  sr <- validate_survival_table(tmp_survival)
  if (!sr$valid) {
    return(fail(mcp_tool_error(sr$issues, expected_format = .SURVIVAL_FORMAT)))
  }

  run <- make_run_dir()
  base_name <- "evaluate_subtyping"
  eval_json <- file.path(run$dir, "evaluation.json")
  eval_url  <- result_uri(run$run_id, "evaluation.json")

  job <- make_job_script(run$dir, base_name, "evaluate_subtyping", list(
    clusters_path  = tmp_clusters,
    survival_path  = tmp_survival,
    empirical      = empirical,
    n_permutations = n_perm,
    eval_json      = eval_json
  ))

  list(
    error = NULL,
    script_path = job$script_path,
    job_name = base_name,
    eval_json = eval_json,
    eval_url = eval_url,
    empirical = empirical,
    run_id = run$run_id,
    tmp_files = tmp_files
  )
}

evaluate_build_response <- function(job_result, prep) {
  if (!job_result$success) {
    return(mcp_tool_error(paste("Subtyping evaluation failed:", job_result$stderr)))
  }
  res <- tryCatch(jsonlite::fromJSON(prep$eval_json), error = function(e) NULL)
  if (is.null(res)) {
    return(mcp_tool_error(paste(
      "Evaluation produced no usable evaluation.json. stderr:",
      job_result$stderr)))
  }
  res$result_type <- "dscc_evaluation"
  res$run_id <- prep$run_id

  metadata_json <- jsonlite::toJSON(res, auto_unbox = TRUE)
  list(
    content = list(
      mcpserver::response_text(metadata_json),
      mcpserver::response_resource_link(
        uri = prep$eval_url,
        name = "evaluation.json",
        mime_type = "application/json")
    ),
    isError = FALSE
  )
}
