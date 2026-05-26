test_that("build_dscc_server registers the 4 DSCC tools", {
  srv <- build_dscc_server()
  tool_names <- ls(srv$tools, all.names = TRUE)
  expect_setequal(
    tool_names,
    c("validate_input_file", "run_dscc_subtyping",
      "evaluate_subtyping", "plot_subtypes")
  )
})

test_that("each registered tool has a valid input_schema", {
  srv <- build_dscc_server()
  for (n in ls(srv$tools)) {
    t <- get(n, envir = srv$tools)
    expect_true(is.list(t$input_schema), info = n)
    expect_equal(t$input_schema$type, "object", info = n)
  }
})

test_that("the three analysis tools are bidirectional; validate is not", {
  srv <- build_dscc_server()
  expect_true(get("run_dscc_subtyping", envir = srv$tools)$bidirectional)
  expect_true(get("evaluate_subtyping", envir = srv$tools)$bidirectional)
  expect_true(get("plot_subtypes", envir = srv$tools)$bidirectional)
  expect_false(isTRUE(get("validate_input_file", envir = srv$tools)$bidirectional))
})

test_that("server advertises only the tool capability", {
  srv <- build_dscc_server()
  caps <- srv$capabilities()
  expect_false(is.null(caps$tools))
  expect_null(caps$resources)
  expect_null(caps$prompts)
})

test_that("tools declare openWorldHint (they fetch remote files)", {
  srv <- build_dscc_server()
  for (n in c("validate_input_file", "run_dscc_subtyping",
              "evaluate_subtyping", "plot_subtypes")) {
    t <- get(n, envir = srv$tools)
    expect_true(isTRUE(t$annotations$openWorldHint), info = n)
  }
})
