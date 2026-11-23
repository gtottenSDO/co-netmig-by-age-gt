# Agent notes

Repo-specific gotchas worth not rediscovering.

## The Census county table everyone links to has no age detail

`co-est2025-pop-08.xlsx` (the `tables/2020-2025/counties/totals/` path) is
**total population only** — six columns, one per year. Net migration by age
needs the ASRH dataset instead:

```
https://www2.census.gov/programs-surveys/popest/datasets/2020-2025/counties/asrh/cc-est2025-agesex-08.csv
```

That file carries five-year age groups by sex by county for `YEAR` 1–7, where
`YEAR=1` is the 4/1/2020 base, `YEAR=2` is 7/1/2020, and `YEAR=7` is 7/1/2025.
**Use YEAR 2 → YEAR 7, not YEAR 1 → YEAR 7.** Year 1 is a 5.25-year interval and
breaks the clean five-year cohort advance; year 2 to year 7 is exactly five
years, so each five-year age group maps to the next with no graduation
assumption.

The file also contains overlapping spans (`AGE513`, `AGE1824`, `AGE1544`,
`AGE65PLUS`, ...) mixed in with the disjoint five-year groups. Selecting columns
by regex silently pulls those in and double-counts. Name the 18 five-year
columns explicitly.

## How CDPHE records map to the estimate year (moved)

Moved on 2026-11-23 to `internal/NOTES-internal.md` (not in the public
repository) because it describes restricted CDPHE files and internal drive
locations. Owner, 2026-11-23: "clean up any of the non public data or
references that might be in the repo".

## Which vital-records files to prefer (moved)

Moved on 2026-11-23 to `internal/NOTES-internal.md` (not in the public
repository) because it describes restricted CDPHE files and internal drive
locations. Owner, 2026-11-23: "clean up any of the non public data or
references that might be in the repo".

## `tibble()` recycles a scalar column before later columns see it

This fails with `invalid 'times' argument`:

```r
tibble::tibble(
  k   = k,
  age = (79L + k):max_age,
  w   = c(0.5, rep(1, max_age - (79L + k)))   # k is now length-19, not scalar
)
```

Once `age` is created, the `k` column has been recycled to `age`'s length, so
the later reference to `k` is a vector and `rep()` rejects it. Bind the vectors
to local variables before the `tibble()` call, or name the loop variable
something other than the column.

## Validation that actually catches errors

Three checks, all cheap, all in `R/01-build-netmig-by-age.R`:

1. **Lexis weights partition every age.** Weights summed over cohorts must equal
   exactly 1.0 for each (age, year). A `stopifnot()` on this catches off-by-one
   errors in the open-ended and birth cohorts, which are the easy ones to get
   wrong.
2. **CDPHE totals vs Census control totals.** Landing within a few tenths of a
   percent is the signal that the fyear mapping and county coding are right. A
   several-percent gap means the year convention is off.
3. **The identity closes.** After calibration, net migration summed over ages
   must equal Census `NETMIG + RESIDUAL` per county. The `RESIDUAL` term is easy
   to forget and its omission shows up as a small nonzero difference.

## `QUARTO_R` is set to a corrupted path on this machine

`quarto render` fails with
`os error 123: stat 'C:\Users\sdo\scooppps\R'` — the `QUARTO_R` environment
variable holds a mangled value (`scoop\apps` collapsed into `scooppps`). It is
not a problem with the document. Either fix the variable at the user level or
override it for the render:

```sh
QUARTO_R="$(Rscript -e 'cat(R.home("bin"))')" quarto render netmig-by-age.qmd
```

The real path is whatever `R.home("bin")` reports.

## One Lexis formula handles birth cohorts for free

**Superseded, 2026-11-23:** the build now works one year at a time by single
year of age, so the five-year Lexis weights below are no longer used;
kept for the reasoning.


