tool_plot_subtypes <- function() {
  mcpserver::new_tool(
    name = "plot_subtypes",
    description = paste(
      "Produce a diagnostic plot for a subtyping as a PNG. Two plot types:",
      "'kaplan_meier' (survival curves stratified by subtype - needs a",
      "survival table) and 'silhouette' (per-sample silhouette widths -",
      "needs the omics layers to recompute sample distances).",
      "Provide a clusters CSV (sample / cluster).",
      "An elicitation-capable client is prompted for the plot type when it",
      "is not provided. All *_uri parameters must be URLs from your",
      "platform - do not construct or modify them."),
    input_schema = mcpserver::schema(list(
      clusters_uri = mcpserver::property_string(
        description = paste(
          "URL to a clusters CSV with 'sample' and 'cluster' columns.",
          "Pass it exactly as provided."),
        required = TRUE),
      plot_type = mcpserver::property_enum(
        values = c("kaplan_meier", "silhouette"),
        description = paste(
          "Which plot to draw. Omit to be prompted interactively.")),
      survival_uri = mcpserver::property_string(
        description = paste(
          "URL to a survival table (sample / os / isDead).",
          "Required for plot_type = 'kaplan_meier'.")),
      omics_uris = mcpserver::property_array(
        items = mcpserver::property_string(),
        description = paste(
          "Array of omics matrix URLs (features x samples), the same layers",
          "used for subtyping. Required for plot_type = 'silhouette' to",
          "recompute sample distances."))
    )),
    annotations = list(
      readOnlyHint = FALSE,
      destructiveHint = FALSE,
      idempotentHint = TRUE,
      openWorldHint = TRUE,
      title = "Plot Subtypes"
    ),
    bidirectional = TRUE,
    handler = plot_subtypes_handler
  )
}

plot_subtypes_handler <- function(args, ctx) {
  filled <- elicit_plot_args(args, ctx)
  if (is_tool_error(filled)) return(filled)
  prep <- plot_prepare(filled)
  if (!is.null(prep$error)) return(prep$error)
  job <- run_job_sync(prep$script_path, prep$job_name)
  safe_unlink_all(prep$tmp_files)
  plot_build_response(job, prep)
}

# ── Elicitation flow ─────────────────────────────────────────────────────
elicit_plot_args <- function(args, ctx) {
  plot_type <- trimws(args$plot_type %||% "")

  if (!nzchar(plot_type)) {
    caps <- ctx$client_capabilities %||% list()
    can_elicit <- !is.null(caps$elicitation)
    if (!can_elicit) {
      plot_type <- "kaplan_meier"
    } else {
      res <- tryCatch(ctx$request_elicitation(
        message = paste(
          "Which diagnostic plot would you like?",
          "'kaplan_meier' shows survival curves per subtype;",
          "'silhouette' shows clustering quality."),
        requested_schema = dscc_plot_type_schema()),
        error = function(e) e)
      if (inherits(res, "error")) {
        return(mcp_tool_error(paste("Elicitation failed:",
                                     conditionMessage(res))))
      }
      if (!identical(res$action %||% "accept", "accept")) {
        return(mcp_tool_error("User declined to choose the plot type."))
      }
      plot_type <- trimws(res$content$plot_type %||% "kaplan_meier")
    }
  }

  args$plot_type <- plot_type
  args
}

dscc_plot_type_schema <- function() {
  list(
    type = "object",
    required = I("plot_type"),
    properties = list(
      plot_type = list(
        type = "string",
        title = "Plot type",
        enum = I(c("kaplan_meier", "silhouette")),
        default = "kaplan_meier"
      )
    )
  )
}

