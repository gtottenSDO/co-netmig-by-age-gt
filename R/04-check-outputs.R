# Check that nothing committed for publication carries restricted data.
#
# The public pipeline (R/01-R/03) reads only public inputs, and county deaths
# by age are estimated, so this guards against a later change reintroducing
# something restricted. It fails if:
#
#   - any CSV in output/ has a column whose name contains "death" or "birth"
#     with a value for any area other than the state (08000)
#   - any CSV in output/ or data/ has a column whose name points to recorded
#     vital counts or calibration against them (cdphe, observed, recorded,
#     uncal, _cal)
#   - any CSV in data/ is not on the vetted list below. data/ holds inputs that
#     may be derived from restricted records at statewide or summary level, so
#     each file is admitted only after someone has checked it.
#   - the validation summary carries a maximum, which would narrow a recorded
#     count to two values
#
# Run after R/02 and before committing.

library(tidyverse)

proj_dir <- here::here()

# Files in data/ that may be published, and why.
vetted_data <- tibble::tribble(
  ~file                              , ~reason                                                  ,
  "county-mortality-ratios-2025.csv" , "county figures copied from CDPHE's public 2025 reports" ,
  "modelled-deaths-validation.csv"   , "medians and 90th percentiles only; no cells or maxima"
)

files <- tibble::tibble(
  path = c(
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
) |>
  dplyr::mutate(
    file = basename(path),
    folder = basename(dirname(path))
  ) |>
  dplyr::left_join(vetted_data, by = "file")

findings <- purrr::pmap(files, \(path, file, folder, reason) {
  df <- readr::read_csv(
    path,
    show_col_types = FALSE,
    col_types = readr::cols(.default = "c")
  )

  vital_cols <- stringr::str_subset(names(df), "(?i)death|birth")
  county_vitals <- folder == "output" &&
    "countyfips" %in% names(df) &&
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
  if (file == "modelled-deaths-validation.csv") {
    suspect_cols <- c(suspect_cols, stringr::str_subset(names(df), "(?i)max"))
  }

  tibble::tibble(
    folder,
    file,
    rows = nrow(df),
    county_vitals,
    suspect_cols = paste(suspect_cols, collapse = ", "),
    unvetted = folder == "data" && is.na(reason)
  )
}) |>
  purrr::list_rbind()

print(findings, n = 50)

bad <- findings |> dplyr::filter(county_vitals | suspect_cols != "" | unvetted)

if (nrow(bad) > 0) {
  stop(
    "Restricted-looking or unvetted content in: ",
    paste(bad$file, collapse = ", "),
    call. = FALSE
  )
}

cat(
  "\nNo county birth or death counts, no recorded-count columns, no unvetted data files.\n"
)
