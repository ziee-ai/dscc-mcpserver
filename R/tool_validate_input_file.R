.OMICS_FORMAT <- paste(
  "CSV or TSV, features x samples.",
  "Row 1 = column headers (first cell = a feature-ID label or empty,",
  "remaining cells = sample names).",
  "Rows 2+ = one feature per row (feature ID in column 1, numeric values",
  "in the remaining columns). No duplicate feature IDs. NA values are",
  "allowed (they are treated as 0 during subtyping).")

.SURVIVAL_FORMAT <- paste(
  "CSV or TSV, one row per sample. Required columns: a sample identifier",
  "(a 'sample' column, or the first column), 'os' (overall-survival time,",
  "numeric, >= 0), and 'isDead' (event indicator: 1 = death/event,",
  "0 = censored). No duplicate sample names.")

tool_validate_input_file <- function() {
  mcpserver::new_tool(
    name = "validate_input_file",
    description = paste(
      "Validate a DSCC input file from a URL: either an omics matrix",
      "(features x samples) or a survival table (sample / os / isDead).",
      "Returns whether the file is valid, any issues found, sample names",
      "and feature/sample counts (omics) or sample/event counts (survival),",
      "plus a small preview. Always call this first, once per omics layer",
      "and once for the survival table, before running any analysis."),
    input_schema = mcpserver::schema(list(
      file_uri = mcpserver::property_string(
        description = paste(
          "URL to the CSV/TSV file to validate.",
          "Pass the URL exactly as provided."),
        required = TRUE),
      file_type = mcpserver::property_enum(
        values = c("omics_matrix", "survival"),
        description = paste(
          "Type of file to validate:",
          "'omics_matrix' (features x samples numeric matrix) or",
          "'survival' (sample / os / isDead table)."),
        required = TRUE)
    )),
    annotations = list(
      readOnlyHint = TRUE,
      destructiveHint = FALSE,
      idempotentHint = TRUE,
      openWorldHint = TRUE,
      title = "Validate Input File"
    ),
    handler = validate_input_file_handler
  )
}

validate_input_file_handler <- function(args, ctx) {
  file_uri  <- trimws(args$file_uri  %||% "")
  file_type <- trimws(args$file_type %||% "")

  if (!nzchar(file_uri)) {
    return(mcp_tool_error(
      "file_uri is required - provide a download URL, not a local file path"))
  }
  if (!file_type %in% c("omics_matrix", "survival")) {
    return(mcp_tool_error(sprintf(
      "file_type must be 'omics_matrix' or 'survival'. Got: '%s'",
      file_type)))
  }

  tmp_path <- tryCatch(fetch_to_tempfile(file_uri),
                       error = function(e) e)
  if (inherits(tmp_path, "error")) {
    return(mcp_tool_error(
      paste("Failed to fetch file:", conditionMessage(tmp_path))))
  }
  on.exit(unlink(tmp_path), add = TRUE)

  switch(file_type,
    "omics_matrix" = validate_omics_response(validate_omics_matrix(tmp_path)),
    "survival"     = validate_survival_response(validate_survival_table(tmp_path))
  )
}

validate_omics_response <- function(result) {
  if (!result$valid) {
    return(mcp_tool_error(
      result$issues,
      expected_format = .OMICS_FORMAT,
      hint = "Fix the issues above, re-upload, and retry with the new URI."))
  }
  mcpserver::response_text(jsonlite::toJSON(list(
    valid        = TRUE,
    file_type    = "omics_matrix",
    n_features   = result$n_features,
    n_samples    = result$n_samples,
    sample_names = result$sample_names,
    preview      = result$preview
  ), auto_unbox = TRUE))
}

validate_survival_response <- function(result) {
  if (!result$valid) {
    return(mcp_tool_error(
      result$issues,
      expected_format = .SURVIVAL_FORMAT,
      hint = "Fix the issues above, re-upload, and retry with the new URI."))
  }
  mcpserver::response_text(jsonlite::toJSON(list(
    valid        = TRUE,
    file_type    = "survival",
    n_samples    = result$n_samples,
    n_events     = result$n_events,
    sample_names = result$sample_names,
    preview      = result$preview
  ), auto_unbox = TRUE))
}
