#!/usr/bin/env Rscript
## Launch dscc.mcpserver over stdio (newline-delimited JSON-RPC on stdin/stdout).
##
## Env vars: DSCC_RESULTS_MODE (file|http, default file), DSCC_DAEMONS,
##   DSCC_RESULTS_DIR, DSCC_LOG, and (when DSCC_RESULTS_MODE=http) DSCC_STATIC_PORT,
##   DSCC_STATIC_HOST, BASE_URL.
##
## stdout is reserved for the MCP protocol; diagnostics go to stderr (or DSCC_LOG).

tryCatch({
  suppressPackageStartupMessages(library(dscc.mcpserver))
  start_stdio_server()
}, error = function(e) {
  message("run-stdio.R fatal: ", conditionMessage(e))
  quit(status = 1L, save = "no")
})