The obvious way to write the death-allocation weights is a special case for
cohorts born during the period. It is not needed. Key each cohort by its age at
the start of the period and allow that to be **negative**: a cohort with
`a = -5` is "aged -5 to 0" at the start, meaning it is born across the first five
years. Generate its full age range with the standard weights and discard the
negative ages, and the remaining weights are exactly right.

Checked against the hand-derived version: `a = -5` at year 1 leaves age 0 with
weight 0.5; at year 5 it leaves ages 0-3 at weight 1 and age 4 at 0.5. Both
match. Over a ten-year window the two birth cohorts come out at 12.5 and 37.5
person-years, summing to the 50 that one closed cohort contributes.

The partition assertion is what makes this safe to trust. `check_lexis_partition()`
verifies that weights sum to exactly 1.0 for every (year, age) cell; without it a
clipping error would silently shift deaths into net migration where nothing else
would reveal it.

## Where SDO population and components are stored (moved)

Moved on 2026-11-23 to `internal/NOTES-internal.md` (not in the public
repository) because it describes restricted CDPHE files and internal drive
locations. Owner, 2026-11-23: "clean up any of the non public data or
references that might be in the repo".

## `data.netmigrbyage` does not reconcile with itself

SDO already publishes net migration by age in `data.netmigrbyage`
(`netmig9500`/`netmig0010`/`netmig1020` with matching `rate*` columns). Two
problems make it unusable as a control:

- The level and rate columns disagree. Above age 65 `rate1020` is negative while
  `netmig1020` stays positive, and dividing level by rate implies a different
  denominator for every age group, including negative ones.
- The 85+ row is 39,823 against 2,431 for 80-84, and its own rate of 0.0031
  implies a denominator of 12.8 million.

Statewide `netmig1020` also sums to about 538,000 against 450,386 in
`components_change` for 2011-2020. `estimates.county_migbyage_sya` has the same
smell — it sums to 364,682, which matches no clean year window, and shows +9,786
at age 90+.

Both are written out for reference and used as controls nowhere. Someone who
knows their vintage should confirm what they represent.

## The Postgres MCP takes one statement per call

Sending two `SELECT`s separated by a semicolon returns a schema-validation error
from the MCP layer, not a SQL error, which is misleading. Split them.

## Birth-cohort migration rates need exposure, not the midpoint population

**Superseded, 2026-11-23:** the build now works one year at a time by single
year of age, so the exposure factors below are no longer used;
kept for the reasoning.


The obvious denominator for a cohort migration rate is mean population,
`(pop_start + pop_end) / 2`. For a cohort born during the period that is only
right when the births are spread across the **whole** window.

Over the 2010-2020 decade there are two birth cohorts and neither is. The group
aged 0-4 in 2020 was born in fyears 2016-2020 and did not exist for the first
five years; the group aged 5-9 was born in 2011-2015 and was fully present for
the last five. Using `pop_end / 2` for both gave the first roughly twice the
exposure it should have and the second about three quarters of it — the 0-4 rate
came out at 2.63 when it should be 5.25, and 5-9 at 12.4 when it should be 8.25.
The error is invisible in the levels, which is what makes it easy to ship.

The fix costs one line, because the Lexis weights already encode it. A closed
cohort's weights sum to `5 * n_years`; dividing each cohort's weight total by
that gives the exposure factor directly — 1.0 for closed cohorts, 0.75 and 0.25
for the decade's two birth cohorts, 0.5 for the single birth cohort in a
five-year window (where the naive midpoint happens to be right, which is why the
2020-2025 build never revealed the problem).

```r
cohort_exposure <- lexis_weights |>
  dplyr::summarise(exposure_factor = sum(w) / (5 * n_years), .by = cohort)

mean_pop = dplyr::if_else(
  pop_start > 0,
  (pop_start + pop_end) / 2,
  pop_end * exposure_factor
)
```

`mean_pop` is computed in the build scripts and carried through to
`R/03-compare-periods.R` rather than recomputed there, so the comparison cannot
silently fall back to the midpoint.

## OJS value boxes: two traps, one real and one imaginary

