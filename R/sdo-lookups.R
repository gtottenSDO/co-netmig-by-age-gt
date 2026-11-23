# Read SDO population and components of change from the State Demography
# Office's public lookups service, which serves the same tables as the office's
# database (estimates.county_sya and estimates.components_change) to anyone,
# with no account. The service is the ColoradoDemography/MS_Demog_Lookups
# project on GitHub.
#
# Sourced by R/01 and R/03.

sdo_lookups_url <- "https://gis.dola.colorado.gov/lookups"

# Colorado county FIPS codes: the odd numbers 1-125 and Broomfield (14).
sdo_county_codes <- sort(c(seq(1L, 125L, by = 2L), 14L))

#' Population by county, year, sex and single year of age
#'
#' One request per county keeps each response under about 1 MB.
#'
#' @param years Integer vector of July 1 estimate years.
#' @return A tibble of countyfips (integer), county, year, age, malepopulation,
#'   femalepopulation, datatype.
sdo_get_sya <- function(years) {
  purrr::map(sdo_county_codes, \(code) {
    url <- paste0(
      sdo_lookups_url,
      "/sya?choice=single",
      "&county=",
      code,
      "&year=",
      paste(years, collapse = ","),
      "&age=",
      paste(0:100, collapse = ",")
    )
    jsonlite::fromJSON(url) |> tibble::as_tibble()
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
  url <- paste0(
    sdo_lookups_url,
    "/components?county=",
    paste(counties, collapse = ","),
    "&year=",
    paste(years, collapse = ",")
  )
  jsonlite::fromJSON(url) |>
    tibble::as_tibble() |>
    dplyr::transmute(
      countyfips = as.integer(countyfips),
      year = as.integer(year),
      births = as.numeric(births),
      deaths = as.numeric(deaths),
      netmig = as.numeric(netmig),
      datatype
    )
}
