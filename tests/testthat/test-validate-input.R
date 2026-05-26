test_that("validate_input_file_handler validates an omics matrix", {
  ctx <- build_mock_ctx()
  res <- validate_input_file_handler(
    list(file_uri = file_uri(fixture_path("omics1.csv")),
         file_type = "omics_matrix"), ctx)
  expect_false(is_tool_error(res))
  txt <- res$text
  expect_match(txt, '"valid":true')
  expect_match(txt, '"n_features":50')
  expect_match(txt, '"n_samples":30')
})

test_that("validate_input_file_handler validates a survival table", {
  ctx <- build_mock_ctx()
  res <- validate_input_file_handler(
    list(file_uri = file_uri(fixture_path("survival.csv")),
         file_type = "survival"), ctx)
  expect_false(is_tool_error(res))
  txt <- res$text
  expect_match(txt, '"valid":true')
  expect_match(txt, '"file_type":"survival"')
  expect_match(txt, '"preview"')
})

test_that("validate_input_file_handler errors on empty file_uri", {
  res <- validate_input_file_handler(
    list(file_uri = "", file_type = "omics_matrix"), build_mock_ctx())
  expect_true(is_tool_error(res))
  expect_match(error_text(res), "file_uri is required")
})

test_that("validate_input_file_handler errors on a bad file_type", {
  res <- validate_input_file_handler(
    list(file_uri = file_uri(fixture_path("omics1.csv")),
         file_type = "nonsense"), build_mock_ctx())
  expect_true(is_tool_error(res))
  expect_match(error_text(res), "file_type must be")
})
