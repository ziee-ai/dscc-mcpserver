library(testthat)
library(dscc.mcpserver)

# Tests use file:// URIs against fixture CSVs - turn on the explicit
# local-URI opt-in. Production code paths still require http(s) by default.
Sys.setenv(DSCC_ALLOW_LOCAL_URIS = "TRUE")

test_check("dscc.mcpserver")
