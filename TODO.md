# co-netmig-by-age-gt — task list

## What is up next

### Awaiting owner decision
| # | Item | Next step | Who |
|---|---|---|---|
| 9 | Git history still holds earlier files built from recorded deaths, CDPHE county totals and internal paths | Decide on a history rewrite and force-push to the public repository | owner |
| 8 | Today's pull request | Review and merge (merge commit) | owner |

### Deferred
| # | Item | Next step | Who |
|---|---|---|---|
| 10 | County mortality ratios come from 2025 only, which costs most in the oldest groups of large counties in the 1990s | Add earlier CDPHE county reports if they are published | session |

## How to read this file
Numbers are permanent. The reasons behind each row are in `NOTES-agent.md`,
entries of 2026-11-23.

## Done since last rebuild
| # | Item | Evidence |
|---|---|---|
| 3 | Every period on the same method (estimated deaths) | `R/01-build-netmig-annual.R`, `R/02-build-periods.R`; owner: "we should change the compare to be on the same methodology" |
| 4 | Report and landing page rewritten; figures computed inline | `netmig-by-age.qmd`, `index.qmd` |
| 5 | Broad age groups for all periods, on both Compare pages | `output/netmig-comparison.csv` (`grouping`); `dashboard.qmd` |
| 11 | Non-public files and references removed from the working tree | `internal/` gitignored; `R/04-check-outputs.R` passes; `NOTES-internal.md` |
| 12 | Broomfield 1990-2000 caveat marked | `caveat` column; dashboard note; report caveats |
