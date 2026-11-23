# Compare the SDO population estimates with the Census Bureau's Population
# Estimates Program (PEP, vintage 2025), Colorado and counties, 2020-2025.
#
# From 2026-11-23 the 2020-2025 build reads population from the SDO
# single-year-of-age table (estimates.county_sya) instead of the Census age/sex
# file, because only single years of age support spans shorter than five years
# and age groups such as 18-24. This script measures how far the two sources
# differ, so the change in the published figures can be explained:
#
#   1. total population by county and year
#   2. population by five-year age group and sex, by county and year
#   3. births, deaths and net migration by county and year
#
# Census net migration is compared as NETMIG + RESIDUAL, because the Bureau's
# identity carries a residual term that SDO folds into net migration.

library(tidyverse)

proj_dir <- here::here()
raw_dir <- file.path(proj_dir, "data-raw")
out_dir <- file.path(proj_dir, "output-internal") # check results, not committed

years <- 2020:2025

# data-raw/ is not committed, so the two Census files are fetched on first run.
census_url <- "https://www2.census.gov/programs-surveys/popest/datasets/2020-2025/counties"
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
purrr::walk2(
  c("asrh/cc-est2025-agesex-08.csv", "totals/co-est2025-alldata.csv"),
  c("cc-est2025-agesex-08.csv", "co-est2025-alldata.csv"),
  \(remote, local) {
    dest <- file.path(raw_dir, local)
    if (!file.exists(dest)) {
      download.file(
        file.path(census_url, remote),
        dest,
        mode = "wb",
        quiet = TRUE
      )
    }
  }
)

# ---- SDO population and components ------------------------------------------

db <- sdotools::sdo_db_connect(public = TRUE)
withr::defer(DBI::dbDisconnect(db))

# Single-year population, collapsed to the eighteen Census five-year groups
# (85+ open) so the two sources can be compared group by group.
sdo_age <- dplyr::tbl(db, dbplyr::in_schema("estimates", "county_sya")) |>
  dplyr::filter(datatype == "Estimate", year %in% !!years) |>
  dplyr::select(countyfips, year, age, malepopulation, femalepopulation) |>
  dplyr::collect() |>
  tidyr::pivot_longer(
    c(malepopulation, femalepopulation),
    names_to = "sex",
    values_to = "pop"
  ) |>
  dplyr::mutate(
    countyfips = sprintf("08%03d", as.integer(countyfips)),
    year = as.integer(year),
    sex = dplyr::if_else(sex == "malepopulation", "Male", "Female"),
    age_start = pmin(as.integer(age) %/% 5L * 5L, 85L)
  ) |>
  dplyr::summarise(
    sdo_pop = sum(as.numeric(pop)),
    .by = c(countyfips, year, sex, age_start)
  )

# Components by county and estimate year (July to July). The 2020 row is not
# used: it is the year ending 7/1/2020, before the comparison window opens.
sdo_components <- dplyr::tbl(
  db,
  dbplyr::in_schema("estimates", "components_change")
) |>
  dplyr::filter(year %in% !!years[-1]) |>
  dplyr::select(countyfips, year, births, deaths, netmig) |>
  dplyr::collect() |>
  dplyr::mutate(
    countyfips = sprintf("08%03d", as.integer(countyfips)),
    year = as.integer(year),
    dplyr::across(c(births, deaths, netmig), as.numeric)
  )

# ---- Census PEP vintage 2025 ------------------------------------------------

# The eighteen disjoint five-year columns, named explicitly because the file
# also carries overlapping spans (AGE513, AGE1824, ...).
age_group_cols <- tibble::tibble(
  age_start = seq(0L, 85L, by = 5L),
  col = c(
    paste0("AGE", seq(0, 80, by = 5), seq(4, 84, by = 5)),
    "AGE85PLUS"
  )
)