**Real: a bare string renders with visible quote marks.** An OJS cell marked
`//| content: valuebox` whose last expression is a plain JavaScript string shows
up on the page as `"+4.8 per 1,000"`, quotes included, because Quarto renders it
through the Observable inspector. Wrap it:

```js
html`${measures[measure_p].fmt(val2010_p)}`
```

The boxes that already used `` html`` `` were fine; only the bare-string ones
were wrong.

**Imaginary: "the value boxes are empty."** They are not. An OJS value box does
**not** put its value in `.value-box-value` the way an R value box does — that
node stays empty and the value renders into an adjacent Observable output node.
So this check reports every box as empty even when the page looks correct:

```js
[...document.querySelectorAll('.value-box-value')].map(e => e.textContent)  // WRONG
```

Both a subagent and I independently concluded the boxes were broken on the
strength of that selector, and the subagent went as far as building an isolated
reproduction and recommending replacing every value box with a styled card. The
page had been rendering correctly the whole time. Check the card text instead,
filtering to boxes that are actually rendered:

```js
const vis = el => el.offsetParent !== null && el.getClientRects().length > 0;
[...document.querySelectorAll('.card')]
  .filter(c => vis(c) && c.querySelector('.value-box-title'))
  .map(c => c.innerText.replace(/\s+/g, ' ').trim())
// -> ["2010-2020, all ages +8.3 per 1,000", "Peak age group, 2020-2025 25-29: +36.3 per 1,000", ...]
```

The visibility filter matters: `innerText` falls back to raw text for elements
that are not rendered, so the hidden `::: {.hidden}` cells that hold the OJS
variable definitions come back as walls of source code and drown the real
output.

A useful control when a value box looks wrong: add an R value box
(`#| content: valuebox` returning `list(value = 7)`) next to it. R value boxes
*do* populate `.value-box-value`, so if the R one shows and the OJS one does
not, the difference is the rendering path, not your data.

## Screenshots of a busy OJS page time out

`Page.captureScreenshot` repeatedly timed out at 30s on the dashboard while
several tabs each ran 44 OJS cells against the same 551 KB CSV, alongside two
`quarto preview` servers. The renderer is not crashed — DOM queries through the
JavaScript tool keep working and are far more reliable for verification anyway.
Prefer reading the DOM over screenshotting when checking OJS output, and close
spare tabs and preview servers first.

`quarto preview` also leaves `deno` and `quarto` processes running, and a local
`python -m http.server` rooted in `_site` will lock that directory so the next
`quarto render` fails with `os error 32: remove '_site'`. Kill the servers before
re-rendering.

## OJS does not run in a hidden browser tab

Chrome throttles background tabs, and the Quarto OJS runtime will not evaluate
its cells until the tab is actually visible. A dashboard checked from an
automated, unfocused tab looks completely broken: value boxes show titles with
no values, charts are empty frames, the sidebar inputs are missing entirely, and
`window._ojs.runtime.value('raw')` never resolves.

`document.visibilityState` is the tell. If it reports `"hidden"`, nothing that
follows is evidence about whether the page works.

This cost an hour across two false diagnoses — first that a code change had
broken the dashboard, then that GitHub Pages was serving it wrong. The deployed
page had been fine throughout. The controlled test that settled it was loading
the local build and the deployed build in the same hidden tab back to back and
getting byte-for-byte identical (broken-looking) results, then taking a
screenshot, which makes the tab visible, and watching both populate.

Take a screenshot first, wait several seconds, and only then read the DOM.

A related red herring: the local and deployed HTML differ by several hundred
bytes in the base64 `ojs-module-contents` payload. That is only CRLF against LF
in the source `.qmd` — Windows renders locally, Linux renders in CI. It is not a
version difference and not a problem.

## How far back the age-detailed history can go: 1990, not 1970

`estimates.components_change` runs from 1970, which makes a 1970s start look
possible. It is not. That table carries births, deaths and net migration as
totals with no age breakdown, and every age-detailed population table in the
database begins in 1990:

| table | earliest Estimate |
|---|---|
| `estimates.county_sya` | 1990 |
| `estimates.colorado_sya` | 1990 |
| `estimates.county_5ya` | 1990 |
| `estimates.county_census_grouping_ya` | 1990 |

The CDPHE microdata begins in 1989, so vital events are not the binding
constraint; population by age is. Reaching 1970 or 1980 would mean bringing in
decennial county age counts from outside this database.

Note the top-coding changes: `county_sya` tops out at age 90 for 1990 and 2000
and at 100 for 2010 and 2020. Cohort construction has to tolerate both, which is
why the open-ended group is defined as 80+ at the start of a decade landing in
90+ at the end.

## Joining the older and newer CDPHE extracts (moved)

Moved on 2026-11-23 to `internal/NOTES-internal.md` (not in the public
repository) because it describes restricted CDPHE files and internal drive
locations. Owner, 2026-11-23: "clean up any of the non public data or
references that might be in the repo".

## The older decades close the identity less tightly

Net migration summed across ages matches SDO's own `components_change` control
exactly for 2000-2010 and to within 14 people for 2010-2020, but for 1990-2000
the worst county is Denver at 858 people, about 1.8% of its decade total, and
the sum of absolute county gaps is about 5,200 on 718,000. That is internal
inconsistency between the older `county_sya` vintages and their components of
change, not an error in the residual. Worth reporting rather than chasing.

## Each top-level cell in a dashboard Row becomes its own card

A chart cell and a button cell placed side by side under `### Row` render as
**two cards**, not one card with a button under the chart. The result is a
half-width chart next to a nearly empty card containing a lone button.

Wrap them together explicitly:

```markdown
### Row {height="42%"}

::: {.card title="Net migration by age group, selected periods"}

```{ojs}
chart_p1 = Plot.plot({ ... })
```

```{ojs}
//| echo: false
svgDownloadButton(chart_p1, "filename.svg")
```

:::
```

Note the cell loses its `//| title:` option when it moves inside the card — the
title comes from the div attribute instead.

## Exporting an Observable Plot chart as SVG for PowerPoint

Three things have to be handled or the file opens blank or unstyled:

- **Pick the right `<svg>`.** When a chart has `legend: true`, Plot returns a
  `<figure>` containing small per-swatch `<svg>` icons *before* the chart's own
  `<svg>`. `querySelector("svg")` grabs a 15x15 legend icon and silently writes a
  near-empty file. Select the largest `<svg>` in the subtree by rendered area.
- **Inline the styles.** Plot marks rely on a generated stylesheet class and on
  `fill="currentColor"`, neither of which travels with the file. Walk the clone
  and copy each element's *computed* fill, stroke and font onto explicit
  attributes.
- **Redraw the legend.** Plot's legend is an HTML div, not part of the SVG, so it
  has to be rebuilt as `<rect>` + `<text>`, with the root height and viewBox
  grown and the original content wrapped in a translated `<g>`.

Set explicit `width`, `height` and `viewBox` on the root so it scales cleanly.
A good export checks out as: valid XML, hundreds of explicit `fill="#..."`
attributes, a `font-family` on every text node, and the legend labels present as
real text.

## OJS misses a variable referenced only by computed member access

`measureSlug = ({rate_per_1000: "rate", ...})` referenced as
`` `...${measureSlug[measure_p]}...` `` inside a template literal threw
`measureSlug is not defined` at runtime, even though the cell plainly exists.
Quarto's OJS dependency scanner did not recognise the bracket-subscript
reference as a free variable, so the compiled cell never received it.

Making it a function and calling it (`measureSlug(measure_p)`) sidesteps the
parser entirely. If you see "X is not defined" for something that demonstrably
exists, check whether the only reference is computed member access inside a
template literal.

## 2026-11-23 — Custom spans and broad age groups: method switch and disclosure

**Request.** The owner asked for age groups 0-18, 18-24, 25-44, 45-64, 65+ (read
as 0-17 so that age 18 is counted once) and for custom spans such as 2022-2025
and 2024-2025.