# ── Prepare: validate + fetch + build the job ────────────────────────────
plot_prepare <- function(args) {
  clusters_uri <- trimws(args$clusters_uri %||% "")
  survival_uri <- trimws(args$survival_uri %||% "")
  plot_type    <- trimws(args$plot_type %||% "kaplan_meier")

  omics_uris <- args$omics_uris
  if (is.character(omics_uris)) omics_uris <- as.list(omics_uris)
  omics_uris <- omics_uris %||% list()
  omics_uris <- lapply(omics_uris, function(u) trimws(as.character(u)))
  omics_uris <- omics_uris[vapply(omics_uris, nzchar, logical(1L))]

  tmp_files <- list()
  fail <- function(resp) {
    safe_unlink_all(tmp_files)
    list(error = resp)
  }

  if (!plot_type %in% c("kaplan_meier", "silhouette")) {
    return(fail(mcp_tool_error(sprintf(
      "plot_type must be 'kaplan_meier' or 'silhouette'. Got: '%s'",
      plot_type))))
  }
  if (!nzchar(clusters_uri)) {
    return(fail(mcp_tool_error("clusters_uri is required.")))
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

  survival_path <- NULL
  omics_paths <- character(0L)

  if (identical(plot_type, "kaplan_meier")) {
    if (!nzchar(survival_uri)) {
      return(fail(mcp_tool_error(
        "survival_uri is required for plot_type = 'kaplan_meier'.")))
    }
    survival_path <- tryCatch(fetch_to_tempfile(survival_uri), error = function(e) e)
    if (inherits(survival_path, "error")) {
      return(fail(mcp_tool_error(paste("Failed to fetch survival_uri:",
                                        conditionMessage(survival_path)))))
    }
    tmp_files[[length(tmp_files) + 1L]] <- survival_path
    sr <- validate_survival_table(survival_path)
    if (!sr$valid) {
      return(fail(mcp_tool_error(sr$issues, expected_format = .SURVIVAL_FORMAT)))
    }
  } else {
    if (length(omics_uris) < 1L) {
      return(fail(mcp_tool_error(
        "omics_uris is required for plot_type = 'silhouette' (the layers used for subtyping).")))
    }
    for (i in seq_along(omics_uris)) {
      tmp <- tryCatch(fetch_to_tempfile(omics_uris[[i]]), error = function(e) e)
      if (inherits(tmp, "error")) {
        return(fail(mcp_tool_error(sprintf(
          "Failed to fetch omics layer %d: %s", i, conditionMessage(tmp)))))
      }
      tmp_files[[length(tmp_files) + 1L]] <- tmp
      vr <- validate_omics_matrix(tmp)
      if (!vr$valid) {
        return(fail(mcp_tool_error(
          c(sprintf("Omics layer %d is invalid:", i), vr$issues),
          expected_format = .OMICS_FORMAT)))
      }
      omics_paths <- c(omics_paths, tmp)
    }
  }

  run <- make_run_dir()
  base_name <- "plot_subtypes"
  png_path <- file.path(run$dir, "plot.png")
  png_url  <- paste0(base_url(), "/results/", run$run_id, "/plot.png")

  job <- make_job_script(run$dir, base_name, "plot_subtypes", list(
    clusters_path = tmp_clusters,
    survival_path = survival_path,
    omics_paths   = as.list(omics_paths),
    plot_type     = plot_type,
    png_path      = png_path
  ))

  list(
    error = NULL,
    script_path = job$script_path,
    job_name = base_name,
    png_path = png_path,
    png_url = png_url,
    plot_type = plot_type,
    run_id = run$run_id,
    tmp_files = tmp_files
  )
}

plot_build_response <- function(job_result, prep) {
  if (!job_result$success) {
    return(mcp_tool_error(paste("Plotting failed:", job_result$stderr)))
  }
  if (!file.exists(prep$png_path)) {
    return(mcp_tool_error(paste(
      "Plotting produced no PNG. stderr:", job_result$stderr)))
  }
  metadata_json <- jsonlite::toJSON(list(
    result_type = "dscc_plot",
    plot_type   = prep$plot_type,
    run_id      = prep$run_id
  ), auto_unbox = TRUE)
  list(
    content = list(
      mcpserver::response_text(metadata_json),
      mcpserver::response_resource_link(
        uri = prep$png_url,
        name = "plot.png",
        mime_type = "image/png")
    ),
    isError = FALSE
  )
}
