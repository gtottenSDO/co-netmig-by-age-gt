# Sum the annual single-year results (R/01) into periods and age groups, and
# write everything the site publishes.
#
# A one-year cohort that ends estimate year t at age a is (end - t) years older
# at the end of a period, so its annual rows add up to its net migration over
# the period. Rows are then gathered by age at the END of the period, in two
# groupings: eighteen five-year groups (0-4 ... 85+) and five broad groups
# (0-17, 18-24, 25-44, 45-64, 65+).
#
# Rates are annual net migration per 1,000 of the group's average population,
# where average population is person-years divided by the period's length. A
# group born during the period grows into it, and person-years count that
# correctly.
#
# Outputs (output/, committed):
#   netmig-comparison.csv            period x grouping x area x sex x age group
#   netmig-annual-sya-2020-2025.csv  annual single-year rows for the dashboard's
#                                    custom-span page
#   co-netmig-by-age-wide.csv        county x five-year group, 2020-2025
#   sdo-published-netmig-by-age.csv  SDO's earlier published figures, reference

library(tidyverse)

proj_dir <- here::here()
in_dir <- file.path(proj_dir, "output-internal")
out_dir <- file.path(proj_dir, "output")
max_age <- 90L

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

annual <- readr::read_csv(
  file.path(in_dir, "netmig-annual-sya-1990-2025.csv"),
  col_types = readr::cols(countyfips = "c", county = "c", .default = "d")
) |>
  dplyr::mutate(dplyr::across(c(sex, year, age_end), as.integer))

periods <- tibble::tribble(
  ~period     , ~start_year , ~end_year ,
  "1990-2000" , 1990L       , 2000L     ,
  "2000-2010" , 2000L       , 2010L     ,
  "2010-2020" , 2010L       , 2020L     ,
  "2020-2025" , 2020L       , 2025L
) |>
  dplyr::mutate(years = end_year - start_year)

# Lower bound of each age group; a group runs to the next lower bound.
age_groups <- dplyr::bind_rows(
  tibble::tibble(grouping = "five", age_lo = seq(0L, 85L, by = 5L)) |>
    dplyr::mutate(
      age_group = dplyr::if_else(
        age_lo == 85L,
        "85+",
        paste0(age_lo, "-", age_lo + 4L)
      )
    ),
  tibble::tibble(
    grouping = "broad",
    age_lo = c(0L, 18L, 25L, 45L, 65L),
    age_group = c("0-17", "18-24", "25-44", "45-64", "65+")
  )
) |>
  dplyr::mutate(age_order = dplyr::row_number(), .by = grouping)

# The territory that became Broomfield County was moved out of Adams, Boulder,
# Jefferson and Weld in estimate year 2000, and SDO's estimates record the move
# as net migration. Owner, 2026-11-23: "just mark the caveat when including
# them".
boundary_caveat <- tibble::tibble(
  countyfips = c("08001", "08013", "08014", "08059", "08123"),
  caveat = paste(
    "Includes the 2000 transfer of territory to the new Broomfield County,",
    "which the population estimates record as migration."
  )
)

# ---- Periods by age group ---------------------------------------------------

# Each annual row is placed in its period and given its age at the period's end.
in_period <- annual |>
  dplyr::inner_join(
    periods,
    by = dplyr::join_by(year > start_year, year <= end_year)
  ) |>
  dplyr::mutate(age_at_end = pmin(age_end + (end_year - year), max_age))

# Both groupings, by rolling each age back to the nearest group lower bound.
grouped <- dplyr::cross_join(
  in_period,
  tibble::tibble(grouping = c("five", "broad"))
) |>
  dplyr::left_join(
    age_groups,
    by = dplyr::join_by(grouping, closest(age_at_end >= age_lo))
  )

group_keys <- c(
  "period",
  "years",
  "grouping",
  "countyfips",
  "county",
  "sex",
  "age_group",
  "age_order"
)

# Population at the two ends of the period, for the same people: the start
# population comes from the first year's rows, the end from the last year's.
pop_start_by_group <- grouped |>
  dplyr::filter(year == start_year + 1L) |>
  dplyr::summarise(pop_start = sum(pop_start), .by = dplyr::all_of(group_keys))

pop_end_by_group <- grouped |>
  dplyr::filter(year == end_year) |>
  dplyr::summarise(pop_end = sum(pop_end), .by = dplyr::all_of(group_keys))

by_sex <- grouped |>
  dplyr::summarise(
    person_years = sum(person_years),
    births = sum(births),
    deaths = sum(deaths),
    netmig = sum(netmig),
    .by = dplyr::all_of(group_keys)
  ) |>
  dplyr::left_join(pop_start_by_group, by = group_keys) |>
  dplyr::left_join(pop_end_by_group, by = group_keys) |>
  dplyr::mutate(dplyr::across(c(pop_start, pop_end), \(x) {
    tidyr::replace_na(x, 0)
  }))