**Why the old 2020-2025 build could not do it.** It used the Census age/sex file,
which has five-year groups only. Five-year groups advance cleanly only over
exactly five years, and 18-24 cannot be formed from them. Both requests need
population by single year of age.

**Owner decisions, 2026-11-23** (answers to multiple-choice questions):
- Population source: "Switch to SDO (Recommended)" — 2020-2025 now reads
  `estimates.county_sya`, which now carries 2025 as an Estimate.
- Span range: "2020–2025 only (Recommended)".
- Age groups: "Offer both (Recommended)" — five-year groups and the five broad
  groups.
- Deaths behind the published custom-span county figures: "Modelled from public
  data".

**SDO against Census PEP** (`R/05-compare-sdo-pep.R`, owner asked "can you also
check the sdo estimates against the pep estimates?"):
- Net migration is identical by county and year; SDO takes Census
  NETMIG + RESIDUAL as given. Births and deaths differ slightly because SDO uses
  CDPHE, so the state totals drift apart from -241 (2020) to -1,415 (2025).
- In 2020 SDO has 9,123 fewer children aged 0-4 than Census and 500-1,000 more
  in each group from 5 to 79. The gap travels with the cohort (it is -9,123 at
  5-9 in 2025), so it cancels from the cohort residual and only touches rates.
- Dolores is about 250 people (10%) lower in SDO in every year: a different
  2020 base, not a different change.

**Effect of the switch on 2020-2025.** Statewide net migration is unchanged at
+141,694; no five-year group moves by more than 91; across 1,152 county-age cells
the median change is 0.5 people. The identity
closes exactly in all 320 county-years against `components_change`.

**Disclosure — what nearly went wrong.** `R/04` drops county birth and death
columns, but that does not protect them: SDO single-year population is public,
and deaths = net migration - population change + births. So any published net
migration by age gives back that cell's deaths. Annual single-year spans would
have exposed county deaths by single age and year, mostly below five. This
already applied, more coarsely, to the five-year cohorts published before today.

**Public-data version** (`netmig_mod` in `netmig-annual-sya-2020-2025.csv`):
statewide death rates by year, sex and age band (0, 1, 2-4, five-year bands to
95-99, 100) times county person-years, scaled to SDO's county-year death total;
births are the county total split by the statewide sex ratio. Bands 2-14 are
pooled across sex and year because one statewide count was 4; every rate now
rests on at least 53 deaths. Cost, measured against recorded deaths: medians
move 3-6 people, but older ages in large counties move by hundreds, because
county mortality differs from the state's at the same age. (Named-county
figures moved to `internal/NOTES-internal.md`, 2026-11-23.)

**County age pattern of deaths from CDPHE's public reports.** The COHID
dashboard (county x age group x calendar year, counts of 1-2 suppressed) offers
no bulk download and its bar values are not in the page text, so it was not
used. The owner then found the source the dashboard draws on: the "2025 County
Reports" Google Drive folder linked from CDPHE's Vital Statistics Program page
("State and county birth and death summary tables"). Owner, 2026-11-23: "they
are slightly different age groups but lets go off these". Only 2025 is
published there, and Rio Grande is missing. Table 11 gives deaths and
population by five-year group, sexes combined. The sheet name ends in a number
that differs per file ("T11_Age-specific Death Rates 86", "... Rate 133"), so it
is matched by prefix.
Method: six bands (0-24, 25-44, 45-64, 65-74, 75-84, 85+), a suppressed cell
counted as 1.5, ratio = (observed + 10) / (expected + 10) against statewide 2025
rates, applied to all of 2021-2025, Rio Grande = 1. Effect against recorded
deaths, broad groups 2020-2025: the largest county error fell by about
two-thirds and the 90th percentile from 72 to 48 people. (Named-county figures
moved to `internal/NOTES-internal.md`, 2026-11-23.)