# YEAR 2 is 7/1/2020 and YEAR 7 is 7/1/2025; YEAR 1 (the April 2020 base) is
# dropped. Rows with COUNTY 000 are the state.
pep_age <- readr::read_csv(
  file.path(raw_dir, "cc-est2025-agesex-08.csv"),
  col_types = readr::cols(.default = "c")
) |>
  dplyr::filter(YEAR %in% as.character(2:7)) |>
  dplyr::select(
    COUNTY,
    YEAR,
    dplyr::all_of(paste0(age_group_cols$col, "_MALE")),
    dplyr::all_of(paste0(age_group_cols$col, "_FEM"))
  ) |>
  tidyr::pivot_longer(
    -c(COUNTY, YEAR),
    names_to = c("col", "sex"),
    names_pattern = "^(.*)_(MALE|FEM)$",
    values_to = "pep_pop",
    values_transform = list(pep_pop = as.numeric)
  ) |>
  dplyr::inner_join(age_group_cols, by = "col") |>
  dplyr::transmute(
    countyfips = paste0("08", COUNTY),
    year = as.integer(YEAR) + 2018L,
    sex = dplyr::if_else(sex == "MALE", "Male", "Female"),
    age_start,
    pep_pop
  )

# The age/sex file has county rows only, so the state is their sum. SDO's
# table carries its own state rows (countyfips 0), which are kept as they are.
pep_age <- pep_age |>
  dplyr::bind_rows(
    pep_age |>
      dplyr::summarise(
        pep_pop = sum(pep_pop),
        .by = c(year, sex, age_start)
      ) |>
      dplyr::mutate(countyfips = "08000")
  )

# Census components by county and year, in long form. SUMLEV 040 is the state.
pep_alldata <- readr::read_csv(
  file.path(raw_dir, "co-est2025-alldata.csv"),
  col_types = readr::cols(.default = "c")
) |>
  dplyr::filter(STATE == "08") |>
  dplyr::mutate(countyfips = paste0(STATE, COUNTY), county = CTYNAME) |>
  dplyr::select(
    countyfips,
    county,
    dplyr::matches("^(POPESTIMATE|BIRTHS|DEATHS|NETMIG|RESIDUAL)20(2[0-5])$")
  ) |>
  tidyr::pivot_longer(
    -c(countyfips, county),
    names_to = c(".value", "year"),
    names_pattern = "^([A-Z]+)(\\d{4})$",
    names_transform = list(year = as.integer)
  ) |>
  dplyr::mutate(
    dplyr::across(POPESTIMATE:RESIDUAL, as.numeric),
    county = stringr::str_remove(county, " County$")
  )

county_names <- pep_alldata |> dplyr::distinct(countyfips, county)

# ---- 1. Total population by county and year ---------------------------------

totals <- sdo_age |>
  dplyr::summarise(sdo_pop = sum(sdo_pop), .by = c(countyfips, year)) |>
  dplyr::inner_join(
    pep_alldata |> dplyr::select(countyfips, year, pep_pop = POPESTIMATE),
    by = c("countyfips", "year")
  ) |>
  dplyr::left_join(county_names, by = "countyfips") |>
  dplyr::mutate(diff = sdo_pop - pep_pop, pct_diff = 100 * diff / pep_pop) |>
  dplyr::relocate(county, .after = countyfips)

# ---- 2. Population by age group and sex -------------------------------------

by_age <- sdo_age |>
  dplyr::full_join(pep_age, by = c("countyfips", "year", "sex", "age_start")) |>
  dplyr::left_join(county_names, by = "countyfips") |>
  dplyr::mutate(
    age_group = dplyr::if_else(
      age_start == 85L,
      "85+",
      paste0(age_start, "-", age_start + 4L)
    ),
    diff = sdo_pop - pep_pop,
    pct_diff = dplyr::if_else(pep_pop > 0, 100 * diff / pep_pop, NA_real_)
  ) |>
  dplyr::select(
    countyfips,
    county,
    year,
    sex,
    age_start,
    age_group,
    sdo_pop,
    pep_pop,
    diff,
    pct_diff
  ) |>
  dplyr::arrange(countyfips, year, sex, age_start)

# ---- 3. Components by county and year ---------------------------------------

