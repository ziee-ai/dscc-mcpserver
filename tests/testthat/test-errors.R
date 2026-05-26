test_that("mcp_tool_error returns an isError result with the message text", {
  err <- mcp_tool_error("something went wrong")
  expect_true(is_tool_error(err))
  expect_match(error_text(err), "something went wrong")
})

test_that("mcp_tool_error appends detail fields", {
  err <- mcp_tool_error("bad input", hint = "fix it", expected_format = "CSV")
  txt <- error_text(err)
  expect_match(txt, "bad input")
  expect_match(txt, "hint: fix it")
  expect_match(txt, "expected_format: CSV")
})

test_that("is_tool_error only matches isError lists", {
  expect_false(is_tool_error(list(isError = FALSE)))
  expect_false(is_tool_error("nope"))
  expect_true(is_tool_error(list(isError = TRUE)))
})

test_that("is_path validates single non-empty character paths", {
  expect_true(is_path("/tmp/x"))
  expect_false(is_path(""))
  expect_false(is_path(NULL))
  expect_false(is_path(c("a", "b")))
  expect_false(is_path(simpleError("boom")))
})

test_that("safe_unlink_all removes only real files and ignores junk", {
  f <- tempfile(); writeLines("x", f)
  expect_true(file.exists(f))
  safe_unlink_all(list(f, NULL, simpleError("e"), "/nonexistent/path"))
  expect_false(file.exists(f))
})
