#' Build the DSCC MCP server
#'
#' Constructs an mcpserver McpServer with the four DSCC tools registered
#' (validate_input_file, run_dscc_subtyping, evaluate_subtyping,
#' plot_subtypes). The returned object can be passed to
#' mcpserver::serve_http or used directly with mcpserver::route_message
#' for testing.
#'
#' @return An McpServer object.
#' @export
build_dscc_server <- function() {
  srv <- mcpserver::new_server(
    name = "dscc-mcpserver",
    title = "DSCC Cancer Subtyping MCP Server",
    version = utils::packageVersion("dscc.mcpserver"),
    instructions = paste(
      "This server exposes the DSCC multi-omics cancer subtyping method.",
      "Typical workflow: validate each omics matrix and the survival table",
      "with validate_input_file, then run_dscc_subtyping to assign subtypes,",
      "then evaluate_subtyping and plot_subtypes to assess prognostic value.",
      "All *_uri parameters must be URLs from your platform - do not",
      "construct or modify them."),
    description = "DSCC subtyping workflows as MCP tools.",
    website_url = "https://github.com/tinnlab"
  )
  mcpserver::add_capability(srv, tool_validate_input_file())
  mcpserver::add_capability(srv, tool_run_dscc_subtyping())
  mcpserver::add_capability(srv, tool_evaluate_subtyping())
  mcpserver::add_capability(srv, tool_plot_subtypes())
  srv
}
