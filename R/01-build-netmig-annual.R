# Net migration by single year of age, Colorado and counties, one estimate year
# at a time, July 1990 to July 2025. Built only from public data.
#
# Method: demographic residual. For the one-year cohort that ends estimate year
# t at age a (it was a - 1 on the July 1 that opened the year):
#
#   NM = Pop_t(a) - Pop_t-1(a - 1) - Births + Deaths
#
# Adding up one cohort's annual residuals gives its residual over any longer
# span exactly, because the intermediate populations cancel. Every period, age
# grouping and custom span in this project is a sum of these rows (R/02).
#
# Inputs, all public:
#   - population: SDO county single-year-of-age estimates, ages 0-90+
#   - county births, deaths and net migration by year: SDO components of change
#     (both from SDO's public lookups service; see R/sdo-lookups.R)
#   - Colorado death rates by sex and single year of age: NCHS life tables,
#     1999-2001 and 2018-2023
#   - each county's own age pattern of deaths: CDPHE's public 2025 county
#     summary reports (Table 11)
#
# County deaths by age are not public. Because population is public, any
# published net migration by age built from recorded deaths would give those
# deaths back (deaths = net migration - population change + births). Deaths
# are therefore modelled: Colorado life-table rates by year, sex and age, times
# the county's mortality ratio for the broad band, times its person-years, scaled
# so each county-year matches its published death total. Owner, 2026-11-23:
# "Modelled from public data", and "we should change the compare to be on the
# same methodology".
#
# Run R/00 first to download the public inputs.
#
# Output: output-internal/netmig-annual-sya-1990-2025.csv (not committed because
# of its size; R/02 publishes what the site needs).

library(tidyverse)

proj_dir <- here::here()
data_dir <- file.path(proj_dir, "data")
reports_dir <- file.path(proj_dir, "data-raw", "cdphe-county-reports-2025")
life_tables_dir <- file.path(proj_dir, "data-raw", "nchs-life-tables")
out_dir <- file.path(proj_dir, "output-internal")

first_year <- 1990L
last_year <- 2025L
# SDO's single-year table ends at an open 90+ group before 2010 and at 100+
# from 2010; 90+ is used throughout so every year is on the same ages.
max_age <- 90L
shrink_deaths <- 10 # deaths added to both sides of a county mortality ratio

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- SDO population and components (public lookups service) ----------------

source(file.path(proj_dir, "R", "sdo-lookups.R"))

# Counties only; the state is rebuilt as their sum so it adds up exactly.
pop <- sdo_get_sya(first_year:last_year) |>
  dplyr::filter(datatype == "Estimate") |>
  tidyr::pivot_longer(
    c(malepopulation, femalepopulation),
    names_to = "sex",
    values_to = "pop"
  ) |>
  dplyr::transmute(
    countyfips = sprintf("08%03d", countyfips),
    county = stringr::str_remove(county, " County$"),
    year,
    sex = dplyr::if_else(sex == "malepopulation", 1L, 2L),
    age = pmin(age, max_age),
    pop
  ) |>
  dplyr::summarise(pop = sum(pop), .by = c(countyfips, county, year, sex, age))

county_names <- pop |> dplyr::distinct(countyfips, county)

controls <- sdo_get_components((first_year + 1L):last_year) |>
  dplyr::filter(datatype == "Estimate") |>
  dplyr::transmute(
    countyfips = sprintf("08%03d", countyfips),
    year,
    control_births = births,
    control_deaths = deaths,
    control_netmig = netmig
  )

stopifnot(
  dplyr::n_distinct(pop$countyfips) == 64,
  all(first_year:last_year %in% pop$year)
)
stopifnot(max(pop$age) == max_age)

# ---- Annual population change by single year of age -------------------------

# Each row: the cohort ending estimate year t at age_end. age_end 0 is born
# during the year; age_end 90 gathers everyone 89 and over at the start.
pop_end <- pop |>
  dplyr::filter(year > first_year) |>
  dplyr::rename(age_end = age, pop_end = pop)

pop_start <- pop |>
  dplyr::filter(year < last_year) |>
  dplyr::transmute(
    countyfips,
    sex,
    year = year + 1L,
    age_end = pmin(age + 1L, max_age),
    pop
  ) |>
  dplyr::summarise(
    pop_start = sum(pop),
    .by = c(countyfips, sex, year, age_end)
  )