# SDO stores the state as countyfips 0, which sprintf above turns into 08000,
# the same code the Census file uses for its state row.
components <- sdo_components |>
  dplyr::inner_join(pep_alldata, by = c("countyfips", "year")) |>
  dplyr::transmute(
    countyfips,
    county,
    year,
    sdo_births = births,
    pep_births = BIRTHS,
    sdo_deaths = deaths,
    pep_deaths = DEATHS,
    sdo_netmig = netmig,
    pep_netmig = NETMIG + RESIDUAL
  )

readr::write_csv(totals, file.path(out_dir, "sdo-vs-pep-totals.csv"))
readr::write_csv(by_age, file.path(out_dir, "sdo-vs-pep-by-age.csv"))
readr::write_csv(components, file.path(out_dir, "sdo-vs-pep-components.csv"))

# ---- Report -----------------------------------------------------------------

cat("\n--- Colorado total population, SDO vs PEP ---\n")
totals |>
  dplyr::filter(countyfips == "08000") |>
  dplyr::select(year, sdo_pop, pep_pop, diff, pct_diff) |>
  print()

cat("\n--- Counties: absolute % difference in total population, by year ---\n")
totals |>
  dplyr::filter(countyfips != "08000") |>
  dplyr::summarise(
    median_abs_pct = median(abs(pct_diff)),
    max_abs_pct = max(abs(pct_diff)),
    county_at_max = county[which.max(abs(pct_diff))],
    .by = year
  ) |>
  print()

cat("\n--- Counties more than 0.25% apart in any year, 2020 and 2025 ---\n")
totals |>
  dplyr::filter(countyfips != "08000") |>
  dplyr::filter(any(abs(pct_diff) > 0.25), .by = countyfips) |>
  dplyr::filter(year %in% c(2020L, 2025L)) |>
  dplyr::select(county, year, sdo_pop, pep_pop, diff, pct_diff) |>
  tidyr::pivot_wider(
    names_from = year,
    values_from = c(sdo_pop, pep_pop, diff, pct_diff)
  ) |>
  dplyr::arrange(dplyr::desc(abs(pct_diff_2025))) |>
  print(n = 30, width = Inf)

cat("\n--- Colorado by age group, sexes combined, 2020 and 2025 ---\n")
by_age |>
  dplyr::filter(countyfips == "08000", year %in% c(2020L, 2025L)) |>
  dplyr::summarise(
    dplyr::across(c(sdo_pop, pep_pop, diff), sum),
    .by = c(year, age_start, age_group)
  ) |>
  dplyr::mutate(pct_diff = round(100 * diff / pep_pop, 2)) |>
  dplyr::select(-age_start) |>
  tidyr::pivot_wider(
    names_from = year,
    values_from = c(sdo_pop, pep_pop, diff, pct_diff)
  ) |>
  print(n = 20, width = Inf)

cat("\n--- Counties: share of age-sex cells by size of difference ---\n")
by_age |>
  dplyr::filter(countyfips != "08000") |>
  dplyr::mutate(
    band = dplyr::case_when(
      abs(diff) <= 10 ~ "within 10 people",
      abs(diff) <= 100 ~ "11-100",
      abs(diff) <= 1000 ~ "101-1,000",
      .default = "over 1,000"
    )
  ) |>
  dplyr::count(year, band) |>
  tidyr::pivot_wider(names_from = band, values_from = n, values_fill = 0) |>
  print(width = Inf)

cat(
  "\n--- Colorado components, SDO vs PEP (PEP netmig includes residual) ---\n"
)
components |>
  dplyr::filter(countyfips == "08000") |>
  dplyr::select(-countyfips, -county) |>
  print(width = Inf)

cat("\n--- Counties: net migration, 2021-2025 summed ---\n")
components |>
  dplyr::filter(countyfips != "08000") |>
  dplyr::summarise(
    dplyr::across(c(sdo_netmig, pep_netmig), sum),
    .by = c(countyfips, county)
  ) |>
  dplyr::mutate(diff = sdo_netmig - pep_netmig) |>
  dplyr::arrange(dplyr::desc(abs(diff))) |>
  print(n = 10)
