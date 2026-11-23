# Download the public inputs that are not in the SDO database, into data-raw/.
#
# Everything here is public and free to download; data-raw/ is not committed,
# so a fresh clone runs this first. Files already present are left alone, so a
# rerun only fetches what is missing.
#
#   data-raw/census/                     Census Bureau vintage 2025 county
#                                        age/sex and components files (R/03)
#   data-raw/cdphe-county-reports-2025/  CDPHE county summary reports for 2025,
#                                        Table 11 deaths by age group (R/01)
#   data-raw/nchs-life-tables/           NCHS life tables for Colorado, males and
#                                        females: 1999-2001 and 2018-2023 (R/01)
#
# The CDPHE reports sit in a public Google Drive folder linked from CDPHE's
# Vital Statistics Program page ("State and county birth and death summary
# tables"). googledrive reads it without signing in.

library(tidyverse)

proj_dir <- here::here()
raw_dir <- file.path(proj_dir, "data-raw")

# One row per file: where it comes from and where it goes.
url_files <- tibble::tribble(
  ~folder            , ~local                     , ~url                                                                                                        ,
  "census"           , "cc-est2025-agesex-08.csv" , "https://www2.census.gov/programs-surveys/popest/datasets/2020-2025/counties/asrh/cc-est2025-agesex-08.csv" ,
  "census"           , "co-est2025-alldata.csv"   , "https://www2.census.gov/programs-surveys/popest/datasets/2020-2025/counties/totals/co-est2025-alldata.csv" ,
  "nchs-life-tables" , "2000-lewk4_colorado.xlsx" , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/60_09/lewk4_colorado.xlsx"                ,
  "nchs-life-tables" , "2018-CO2.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/70-01/Colorado-2-Male.xlsx"               ,
  "nchs-life-tables" , "2018-CO3.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/70-01/Colorado-3-Female.xlsx"             ,
  "nchs-life-tables" , "2019-CO2.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/70-18/CO2.xlsx"                           ,
  "nchs-life-tables" , "2019-CO3.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/70-18/CO3.xlsx"                           ,
  "nchs-life-tables" , "2020-CO2.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/71-02/CO2.xlsx"                           ,
  "nchs-life-tables" , "2020-CO3.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/71-02/CO3.xlsx"                           ,
  "nchs-life-tables" , "2021-CO2.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/73-07/CO2.xlsx"                           ,
  "nchs-life-tables" , "2021-CO3.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/73-07/CO3.xlsx"                           ,
  "nchs-life-tables" , "2022-CO2.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/74-12/CO2.xlsx"                           ,
  "nchs-life-tables" , "2022-CO3.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/NVSR/74-12/CO3.xlsx"                           ,
  "nchs-life-tables" , "2023-CO2.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/nvss/life-expectancy/2023-state-tables/CO2.xlsx"            ,
  "nchs-life-tables" , "2023-CO3.xlsx"            , "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/nvss/life-expectancy/2023-state-tables/CO3.xlsx"
) |>
  dplyr::mutate(dest = file.path(raw_dir, folder, local))

# ---- Census and NCHS files --------------------------------------------------

purrr::pwalk(url_files, \(folder, local, url, dest) {
  if (!file.exists(dest)) {
    dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)
    download.file(url, dest, mode = "wb", quiet = TRUE)
  }
})

# ---- CDPHE 2025 county reports ----------------------------------------------

reports_dir <- file.path(raw_dir, "cdphe-county-reports-2025")

if (length(list.files(reports_dir, pattern = "\\.xlsx$")) == 0) {
  dir.create(reports_dir, showWarnings = FALSE, recursive = TRUE)
  # The folder is public, so no Google sign-in is needed.
  googledrive::drive_deauth()
  report_files <- googledrive::drive_ls(
    googledrive::as_id("1dpS9IQJVXvW1bDnOvpDPlQ__fIewhg-X")
  )
  purrr::walk2(report_files$id, report_files$name, \(id, name) {
    googledrive::drive_download(
      googledrive::as_id(id),
      path = file.path(reports_dir, name),
      overwrite = TRUE
    )
  })
}

# ---- Check ------------------------------------------------------------------

missing <- url_files |> dplyr::filter(!file.exists(dest))
stopifnot(nrow(missing) == 0)
stopifnot(length(list.files(reports_dir, pattern = "\\.xlsx$")) >= 64)

cat("All public inputs present in data-raw/.\n")