comparison <- by_sex |>
  dplyr::bind_rows(
    by_sex |>
      dplyr::summarise(
        dplyr::across(
          c(person_years, births, deaths, netmig, pop_start, pop_end),
          sum
        ),
        .by = c(
          period,
          years,
          grouping,
          countyfips,
          county,
          age_group,
          age_order
        )
      ) |>
      dplyr::mutate(sex = 0L)
  ) |>
  dplyr::left_join(boundary_caveat, by = "countyfips") |>
  dplyr::mutate(
    sex_label = dplyr::case_when(
      sex == 1L ~ "Male",
      sex == 2L ~ "Female",
      .default = "Total"
    ),
    caveat = dplyr::if_else(period == "1990-2000", caveat, NA_character_),
    mean_pop = person_years / years,
    netmig_annual = netmig / years,
    rate_per_1000 = dplyr::if_else(
      mean_pop > 0,
      netmig_annual / mean_pop * 1000,
      NA_real_
    ),
    # Births and deaths are published for the state only. County figures are
    # modelled (R/01) and are not meant to be read as recorded counts.
    dplyr::across(
      c(births, deaths),
      \(x) dplyr::if_else(countyfips == "08000", x, NA_real_)
    )
  ) |>
  dplyr::arrange(grouping, countyfips, period, sex, age_order) |>
  dplyr::transmute(
    period,
    years,
    grouping,
    countyfips,
    county,
    sex,
    sex_label,
    age_group,
    age_order,
    pop_start = round(pop_start),
    pop_end = round(pop_end),
    mean_pop = round(mean_pop, 1),
    births = round(births, 1),
    deaths = round(deaths, 1),
    netmig = round(netmig, 1),
    netmig_annual = round(netmig_annual, 1),
    rate_per_1000 = round(rate_per_1000, 2),
    caveat
  )

stopifnot(!any(is.na(comparison$age_group)))

readr::write_csv(
  comparison,
  file.path(out_dir, "netmig-comparison.csv"),
  na = ""
)

# ---- Annual rows for the custom-span page -----------------------------------

annual |>
  dplyr::filter(year > 2020L) |>
  dplyr::transmute(
    countyfips,
    sex,
    year,
    age_end,
    pop_start,
    pop_end,
    person_years = round(person_years, 1),
    netmig = round(netmig, 1)
  ) |>
  readr::write_csv(file.path(out_dir, "netmig-annual-sya-2020-2025.csv"))

# ---- County x age grid, 2020-2025 -------------------------------------------

comparison |>
  dplyr::filter(period == "2020-2025", grouping == "five", sex == 0L) |>
  dplyr::select(countyfips, county, age_order, age_group, netmig) |>
  dplyr::arrange(age_order) |>
  dplyr::select(-age_order) |>
  tidyr::pivot_wider(names_from = age_group, values_from = netmig) |>
  dplyr::mutate(
    Total = rowSums(dplyr::across(dplyr::where(is.numeric))),
    .after = county
  ) |>
  dplyr::mutate(dplyr::across(dplyr::where(is.numeric), round)) |>
  readr::write_csv(file.path(out_dir, "co-netmig-by-age-wide.csv"))

# ---- SDO's earlier published figures, for reference -------------------------

# data.netmigrbyage is SDO's existing net migration by age. Its level and rate
# columns are not consistent with each other, so it is used as a control
# nowhere.
db <- sdotools::sdo_db_connect(public = TRUE)
withr::defer(DBI::dbDisconnect(db))

dplyr::tbl(db, dbplyr::in_schema("data", "netmigrbyage")) |>
  dplyr::select(
    fips,
    county,
    agegroup,
    netmig9500,
    rate9500,
    netmig0010,
    rate0010,
    netmig1020,
    rate1020
  ) |>
  dplyr::collect() |>
  dplyr::mutate(
    countyfips = sprintf("08%03d", as.integer(fips)),
    agegroup = as.integer(agegroup),
    dplyr::across(dplyr::starts_with(c("netmig", "rate")), as.numeric)
  ) |>
  readr::write_csv(file.path(out_dir, "sdo-published-netmig-by-age.csv"))

# ---- Report -----------------------------------------------------------------

cat("\n--- Groups per period and grouping (18 and 5) ---\n")
comparison |>
  dplyr::summarise(
    n = dplyr::n_distinct(age_group),
    .by = c(period, grouping)
  ) |>
  print()

cat("\n--- Colorado, broad groups, annual rate per 1,000 ---\n")
comparison |>
  dplyr::filter(countyfips == "08000", sex == 0L, grouping == "broad") |>
  dplyr::select(period, age_group, rate_per_1000) |>
  tidyr::pivot_wider(names_from = period, values_from = rate_per_1000) |>
  print()

cat("\n--- Colorado totals by period ---\n")
comparison |>
  dplyr::filter(countyfips == "08000", sex == 0L, grouping == "five") |>
  dplyr::summarise(netmig = sum(netmig), .by = period) |>
  print()