annual <- pop_end |>
  dplyr::left_join(pop_start, by = c("countyfips", "sex", "year", "age_end")) |>
  dplyr::mutate(
    pop_start = tidyr::replace_na(pop_start, 0),
    # Person-years lived in the year; newborns start at zero.
    person_years = (pop_start + pop_end) / 2
  )

# ---- Colorado death rates by age and sex: NCHS life tables -----------------

# NCHS publishes life tables for Colorado by sex and single year of age (to
# 100+): the decennial 1999-2001 tables and annual tables for 2018-2023 (R/00
# downloads them). The central death rate at each age is deaths over
# person-years lived (dx / Lx); 90 and over are pooled to match the population.
# Owner, 2026-11-23: "Replace with public data" for the statewide rates that
# had been tabulated from restricted records.
life_table_files <- tibble::tribble(
  ~table_year , ~sex , ~file                      , ~sheet    ,
  2000L       , 1L   , "2000-lewk4_colorado.xlsx" , "male6"   ,
  2000L       , 2L   , "2000-lewk4_colorado.xlsx" , "female6" ,
  2018L       , 1L   , "2018-CO2.xlsx"            , NA        ,
  2018L       , 2L   , "2018-CO3.xlsx"            , NA        ,
  2019L       , 1L   , "2019-CO2.xlsx"            , NA        ,
  2019L       , 2L   , "2019-CO3.xlsx"            , NA        ,
  2020L       , 1L   , "2020-CO2.xlsx"            , NA        ,
  2020L       , 2L   , "2020-CO3.xlsx"            , NA        ,
  2021L       , 1L   , "2021-CO2.xlsx"            , NA        ,
  2021L       , 2L   , "2021-CO3.xlsx"            , NA        ,
  2022L       , 1L   , "2022-CO2.xlsx"            , NA        ,
  2022L       , 2L   , "2022-CO3.xlsx"            , NA        ,
  2023L       , 1L   , "2023-CO2.xlsx"            , NA        ,
  2023L       , 2L   , "2023-CO3.xlsx"            , NA
)

life_tables <- life_table_files |>
  purrr::pmap(\(table_year, sex, file, sheet) {
    path <- file.path(life_tables_dir, file)
    readxl::read_excel(
      path,
      sheet = if (is.na(sheet)) 1 else sheet,
      col_names = c("age_label", "qx", "lx", "dx", "Lx", "Tx", "ex"),
      col_types = "text"
    ) |>
      # Data rows start with the age, as in "0-1", "45–46" or "100 and older".
      dplyr::filter(stringr::str_detect(age_label, "^\\d+")) |>
      dplyr::transmute(
        table_year,
        sex,
        age = as.integer(stringr::str_extract(age_label, "^\\d+")),
        dx = as.numeric(dx),
        Lx = as.numeric(Lx)
      )
  }) |>
  purrr::list_rbind() |>
  dplyr::mutate(age = pmin(age, max_age)) |>
  dplyr::summarise(dx = sum(dx), Lx = sum(Lx), .by = c(table_year, sex, age)) |>
  dplyr::mutate(log_m = log(dx / Lx))

stopifnot(
  nrow(life_tables) == nrow(life_table_files) * (max_age + 1L),
  all(is.finite(life_tables$log_m))
)

# Rate for estimate year t (July t-1 to June t), centred on t - 0.5: the log
# rate is interpolated linearly between the tables in time (the 1999-2001
# table is centred on 2000) and held flat before the first and after the last.
table_years <- sort(unique(life_tables$table_year))

rates_by_year <- tidyr::expand_grid(
  year = (first_year + 1L):last_year,
  sex = 1:2,
  age = 0L:max_age
) |>
  dplyr::left_join(
    life_tables |>
      dplyr::select(table_year, sex, age, log_m) |>
      tidyr::nest(by_year = c(table_year, log_m)),
    by = c("sex", "age")
  ) |>
  dplyr::mutate(
    death_rate = purrr::map2_dbl(year, by_year, \(t, d) {
      exp(stats::approx(d$table_year, d$log_m, xout = t - 0.5, rule = 2)$y)
    })
  ) |>
  dplyr::select(year, sex, age, death_rate)

