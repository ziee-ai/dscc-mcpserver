#!/usr/bin/env Rscript
## Launch dscc.mcpserver over Streamable HTTP.
##
## Standard env vars: DSCC_PORT, DSCC_HOST, DSCC_STATIC_PORT,
##   DSCC_STATIC_HOST, DSCC_DAEMONS, DSCC_RESULTS_DIR, BASE_URL, DSCC_LOG.
##
## Optional auth (handled by R/auth_config.R; defaults to off):
##   DSCC_AUTH=on              enable JWT auth + admin REST + admin SPA
##   MCPSERVER_ADMIN_TOKEN     bootstrap admin token (auto-generated if unset)
##   DSCC_AUTH_DB              SQLite path (default <results_dir>/auth.db)
##   DSCC_AUTH_ISSUER          JWT iss claim (default http://127.0.0.1:<port>)
##   DSCC_AUTH_AUDIENCE        JWT aud claim (default "dscc")
##   DSCC_AUTH_UI              "off" to hide the bundled /admin/ui SPA

log_path <- Sys.getenv("DSCC_LOG", unset = "")
if (nzchar(log_path)) {
  sink(file(log_path, open = "a"), type = "message")
}

tryCatch({
  suppressPackageStartupMessages(library(dscc.mcpserver))
  args <- commandArgs(trailingOnly = TRUE)
  port <- as.integer(Sys.getenv("DSCC_PORT", unset = "9006"))
  i <- match("--port", args)
  if (!is.na(i) && i < length(args)) port <- as.integer(args[[i + 1L]])
  run_http_entrypoint(port = port)
}, error = function(e) {
  message("run-http.R fatal: ", conditionMessage(e))
  quit(status = 1L, save = "no")
})
