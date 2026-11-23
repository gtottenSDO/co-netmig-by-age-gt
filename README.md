# co-netmig-by-age-gt

Net migration by age for Colorado and its 64 counties, across four periods —
**1990–2000, 2000–2010, 2010–2020 and 2020–2025** — and any span inside
2020–2025.

Published at <https://gtottensdo.github.io/co-netmig-by-age-gt/>.

Population by age and total net migration by county are published, but net
migration *by age* below the state level is not. This repo recovers it as a
demographic residual: for a group of people followed through time, net
migration is what is left once births and deaths are removed from their
population change.

```
NM = Pop_end - Pop_start - Births + Deaths
```

The residual is formed one estimate year (July to July) at a time, by single
year of age, for every county and sex from 1990 to 2025. Adding up the one-year
results for the same people gives exactly their net migration over a longer
period, so every period, age grouping and custom span is a sum of the annual
rows.

## Layout

| Path | Contents |
|---|---|
| `R/01-build-netmig-annual.R` | Annual residual by county, sex and single year of age, 1990–2025, with deaths estimated from public data |
| `R/02-build-periods.R` | Sums the annual rows into periods and age groups; writes `output/` |
| `R/03-compare-sdo-pep.R` | Check: SDO population and components against Census PEP vintage 2025 (writes to `output-internal/`) |
| `R/04-check-outputs.R` | Guard: fails if anything in `output/` or `data/` carries county birth or death counts or recorded-count columns |
| `data/` | Public inputs: statewide deaths by age band and births by sex, county mortality ratios, validation summary |
| `output/` | Published results (committed) |
| `output-internal/` | Large or check-only intermediate files (not committed) |
| `index.qmd`, `netmig-by-age.qmd`, `dashboard.qmd` | Landing page, report, dashboard |
| `NOTES-agent.md`, `TODO.md` | Findings and decisions; open items |

### Outputs

| File | Contents |
|---|---|
| `netmig-comparison.csv` | Period × age grouping (`five`, `broad`) × area × sex × age group: population at start and end, average population, net migration, annual level and rate per 1,000; births and deaths for the state only; a `caveat` column for rows affected by the Broomfield boundary change |
| `netmig-annual-sya-2020-2025.csv` | County × sex × estimate year × single year of age, 2021–2025; the dashboard's Custom span page sums it into any span and grouping |
| `co-netmig-by-age-wide.csv` | County × five-year age group, 2020–2025, for spreadsheets |
| `sdo-published-netmig-by-age.csv` | SDO's earlier published net migration by age, for reference only |

## Running it

```sh
Rscript R/01-build-netmig-annual.R
Rscript R/02-build-periods.R
Rscript R/03-compare-sdo-pep.R   # check only
Rscript R/04-check-outputs.R
QUARTO_R="$(Rscript -e 'cat(R.home("bin"))')" quarto render
```

The `QUARTO_R` override is needed because this machine has that variable set to
a corrupted path; see `NOTES-agent.md`.

`R/01` needs read access to the SDO database through `sdotools` (the public
read-only account) and downloads CDPHE's public 2025 county reports into
`data-raw/` on first run. `R/03` downloads the Census inputs the same way. The
statewide files in `data/` are produced inside the State Demography Office from
CDPHE vital records by a step that is not part of this repository.

## Data and disclosure

County deaths by age come from CDPHE vital records, which are confidential, and
in small counties most such counts are under five. Because population by age is
public, net migration by age built from recorded deaths would let anyone work
the deaths back out (deaths = net migration − population change + births). So
**everything published here is built from public data**, and county deaths by
age are estimated:

- statewide death rates by year, sex and age band (`data/state-deaths-by-band.csv`;
  ages 2–14 pooled across sex and five-year blocks of years so that no band
  rests on fewer than five deaths)
- times each county's mortality ratio for six broad bands, from CDPHE's public
  2025 county summary reports (`data/county-mortality-ratios-2025.csv`), pulled
  toward 1 when deaths are few
- applied to the county's person-years and scaled to its published death total
  for each year.

Births are each county-year's published total, split by sex with the statewide
ratio. County totals are therefore exact; only the spread across ages is
estimated. Against recorded deaths (checked internally;
`data/modelled-deaths-validation.csv` holds the summary), broad age groups
differ by a median of 6–7 people per county per decade and 5.5 for 2020–2025;
the largest differences are in the oldest groups of the largest counties,
biggest in the 1990s. Owner's decisions, 2026-11-23: "Modelled from public
data" and "we should change the compare to be on the same methodology".

## Inputs

| Input | Source |
|---|---|
| Population by single year of age and sex, 1990–2025 | SDO `estimates.county_sya` (top age 90+ before 2010, so 90+ is used throughout) |
| County births, deaths, net migration by year | SDO `estimates.components_change` |
| Statewide deaths by age band, births by sex | `data/` (CDPHE, statewide aggregates) |
| County age pattern of deaths | CDPHE public 2025 county summary reports, Table 11 |

Until 2026-11-23 the 2020–2025 period used the Census Vintage 2025 county
age/sex file, which has five-year groups only. `R/03-compare-sdo-pep.R` compares
the two: net migration is identical by county and year, statewide totals differ
by under 0.03%, and SDO's 9,100 fewer children aged 0–4 in 2020 stay with the
same people through 2025, so they cancel out of net migration.

**1990 is the earliest possible start.** The SDO age-detailed population tables
begin in 1990; `estimates.components_change` reaches back to 1970 but without
age detail.

## Results in brief

| Period | Net migration | Per year |
|---|---:|---:|
| 1990–2000 | +718,433 | 71,843 |
| 2000–2010 | +318,981 | 31,898 |
| 2010–2020 | +450,141 | 45,014 |
| 2020–2025 | +141,694 | 28,339 |

In the 1990s Colorado gained people at every age — the weakest group, 75–79,
still ran at +4.6 per 1,000 a year. Today the young-adult peak has nearly
recovered (25–29 at +36.1 per 1,000 against +38.7 in the 1990s), but every group
from 45–49 to 80–84 is negative and the inflow of school-age children has
largely stopped.

## Caveats

- This recovers the net migration by age *implied by* the published population
  estimates, not an independent measurement.
- **Broomfield, 1990–2000:** the estimates record the transfer of territory to
  the new county in estimate year 2000 as migration, so the 1990–2000 figures
  for Adams, Boulder, Broomfield, Jefferson and Weld include it. Those rows are
  marked in `netmig-comparison.csv` and on the dashboard.
- SDO's population table and components of change disagree by up to 858 people
  in a county in 1991 and by 10–20 in 2001–2020; the gaps land in net migration.
- SDO's own published `data.netmigrbyage` is written out for reference only; it
  does not reconcile with the components of change.