**Dashboard.** New "Custom span" page reads `output/netmig-annual-sya-2020-2025.csv`
(65,650 rows, 2 MB): start and end year, broad or five-year groups, areas, sex,
measure (rate or people) and basis (annual average or total over the span;
owner: "lets also add in something to choose an annual average rate for the
custom periods - it cna just be total and annual average or something as a
toggle"). Checks in the browser: Colorado 2020-2025 groups sum to +141,697
(+141,694 published, rounding); 2024-2025 to +3,450 (SDO 2025 net migration
+3,451).

**OJS trap, again.** Cells written `name = ({ ... })` rendered as "name is not
defined", like the computed-member case above. The block form
`name = { return {...}; }` works. Chrome also served the old page from cache
after a re-render; add a query string (`?v=2`) when checking a re-render.

## 2026-11-23 (later) — One method for every period; public repository cleaned

Owner, 2026-11-23: "can you go ahead with the remaining to dos and clean up any
of the non public data or references that might be in the repo? because of that
we should change the compare to be on the same methodology". On the Broomfield
boundary change: "just mark the caveat when including them".

**What changed.** The repository is public (checked with `gh repo view`). Every
period is now built by one pipeline, one estimate year at a time by single year
of age, with county deaths estimated from public data: `R/01-build-netmig-annual.R`
(1990-2025) then `R/02-build-periods.R` (four periods x five-year and broad
groups, the custom-span file, the county grid). The old cohort builds, Lexis
weights, calibration diagnostics and per-period files were removed. The only
code that touches restricted files is in `internal/` (gitignored): it writes the
statewide aggregates in `data/` and runs the check against recorded deaths. The
public `data/` and `output/` files pass `R/04-check-outputs.R`.

**What nearly went wrong.** The first annual build overstated statewide net
migration by 10,000-22,000 a year for 1991-2009. `estimates.county_sya` tops
out at an open 90+ group before 2010 and at 100+ from 2010; carrying age 90 to
91 dropped the 90+ group between years. Fix: cap at 90+ for every year, with one
statewide death band for 90+. After the fix, net migration summed over ages
equals SDO's net migration exactly for 1992-2025, apart from rounding gaps of
10-20 in 2001-2020 and the 1991 gap of up to 858 already in SDO's own tables.
2010-2020 statewide is 450,141 against 450,448 in the old cohort build (307
people, 0.07%); the other periods match exactly.

**Broomfield.** SDO's tables give Broomfield zero population until 1999 and
record all 38,545 residents as net migration in estimate year 2000, with
matching losses in Adams (-8,329) and Boulder (-10,005). The 1990-2000 figures
for the five counties carry a `caveat` column and a dashboard note.

**Estimated against recorded deaths, all periods** (`data/modelled-deaths-validation.csv`):
broad groups, median county-group difference 6.1 (1990s), 7.4 (2000s), 6.2
(2010s), 5.5 (2020-2025) people; the largest differences are in the oldest
groups of large counties in the 1990s, because the county mortality ratios are
from 2025.

**Moved out of this file.** Four sections describing restricted CDPHE files and
internal drive locations were moved verbatim to `internal/NOTES-internal.md`;
pointers remain under their old positions.

**Not yet done:** the git history still holds the earlier published files built
from recorded deaths, the calibration files with CDPHE county totals, and the
internal paths. Removing them needs a history rewrite and force-push; that is
the owner's call (TODO 9).

## Where to start next

1. **Owner:** decide whether to rewrite the repository history to remove the
   earlier files and references (TODO 9). It is a force-push to a public
   repository; copies already fetched or forked are not affected.
2. **Owner:** review and merge today's pull request.
3. Nothing is running; logs are in `logs/finished/`.
4. To rebuild: inside SDO run `internal/01-prepare-vital-inputs.R` only when
   the vital records change, then `R/01` to `R/04` and the render.
5. Do not add recorded county deaths, or anything computed from them below
   the state level, to `output/` or `data/`; `R/04-check-outputs.R` guards it.
