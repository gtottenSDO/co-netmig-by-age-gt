# Read SDO population and components of change from the State Demography
# Office's public lookups service, which serves the same tables as the office's
# database (estimates.county_sya and estimates.components_change) to anyone,
# with no account. The service is the ColoradoDemography/MS_Demog_Lookups
# project on GitHub.
#
# Sourced by R/01 and R/03, after R/00 has downloaded the Census files.

sdo_lookups_url <- "https://gis.dola.colorado.gov/lookups"

# Colorado county FIPS codes, taken from the Census county file that R/00
# downloads. The SDO crosswalk (sdotools::sdo_xwalk_get()) is the usual source,
# but sdotools is a private package and this repository must run without it.
sdo_county_codes <- readr::read_csv(
  here::here("data-raw", "census", "co-est2025-alldata.csv"),
  col_types = readr::cols(.default = "c")
) |>
  dplyr::filter(STATE == "08", SUMLEV == "050") |>
  dplyr::pull(COUNTY) |>
  as.integer() |>
  sort()

stopifnot(length(sdo_county_codes) == 64)

#' Read one lookups-service request, retrying on failure
#'
#' A brief outage or an empty answer would otherwise stop the build far from
#' its cause. Each request is tried up to `tries` times, waiting longer each
#' time, and the answer must be a non-empty table with the expected columns.
#'
#' @param url Full request URL.
#' @param columns Column names the answer must contain.
#' @param tries Number of attempts.
#' @return A tibble.
sdo_lookup <- function(url, columns, tries = 4) {
  for (attempt in seq_len(tries)) {
    result <- tryCatch(jsonlite::fromJSON(url), error = \(e) e)
    ok <- is.data.frame(result) &&
      nrow(result) > 0 &&
      all(columns %in% names(result))
    if (ok) {
      return(tibble::as_tibble(result))
    }
    if (attempt < tries) Sys.sleep(2^attempt)
  }
  reason <- if (inherits(result, "error")) {
    conditionMessage(result)
  } else {
    "an empty or unexpected answer"
  }
  stop(
    "SDO lookups request failed after ",
    tries,
    " attempts (",
    reason,
    "): ",
    url,
    call. = FALSE
  )
}

#' Population by county, year, sex and single year of age
#'
#' One request per county keeps each response under about 1 MB.
#'
#' @param years Integer vector of July 1 estimate years.
#' @return A tibble of countyfips (integer), county, year, age, malepopulation,
#'   femalepopulation, datatype.
sdo_get_sya <- function(years) {
  purrr::map(sdo_county_codes, \(code) {
    sdo_lookup(
      paste0(
        sdo_lookups_url,
        "/sya?choice=single",
        "&county=",
        code,
        "&year=",
        paste(years, collapse = ","),
        "&age=",
        paste(0:100, collapse = ",")
      ),
      columns = c(
        "countyfips",
        "year",
        "age",
        "malepopulation",
        "femalepopulation"
      )
    )
  }) |>
    purrr::list_rbind() |>
    dplyr::transmute(
      countyfips = as.integer(countyfips),
      county,
      year = as.integer(year),
      age = as.integer(age),
      malepopulation = as.numeric(malepopulation),
      femalepopulation = as.numeric(femalepopulation),
      datatype
    )
}

#' Births, deaths and net migration by county and year
#'
#' @param years Integer vector of estimate years (each July to July).
#' @param counties Integer county codes; 0 is the state.
#' @return A tibble of countyfips, year, births, deaths, netmig, datatype.
sdo_get_components <- function(years, counties = sdo_county_codes) {
  sdo_lookup(
    paste0(
      sdo_lookups_url,
      "/components?county=",
      paste(counties, collapse = ","),
      "&year=",
      paste(years, collapse = ",")
    ),
    columns = c("countyfips", "year", "births", "deaths", "netmig")
  ) |>
    dplyr::transmute(
      countyfips = as.integer(countyfips),
      year = as.integer(year),
      births = as.numeric(births),
      deaths = as.numeric(deaths),
      netmig = as.numeric(netmig),
      datatype
    )
}
