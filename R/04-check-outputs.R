# Check that nothing committed for publication carries restricted data.
#
# The public pipeline (R/01-R/03) reads only public inputs, and county deaths
# by age are modelled, so this is a guard against a later change reintroducing
# something restricted. It fails if any committed CSV in output/ or data/:
#
#   - has births or deaths for any area other than the state (08000)
#   - has a column whose name points to recorded vital counts or calibration
#     against them (cdphe, observed, recorded, uncal, _cal)
#
# Run after R/02 and before committing.

library(tidyverse)

proj_dir <- here::here()

files <- c(
  list.files(
    file.path(proj_dir, "output"),
    pattern = "\\.csv$",
    full.names = TRUE
  ),
  list.files(
    file.path(proj_dir, "data"),
    pattern = "\\.csv$",
    full.names = TRUE
  )
)

findings <- purrr::map(files, \(f) {
  df <- readr::read_csv(
    f,
    show_col_types = FALSE,
    col_types = readr::cols(.default = "c")
  )
  vital_cols <- intersect(c("births", "deaths"), names(df))
  county_vitals <- "countyfips" %in%
    names(df) &&
    length(vital_cols) > 0 &&
    nrow(dplyr::filter(
      df,
      countyfips != "08000",
      dplyr::if_any(dplyr::all_of(vital_cols), \(x) !is.na(x) & x != "")
    )) >
      0
  suspect_cols <- stringr::str_subset(
    names(df),
    "(?i)cdphe|observed|recorded|uncal|_cal$"
  )
  tibble::tibble(
    file = basename(f),
    rows = nrow(df),
    county_vitals,
    suspect_cols = paste(suspect_cols, collapse = ", ")
  )
}) |>
  purrr::list_rbind()

print(findings, n = 50)

bad <- findings |> dplyr::filter(county_vitals | suspect_cols != "")

if (nrow(bad) > 0) {
  stop(
    "Restricted-looking content in: ",
    paste(bad$file, collapse = ", "),
    call. = FALSE
  )
}

cat("\nNo county-level birth or death counts and no recorded-count columns.\n")