# A cohort ending the year at age a lives it at ages a - 1 and a, half each;
# newborns live it at age 0 only.
state_rates <- rates_by_year |>
  dplyr::left_join(
    rates_by_year |>
      dplyr::transmute(year, sex, age = age + 1L, rate_younger = death_rate),
    by = c("year", "sex", "age")
  ) |>
  dplyr::transmute(
    year,
    sex,
    age_end = age,
    death_rate = dplyr::if_else(
      is.na(rate_younger) | age == max_age,
      death_rate,
      (death_rate + rate_younger) / 2
    )
  )

# ---- County mortality ratios from the public 2025 reports -------------------

# The reports are downloaded by R/00.
stopifnot(length(list.files(reports_dir, pattern = "\\.xlsx$")) >= 64)

# Table 11 gives deaths and population by five-year group, sexes combined, for
# calendar 2025; "." means one or two deaths and is counted as 1.5. Rows are
# gathered into six broad bands so that suppressed cells matter little.
# Owner, 2026-11-23: "they are slightly different age groups but lets go off
# these". Only 2025 is published, so the ratios are applied to every year.
mortality_bands <- tibble::tribble(
  ~row_label , ~mort_band ,
  "Infant"   , "0-24"     ,
  "1-4"      , "0-24"     ,
  "5-9"      , "0-24"     ,
  "10-14"    , "0-24"     ,
  "15-19"    , "0-24"     ,
  "20-24"    , "0-24"     ,
  "25-29"    , "25-44"    ,
  "30-34"    , "25-44"    ,
  "35-39"    , "25-44"    ,
  "40-44"    , "25-44"    ,
  "45-49"    , "45-64"    ,
  "50-54"    , "45-64"    ,
  "55-59"    , "45-64"    ,
  "60-64"    , "45-64"    ,
  "65-69"    , "65-74"    ,
  "70-74"    , "65-74"    ,
  "75-79"    , "75-84"    ,
  "80-84"    , "75-84"    ,
  "85+"      , "85+"
)

report_rows <- list.files(
  reports_dir,
  pattern = "\\.xlsx$",
  full.names = TRUE
) |>
  purrr::map(\(f) {
    readxl::read_excel(
      f,
      # The sheet name ends in a number that differs from file to file.
      sheet = stringr::str_subset(readxl::excel_sheets(f), "^T11_"),
      skip = 2,
      col_names = c("row_label", "deaths", "population", "rate"),
      col_types = "text"
    ) |>
      dplyr::mutate(
        area = stringr::str_remove(basename(f), "( County)? Summary Report.*$")
      )
  }) |>
  purrr::list_rbind() |>
  dplyr::mutate(row_label = stringr::str_trim(row_label)) |>
  dplyr::inner_join(mortality_bands, by = "row_label") |>
  dplyr::mutate(
    deaths = dplyr::if_else(deaths == ".", 1.5, readr::parse_number(deaths)),
    population = readr::parse_number(population)
  )

report_state_rates <- report_rows |>
  dplyr::filter(area == "Colorado") |>
  dplyr::transmute(row_label, state_rate = deaths / population)

# Ratio of the county's 2025 deaths to what statewide rates would give it,
# pulled toward 1 by adding shrink_deaths to both sides. Rio Grande has no
# report and keeps a ratio of 1.
county_mortality <- report_rows |>
  dplyr::filter(area != "Colorado") |>
  dplyr::left_join(report_state_rates, by = "row_label") |>
  dplyr::summarise(
    report_deaths = sum(deaths),
    expected_deaths = sum(state_rate * population),
    .by = c(area, mort_band)
  ) |>
  dplyr::mutate(
    mortality_ratio = (report_deaths + shrink_deaths) /
      (expected_deaths + shrink_deaths)
  ) |>
  dplyr::inner_join(county_names, by = c("area" = "county")) |>
  dplyr::select(
    countyfips,
    mort_band,
    report_deaths,
    expected_deaths,
    mortality_ratio
  )

# Every county except Rio Grande (08105, no report published) must match a
# report by name; a renamed file would otherwise fall back to the state pattern
# without warning.
unmatched_counties <- setdiff(
  county_names$countyfips,
  c(county_mortality$countyfips, "08105")
)
if (length(unmatched_counties) > 0) {
  stop(
    "No 2025 county report matched: ",
    paste(unmatched_counties, collapse = ", "),
    call. = FALSE
  )
}

readr::write_csv(
  county_mortality,
  file.path(data_dir, "county-mortality-ratios-2025.csv")
)

