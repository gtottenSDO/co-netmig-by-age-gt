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

# A file counts as present only if it exists and is not empty. Each download
# goes to a temporary name and is renamed only when it completes, so an
# interrupted run never leaves a partial file that a rerun would skip.
present <- function(path) file.exists(path) & file.size(path) > 0

purrr::pwalk(url_files, \(folder, local, url, dest) {
  if (!present(dest)) {
    dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)
    partial <- paste0(dest, ".part")
    on.exit(unlink(partial), add = TRUE)
    download.file(url, partial, mode = "wb", quiet = TRUE)
    file.rename(partial, dest)
  }
})

# ---- CDPHE 2025 county reports ----------------------------------------------

reports_dir <- file.path(raw_dir, "cdphe-county-reports-2025")
dir.create(reports_dir, showWarnings = FALSE, recursive = TRUE)

# The folder is public, so no Google sign-in is needed. googledrive lists it
# signed out, but its signed-out downloads fail, so each file comes through
# Google's public download link instead. Only reports not yet present are
# downloaded, so an interrupted run is completed by a rerun.
googledrive::drive_deauth()
report_files <- googledrive::drive_ls(
  googledrive::as_id("1dpS9IQJVXvW1bDnOvpDPlQ__fIewhg-X")
) |>
  dplyr::mutate(
    dest = file.path(reports_dir, name),
    url = paste0("https://drive.google.com/uc?export=download&id=", id)
  )

report_files |>
  dplyr::filter(!present(dest)) |>
  dplyr::select(url, dest) |>
  purrr::pwalk(\(url, dest) {
    partial <- paste0(dest, ".part")
    on.exit(unlink(partial), add = TRUE)
    download.file(url, partial, mode = "wb", quiet = TRUE)
    file.rename(partial, dest)
  })

# ---- Check ------------------------------------------------------------------

missing_files <- tibble::tibble(dest = c(url_files$dest, report_files$dest)) |>
  dplyr::filter(!present(dest)) |>
  dplyr::pull(dest)

if (length(missing_files) > 0) {
  stop(
    "Still missing or empty: ",
    paste(basename(missing_files), collapse = ", "),
    call. = FALSE
  )
}

cat("All public inputs present in data-raw/.\n")