# ---- Modelled births and deaths, and the residual ---------------------------

# Births are split by sex with the conventional ratio of 105 boys to 100 girls.
birth_sex_share <- tibble::tibble(sex = 1:2, sex_share = c(105, 100) / 205)

annual <- annual |>
  dplyr::left_join(state_rates, by = c("year", "sex", "age_end")) |>
  dplyr::mutate(
    mort_band = dplyr::case_when(
      age_end < 25L ~ "0-24",
      age_end < 45L ~ "25-44",
      age_end < 65L ~ "45-64",
      age_end < 75L ~ "65-74",
      age_end < 85L ~ "75-84",
      .default = "85+"
    )
  ) |>
  dplyr::left_join(
    county_mortality |> dplyr::select(countyfips, mort_band, mortality_ratio),
    by = c("countyfips", "mort_band")
  ) |>
  dplyr::left_join(controls, by = c("countyfips", "year")) |>
  dplyr::left_join(birth_sex_share, by = "sex") |>
  dplyr::mutate(
    mortality_ratio = tidyr::replace_na(mortality_ratio, 1),
    deaths_expected = death_rate * mortality_ratio * person_years
  ) |>
  # Scaled so each county-year matches its published death total. A county-year
  # with no published components (Broomfield before 2000) gets none.
  dplyr::mutate(
    deaths = if (sum(deaths_expected) > 0) {
      deaths_expected *
        tidyr::replace_na(control_deaths, 0) /
        sum(deaths_expected)
    } else {
      0
    },
    .by = c(countyfips, year)
  ) |>
  dplyr::mutate(
    births = dplyr::if_else(
      age_end == 0L,
      tidyr::replace_na(control_births, 0) * sex_share,
      0
    ),
    netmig = pop_end - pop_start - births + deaths
  )

# ---- Checks -----------------------------------------------------------------

# A county-year with people but no published components gets zero births and
# deaths, so its whole natural change would land in net migration. The only
# expected case is Broomfield before it was created (no components until 2000).
missing_controls <- annual |>
  dplyr::summarise(
    person_years = sum(person_years),
    has_controls = !all(is.na(control_deaths)),
    .by = c(countyfips, year)
  ) |>
  dplyr::filter(person_years > 0, !has_controls)

cat("\n--- County-years with people but no published components ---\n")
print(missing_controls)

stopifnot(all(
  missing_controls$countyfips == "08014" & missing_controls$year < 2000L
))

# The residual adds back to population change less natural increase. Where
# SDO's population and components agree, that is SDO's net migration; the gap
# is reported rather than forced, because the two tables differ by rounding in
# 2001-2020 and by more in 1991 (the first year after the 1990 census base).
identity <- annual |>
  dplyr::summarise(
    netmig = sum(netmig),
    control_netmig = dplyr::first(control_netmig),
    .by = c(countyfips, year)
  ) |>
  dplyr::filter(!is.na(control_netmig)) |>
  dplyr::mutate(gap = netmig - control_netmig)

cat("\n--- Sum of net migration by age less SDO net migration, by year ---\n")
identity |>
  dplyr::summarise(
    county_years = dplyr::n(),
    max_abs_gap = round(max(abs(gap))),
    state_gap = round(sum(gap)),
    .by = year
  ) |>
  print(n = 40)


# ---- Write ------------------------------------------------------------------

annual_out <- annual |>
  dplyr::select(
    countyfips,
    county,
    sex,
    year,
    age_end,
    pop_start,
    pop_end,
    person_years,
    births,
    deaths,
    netmig
  )

annual_out <- annual_out |>
  dplyr::bind_rows(
    annual_out |>
      dplyr::summarise(
        dplyr::across(pop_start:netmig, sum),
        .by = c(sex, year, age_end)
      ) |>
      dplyr::mutate(countyfips = "08000", county = "Colorado")
  ) |>
  dplyr::arrange(countyfips, year, sex, age_end)

readr::write_csv(
  annual_out,
  file.path(out_dir, "netmig-annual-sya-1990-2025.csv")
)

cat("\n--- Colorado net migration by decade ---\n")
annual_out |>
  dplyr::filter(countyfips == "08000") |>
  dplyr::mutate(period = cut(year, c(1990, 2000, 2010, 2020, 2025))) |>
  dplyr::summarise(netmig = round(sum(netmig)), .by = period) |>
  print()
