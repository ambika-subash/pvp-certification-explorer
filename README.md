# PVP Certification Explorer (India)

[![DOI](https://zenodo.org/badge/1112427994.svg)](https://doi.org/10.5281/zenodo.21140353)

An R + Quarto project on India's Plant Variety Protection (PVP) certificates, issued
under the Protection of Plant Varieties & Farmers' Rights Act (PPVFRA), 2001. The full
register is scraped, cleaned, and analysed automatically every week and published as an
interactive dashboard.

**Live site**: <https://ambika-subash.github.io/pvp-certification-explorer/>

**Focus**
- Who actually holds PVP certificates over time: private firms, public institutions,
  farmers, and individual breeders.
- How crop-wise and firm-wise concentration has evolved, with a particular case study on
  **cotton**, India's only widely genetically modified crop.

This repo is part of a broader portfolio on agritech, biotechnology regulation, and
tech-policy analytics.

---

## The dashboard

The site is a single-page [Quarto](https://quarto.org) website (`index.qmd`), rebuilt
automatically every week from the latest data. It's an interactive explorer, not a
write-up: charts (built with Observable Plot inside Quarto's OJS engine) let you ask the
same set of questions of *any* crop, not just cotton, including a **"Cotton (All)"**
option that merges diploid and tetraploid cotton together.

Covered on the page: total certificates issued per year, certificates by crop group,
certificate trends and applicant composition by crop, firm-level concentration, a
per-crop Gini concentration score, variety category breakdown, cumulative ownership over
time, a full crop-comparison tool, and a searchable firm lookup (every private applicant's
crop-by-crop footprint).

A longer written analysis, including the cotton case study, Lorenz curve, and EDV/VCK
detail that used to live on a second page (`analysis.qmd`) here, is now published
separately on [The Lone Researcher](https://theloneresearcher.substack.com/), linked from
the dashboard. `analysis.qmd` still exists in this repository and still renders correctly
if you build it locally, it's just no longer linked from the site's navigation.

**Dashboard features**
- **Dark mode**: a light/dark theme toggle in the navbar, defaulting to your system
  preference and remembered on return visits. Charts themselves stay on a light card
  regardless of theme, since their colour encoding is tuned for a light background.
- **Sticky section navigation**: a left-hand table of contents jumps directly to any
  section.
- **Chart export**: every chart has a "Save chart as PNG" button. The exported image
  includes the chart's title, current filter selection, and a data source line, so it
  reads correctly once it's out of the page context.
- **Data download**: the full cleaned dataset is downloadable as CSV directly from the
  page, kept in sync with the weekly refresh.

All of this sources `R/prep_dashboard.R`, the single place data loading, colour palettes,
the company-name deduplication logic, and the Gini function live. That way the numbers
never drift out of sync across charts.

---

## Data

- **Source**: the PPV&FR Authority's public certificate register:
  <https://plantauthority.gov.in/list-certificates>
- **Coverage**: every granted certificate (~10,500+ and growing), 2007 onward.
- The register is scraped, cleaned, and analysed entirely in R. A weekly job keeps the
  dataset current automatically (see [Automation](#automation)).

Generated data files (tracked in `data/`):

| File | Description |
|------|-------------|
| `pvp_certificates_all.csv`   | Raw scrape of the full register (one row per certificate). |
| `pvp_certificates_clean.csv` | Cleaned/analysis-ready: normalised categories & sectors, parsed years, cotton & ploidy flags, expiry/term/live-status, applicant tiers. See [Codebook](#codebook). |
| `last_updated.txt`           | Timestamp of the last successful refresh. |
| `reference_date.txt`         | The date `is_live` was computed against for the current `pvp_certificates_clean.csv` (see [Codebook](#codebook)). |
| `applicant_normalisation_lookup.csv` | Audited applicant → Tier-1 `applicant_norm` dictionary (human-maintained; grows as new applicants are reviewed). See [Codebook](#codebook). |
| `entity_exceptions.csv`      | Layer-2 override table for applicant strings the mechanical Tier-1 rule can't derive on its own. |
| `same_entity_merges.csv`     | Tier-1 → Tier-2 (`applicant_entity`) fold: CIN-confirmed same-legal-entity pairs. |
| `A1_ownership_crosswalk.csv` | Tier-2 → Tier-3 (`owner_group`) fold: evidence-backed ownership groupings, with CIN and source per row. |
| `A2_considered_not_merged.csv`, `A3_related_entities_absent.csv`, `A5_control_verification.csv`, `A6_larger_holders_examined.csv` | Supporting evidence for the Tier-3 crosswalk, deposited alongside as supplementary files. |
| `applicant_review_queue.csv` | Private-sector applicant strings seen for the first time since the audit -- generated fresh each run, present only when non-empty. Not a data-quality signal on its own; see [Codebook](#codebook). |

---

## Pipeline

Scripts live in `R/`, run in order. Each reads the previous one's output.

| Step | Script | Input → Output |
|------|--------|----------------|
| 1. Scrape  | `R/scrape_all_certificates.R`  | live website → `data/pvp_certificates_all.csv` |
| 2. Clean   | `R/clean_pvp_certificates.R`   | `…_all.csv` → `data/pvp_certificates_clean.csv` |
| 3. Figures | `R/analyze_pvp_certificates.R` | `…_clean.csv` → `figures/*.png` (13 standalone charts) |
| 4. Dashboard | `index.qmd`, `analysis.qmd` (via `R/prep_dashboard.R`) | `…_clean.csv` → the two-page website (`_site/`) |

Extras:
- `R/parse_pvp_certificates.R`: a manual helper for parsing a single registry page
  (`plantauthority.gov.in/node/...`) into a tidy CSV. Not part of the automated pipeline.
- `R/interactive_figures.R`: standalone interactive **plotly** HTML versions of the
  time-series charts, independent of the Quarto site.

### Cleaning notes
- Category/sector/crop labels are case-normalised (`FARMER`/`farmer` → `Farmer`, etc.).
- **Years** are extracted by regex from the (inconsistently formatted) issue-date field;
  all time-series use **year of certificate issue**.
- **SAU** is a sector value the register itself assigns; the pipeline does not derive it
  from applicant names, it just passes the register's own `applicant_category` field
  through unchanged (after normalising case and whitespace).
- **Cotton ploidy** (diploid/tetraploid) is read from the crop field.

---

## Methodology notes

### Company name deduplication

The same firm appears under many spellings in the raw register, for example
`Nuziveedu Seeds Limited`, `Nuziveedu Seeds Ltd`, and `Nuziveedu Seeds Pvt Ltd.`. If left
unmerged, any concentration measure built on top of it (market share, Gini coefficient,
"top firms" charts) is artificially deflated, since one real company is being counted as
several smaller ones.

Two functions in `R/prep_dashboard.R` handle this, applied in sequence as
`alias_company(canon_company(applicant))`:

- **`canon_company()`** strips punctuation, normalises `&` to "and", singularises
  "seeds" → "seed", strips common legal-form suffixes (`Private`, `Pvt`, `Ltd`,
  `Limited`, `LLP`, `Company`, `Co`, `Corporation`, `Corp`, `Incorporated`, `Inc`), and
  strips leading `M/S` / `Messrs` prefixes.
- **`alias_company()`** merges a short list of known aliases that share no common
  substring with `canon_company()` alone, for example Mahyco and Maharashtra Hybrid
  Seeds Company, or the various Monsanto entity names.

This is a heuristic, not a corporate-registry lookup, so it will not catch every
possible variant (a genuine typo, an unlisted acronym, a completely different legal
name for the same beneficial owner). Anyone extending the analysis should spot-check the
top firms by grouping raw `applicant` strings under each canonical key and eyeballing
whether anything that should have merged didn't.

### Concentration: Lorenz curve and Gini coefficient

Used on the "How concentrated is private cotton ownership?" chart in the full analysis,
and computed per-crop for the interactive Gini explorer on the landing page.

For a given crop (or crop group), let $x_1, x_2, \ldots, x_n$ be the certificate counts
held by its $n$ distinct private applicants (after deduplication), sorted ascending so
that $x_{(1)} \le x_{(2)} \le \cdots \le x_{(n)}$.

**Lorenz curve.** The cumulative share of certificates held by the smallest $k$ firms,
against the cumulative share of firms itself:

$$
L\!\left(\frac{k}{n}\right) = \frac{\displaystyle\sum_{i=1}^{k} x_{(i)}}{\displaystyle\sum_{i=1}^{n} x_{(i)}}, \qquad k = 0, 1, \ldots, n
$$

If every firm held an identical number of certificates, $L(p) = p$ for every $p$: the
45° line of perfect equality. The further the observed curve sags below that line, the
more concentrated ownership is. The shaded area on the chart shows this directly.

**Gini coefficient.** Defined as twice the area between the line of equality and the
Lorenz curve:

$$
G = 1 - 2\int_0^1 L(p)\, dp
$$

which, for the sorted discrete counts above, reduces to the closed-form expression
implemented directly in `gini()`:

$$
G = \frac{2\displaystyle\sum_{i=1}^{n} i \cdot x_{(i)}}{n\displaystyle\sum_{i=1}^{n} x_{(i)}} - \frac{n+1}{n}
$$

```r
# R/prep_dashboard.R
gini <- function(x){
  x <- sort(x)
  n <- length(x)
  if (n <= 1 || sum(x) == 0) return(NA_real_)
  (2 * sum(seq_len(n) * x) / (n * sum(x))) - (n + 1) / n
}
```

$G = 0$ means every firm holds an equal share of certificates in that crop; $G = 1$
means a single firm holds all of them. Gini is unstable with very few observations, so
the interactive per-crop explorer excludes any crop with fewer than 5 distinct private
applicants. Below that threshold the statistic isn't meaningful.

### Figures in the prose are computed live, not hardcoded

Every specific number quoted in `analysis.qmd`'s write-up, firm names and their
percentages, EDV and VCK counts, the cotton applicant split, peak years, is computed by
inline R at render time from whatever `data/pvp_certificates_clean.csv` currently
contains, rather than typed in by hand. That means the weekly data refresh updates the
prose along with the charts: if a new firm overtakes Nuziveedu next year, or the EDV
count changes, the text describing it changes too on the next render, nobody has to
remember to go back and edit a sentence.

The `setup` chunk at the top of `analysis.qmd` computes these once (register span, EDV
totals, cotton applicant splits, VCK splits, top-firm rankings and their prose) so every
caption that cites the same fact pulls from the same variable, and can't drift out of
sync with a different caption citing the same thing. The `top_firms_ranked()` and
`top_firms_prose()` helpers in `R/prep_dashboard.R` turn a firm ranking directly into
readable text, for example `"Nuziveedu Seed (30.1 percent), Prabhat Agri Biotech (11.8
percent), and Mahyco (7.1 percent)"`, so a chart and the sentence describing it are
always built from the same underlying ranking.

---

## Codebook

Derived fields in `pvp_certificates_clean.csv` beyond a straight clean-up of the
register's own columns, and known limitations of the underlying data. Written up here
because a paper analysing this register cites specific figures from it, and anyone
trying to reproduce those figures needs to know exactly how each derived field is
built, not just that it exists.

### `crop_clean` and `is_cotton`

The register's own `crop` field has inconsistent capitalisation for the same crop
(`Pearl millet` / `Pearl Millet` / `pearl millet`, `Diploid Cotton` / `Diploid cotton`,
20 such groups in total as of the Sept 2026 pull). `crop_clean` is the title-cased,
whitespace-squished form, used as the canonical crop name everywhere a crop needs to be
matched or counted.

**`is_cotton` is `TRUE` only where `crop_clean` is `"Tetraploid Cotton"` or `"Diploid
Cotton"`.** An earlier version of this pipeline defined it as *either* the crop name
containing "cotton" *or* `crop_group == "Fibre Crops"` -- which also matches Jute, since
Jute shares the Fibre Crops group with cotton in the register's own taxonomy. That
inflated every "cotton" figure by however many Jute certificates existed at the time.
**`crop_group == "Fibre Crops"` is a deliberately larger, different set** (cotton +
Jute) and remains available unchanged for anything actually asking about fibre crops as
a group, not cotton specifically. Do not use `crop_group` as a proxy for cotton.

### `expiry_date`, `term_years`, `is_live`, `is_revoked`

`maximum_protection_period_up_to` (expiry) and `provisional_protection_claim` (a sparse
date-range string) are carried through from the raw scrape, which previously dropped
both.

Parsing handles three date formats found in the raw register, tried in order:
`"16 September 2012"`, `"28-November-2038"` (hyphens are normalised to spaces before
parsing, so the first two formats share one parse step), and a small number of rows
(3, as of the Sept 2026 pull, recurring across both the issue-date and expiry-date
columns) in `"Friday, January 16, 2037"` format, seemingly from an older export.

One certificate, registration `59 of 2016`, is the well-known FL 2027 potato case: its
expiry field holds free text noting the certificate was **revoked** rather than a plain
date (`"31/01/2031 (Registration Certificate revoked as per order dated 3rd December,
2021 ...)"`). This is the *only* place anywhere in the register that a revocation is
recorded at all (see "Fields the Rules require but the register omits" below) --
losing it to a failed date parse would throw away the one piece of revocation data the
register happens to expose. It's handled explicitly:
- `is_revoked` is `TRUE` for this row (detected by the word "revok" in the raw field).
- `revocation_note` carries the full free text for this row, `NA` elsewhere.
- `expiry_date` still gets the embedded date (`2031-01-31`) parsed out, for reference.
- **`is_live` is forced `FALSE` regardless of that date** -- a revoked certificate's
  protection ended at revocation, not at its originally scheduled expiry.

`term_years` is `(expiry_date - issue_date) / 365.25`. Its median varies sharply by
`variety_category` (roughly 15.0 years for Farmer / New / EDV / Extant (VCK), but only
~7.6 for Extant and ~11.5 for Extant (Notified)) for a statutory reason, not a data
error: s.24(6) of the Act dates the 15-year cap for Seeds-Act-notified extant varieties
from the date of **notification**, not registration, so those categories carry a
shorter effective term measured from issue.

`is_live` compares `expiry_date` against an explicit **reference date**, recorded in
`data/reference_date.txt` alongside the cleaned CSV every time the pipeline runs (the
same pattern as `last_updated.txt`). It is **not** silently computed against "today" at
whatever moment someone happens to open the data -- `Rscript R/clean_pvp_certificates.R
[in] [out] [reference_date]` takes it as an explicit third argument, defaulting to the
run date only when not supplied. The live, weekly-refreshed dashboard uses that default
(each week's refresh is still an explicit, displayed date, just one that advances week
to week); a frozen data release meant to back a specific paper's figures should instead
pass a **fixed** reference date, recorded here, so that `is_live` never changes if the
release is reprocessed later.

> **Caveat for anyone comparing expiry/live rates across sectors:** Farmer-category
> certificates show a near-zero non-live count (9 of several thousand, as of the Sept
> 2026 pull) not because farmer varieties are unusually durable, but because the Farmer
> category is young -- a small fraction were issued before 2013, and the majority were
> issued in the last few years, against a 15-year term. A cross-sector comparison of
> "share expired" or "share live" will read as a durability difference when it is
> actually an age-distribution artefact, unless it explicitly controls for the age
> profile of each sector's certificates. Label such a comparison accordingly, or don't
> make it.

### Applicant tiers: `applicant_norm`, `applicant_entity`, `owner_group`

Three progressively broader notions of "who holds this certificate," because collapsing
them into one number silently picks a methodology. Computed against the same raw pull
the paper's audit used (the 10,802-row pull of 2026-08-09), this pipeline now reproduces
the audit's figures exactly for Tiers 1 and 2, and within one entity of Tier 3 (see the
one open item below) -- see `R/test_clean_pvp_certificates.R`.

- **`applicant_norm`** (Tier 1, "as published"): the register's own `applicant` string,
  with only mechanical spelling/legal-suffix normalisation applied -- strips `M/S`/
  `Messrs` prefixes and reissue/corrigendum annotations, canonicalises legal suffixes
  (`Pvt Ltd`/`Pvt Limited` → `Private Limited`, `P Ltd` → `P Limited`, `Co Ltd` →
  `Co Limited`, bare `Ltd` → `Limited`), strips periods, and title-cases with a small
  validated acronym-preserve list (`DCM`, `JK`, `LP`). No brand- or parent-company
  judgment call happens at this tier -- `"Monsanto Holding Pvt Ltd"`, `"Monsanto
  Holdings Pvt Ltd"`, and `"Monsanto India Limited"` stay three distinct Tier-1 names,
  since as filed with the Authority they are three distinct legal names.
- **`applicant_entity`** (Tier 2, "same legal entity"): `applicant_norm` folded further
  wherever two register names are confirmed, by a shared Corporate Identification
  Number, to be the same legal entity under a different name -- the eight pairs in
  `data/same_entity_merges.csv`.
- **`owner_group`** (Tier 3, "ownership-adjusted"): `applicant_entity` folded again
  wherever a documented, evidence-backed ownership relationship (majority control,
  verified by CIN, regulatory filing, or rating-agency disclosure -- never a bare
  promoter-family or director link) puts two entities under one controlling group --
  `data/A1_ownership_crosswalk.csv`. An entity with no row there is its own group,
  never silently merged. `data/A2_considered_not_merged.csv`,
  `A3_related_entities_absent.csv`, `A5_control_verification.csv`, and
  `A6_larger_holders_examined.csv` are the supporting evidence, deposited alongside as
  supplementary files, not regenerated.
  **This tier must never be used for period/time-series concentration** -- several of
  the underlying relationships postdate certificates they would otherwise govern (most
  of Bayer's former-Monsanto certificates were filed before the 2018 acquisition; a
  large share of NSL's Prabhat/Pravardhan certificates predate the 2011 acquisitions
  that brought them into the group). Use Tier 1 or 2 for anything time-series.

**How Tier 1 is actually computed**, since a mechanical rule alone doesn't reach the
audited count: a validated dictionary (`data/applicant_normalisation_lookup.csv`, every
applicant string the audit has already resolved) is checked first, so historical
figures reproduce exactly regardless of any edge case in the mechanical rule. A second,
smaller table (`data/entity_exceptions.csv`) covers the specific residue the mechanical
rule can't derive on its own -- private→public conversions, trade-name changes,
typo-renames -- applied by exact match on the as-filed string. Only a genuinely new
applicant string (not in either table) falls through to the mechanical rule directly.
This is not a shortcut: the mechanical rule was validated by running it against every
one of the 236 known applicants and diffing against the audited answer -- 235 matched
immediately, and the one residual mismatch (`"Bayer CropScience LP"`, whose camelCase
spelling the rule doesn't split) was folded into `entity_exceptions.csv` rather than
special-cased away, per "let the diff define the exception set, don't hand-sort."

**Weekly-refresh triage.** Any applicant string not already in
`applicant_normalisation_lookup.csv` is queued to `data/applicant_review_queue.csv`
(private sector only -- Tiers 2/3 don't apply elsewhere, and the lookup was never
meant to cover the thousands of distinct farmer names). Its `applicant_norm` is still
computed immediately by the mechanical rule (degrade-safe: it appears as itself, never
silently merged into an existing entity or ownership group it hasn't been checked
against), but Tier 3 in particular should not be trusted for a brand-new name until a
person has reviewed it and, if warranted, added a row to `A1_ownership_crosswalk.csv`
-- majority control needs documentary evidence a script can't gather on its own. Tiers
1 and 2 refresh automatically every week; Tier 3 only changes after that review.

**One open item:** `owner_group` currently gives 106 distinct private groups against
the audited 105. The gap is one specific, fully diagnosed row: `A1_ownership_crosswalk.csv`
assigns `"Devgen Nv"` (16 certificates) to group `"Syngenta"`, but has no row at all for
`"Syngenta India Limited"` (224 certificates) itself, so it defaults to standing as its
own group under its own name instead of joining `"Syngenta"` -- 224 + 16 = 240, matching
the Syngenta group total in the original brief exactly, confirming this is a missing
row rather than a disagreement about the grouping. Needs either an explicit
`"Syngenta India Limited" -> "Syngenta"` row added to `A1_ownership_crosswalk.csv`, or
`Devgen Nv`'s assigned group renamed to `"Syngenta India Limited"` (this pipeline does
not invent or correct crosswalk rows on its own -- they're evidence-backed and
human-maintained).

### Known data-quality issues in the register itself

These are limitations of the Authority's own published register, not of this pipeline.
Documented here rather than silently corrected, so they don't get mistaken for pipeline
bugs later.

- **Sector misclassification.** `applicant_category` codes roughly 15 certificates as
  Private that belong to public bodies -- e.g. MACS Agharkar Research Institute and
  Agharkar Research Institute (the same institute, two names, both coded Private),
  Vasantdada Sugar Institute, National Dairy Development Board, Maharashtra State Seeds
  Corporation (coded under *both* Public and Private across different certificates),
  Cornell University, University of Maine System Board of Trustees, and Instituto de
  Investigaciones Agropecuarias (Chile). Immaterial to headline sector shares, but
  `sector`/`applicant_category` is unreliable at the margin -- don't treat it as ground
  truth for any specific institution.
- **The register does not track corporate existence.** Several certificate holders are
  companies that no longer exist under that name: Monsanto India Limited (amalgamated
  into Bayer CropScience, 2019), Metahelix Life Sciences (amalgamated into Rallis
  India, 2019), Monsanto Genetics India (amalgamated; last filed accounts 2007), and at
  least one case of a company holding certificates filed years before its own
  incorporation date under a later corporate name (Advanta Enterprises Limited,
  incorporated 2 June 2022, holds certificates with filing dates from 2013 -- almost
  certainly a name carried over from a predecessor entity, not evidence of the
  register's dates being wrong). A name-level concentration measure will therefore
  understate concentration purely from unmerged corporate history, before any
  ownership question is even asked.
- **Fields Rule 23 requires but the published register omits.** Rule 23 of the PPVFR
  Rules 2003 requires the Register to record expiry date (item 14, recovered here from
  the raw scrape -- see above), revocation date and grounds (item 15, surfaced by the
  register in exactly one case, as free text in the expiry field -- see `is_revoked`
  above), and licensee names and licence terms (item 20, not surfaced anywhere). Rule
  22(7)-(8) also require the Authority to maintain seed production and sales records;
  none of this is public. This defines the outer boundary of what this dataset can show
  -- no analysis of licensing or seed-production volume is possible from this source at
  all.
- **A handful of rows have expiry one day before issue.** Six certificates as of the
  Sept 2026 pull (`535 of 2014`, `REG/2017/916`, `REG/2017/1021`, `REG/2017/1031`,
  `REG/2017/1032`, `REG/2017/1040`) have `maximum_protection_period_up_to` exactly one
  calendar day *before* `date_of_certificate_issue` -- almost certainly a register-side
  date entry error (all five `REG/2017/9xx`/`REG/2017/10xx` rows share the same issue
  date, suggesting a batch entry mistake), not a parsing artefact here. `term_years`
  is left as the resulting (trivially negative, about -1/365.25) computed value rather
  than silently corrected, and `is_live` is correctly `FALSE` for all six.
- **No location field.** The register records no state, district, or address for any
  applicant. Any geographic analysis is impossible from this source; there is no field
  to recover it from.
- **`date_of_filling` uses a verbose format** (`"Wednesday, March 29, 2017"`) more often
  than the other two date fields do; `date_filed_raw` carries it through unparsed
  (nothing downstream currently needs a parsed filing date), but the same
  weekday-prefixed style is one of the two formats `parse_ppvfr_date()` handles for
  `issue_date`/`expiry_date`, see above.
- **`is_complete` is `FALSE` for 2 rows** (as of the Sept 2026 pull) -- rows with no
  variety name recorded. Left in the data rather than dropped; filter on `is_complete`
  if a variety name is required for the analysis at hand.
- **Raw-vs-clean row count is a period filter, not a data-quality drop.** The paper's
  cited figures compare complete calendar years through 2025, so its snapshot excludes
  the 340 certificates issued in January 2026 or later (a partial year at the time of
  that pull) via an `issue_year <= 2025` filter -- not a cleaning rule. This pipeline's
  `pvp_certificates_clean.csv` for the *live* dashboard deliberately does **not** apply
  this filter (a continuously-refreshed dataset that permanently excluded "this year so
  far" would defeat the point of the weekly refresh); a frozen release meant to
  reproduce the paper's exact figures should pass the cutoff year explicitly --
  `Rscript R/clean_pvp_certificates.R [in] [out] [reference_date] 2025` -- which is
  what makes the 10,802-row pull of 2026-08-09 reduce to exactly 10,462 rows here too.

---

## Usage

Requires **R (≥ 4.1)** and **[Quarto](https://quarto.org/docs/get-started/)**.

Install the R packages once:

```r
install.packages(c(
  "rvest", "httr", "dplyr", "readr", "janitor", "purrr", "stringr",
  "tidyr", "lubridate", "ggplot2", "forcats", "scales",
  "plotly", "htmlwidgets", "knitr", "rmarkdown"
))
```

Then, from the repo root, run the pipeline:

```sh
Rscript R/scrape_all_certificates.R     # fetch the full register
Rscript R/clean_pvp_certificates.R      # build the clean dataset
Rscript R/analyze_pvp_certificates.R    # (optional) render the 13 standalone figures
Rscript R/interactive_figures.R         # (optional) standalone interactive HTML charts
```

...and build the dashboard:

```sh
quarto render      # builds both pages into _site/
quarto preview      # live-reloading local preview in your browser
```

The scraper caches each page under `data/pages/`; delete that folder to force a fully
fresh pull.

> **Windows tip:** close the CSVs in Excel before running. An open file locks it, and
> the scripts/git will fail to write.

---

## Figures

The 13 static figures in `analyze_pvp_certificates.R` (git-ignored, regenerated on
demand into `figures/`) cover the same ground as the dashboard's "Certificates at a
glance" and cotton sections, useful for anyone who wants standalone PNGs rather than the
interactive site:

1. Total certificates per year, all crops
2. Certificates per year, cotton
3. Crop-group-wise totals
4. Variety-category-wise totals
5. Farmers' varieties issued per year
6. Public applicants by category × year
7. Private applicants by category × year
8. Applicant category, cotton vs all crops
9. Cotton by ploidy × applicant
10. Cotton applicant composition over time
11. Cotton by variety category × applicant
12. Private cotton by category × year
13. Major private cotton applicants (share)

A consistent colour palette is used across figures and the dashboard alike (Farmer =
green, Private = blue, Public = red, SAU = orange, Individual Breeder = purple; EDV =
purple in the variety-category palette) so charts line up visually side by side.

---

## Automation

A GitHub Actions workflow (`.github/workflows/weekly-update.yml`) runs the full pipeline
**every Sunday (06:00 UTC)**, entirely on GitHub's servers:

1. Re-scrapes the register and rebuilds the clean dataset (`R/scrape_all_certificates.R`,
   `R/clean_pvp_certificates.R`) and the 13 standalone figures (`R/analyze_pvp_certificates.R`).
2. Commits refreshed data back to the repo, but only when the register actually changed,
   updating `data/last_updated.txt`.
3. Renders both Quarto pages (`quarto render`) and publishes the result to **GitHub
   Pages**.

It can also be triggered manually from the repo's **Actions** tab (*Run workflow*), and
runs automatically on any push to `main` that touches a `.qmd` file, `_quarto.yml`, or
any `.R` file.

A local Windows alternative (`run_update.ps1` + Task Scheduler) is included for running
the same pipeline on your own machine instead of the cloud.

---

## Repository layout

```
.
├── index.qmd                      # Explore the data (dashboard homepage, only page in site nav)
├── analysis.qmd                   # Full analysis (write-up + cotton case study); not linked in site nav
├── _quarto.yml                    # Quarto project + navbar + light/dark theme config
├── styles.css                     # Section dividers, chart-card styling, dark-mode-safe colours
├── R/
│   ├── prep_dashboard.R           # shared data prep, palettes, dedup, gini() -- sourced by both .qmd pages
│   ├── scrape_all_certificates.R  # 1. scrape
│   ├── parse_pvp_certificates.R   # manual single-page parsing helper
│   ├── clean_pvp_certificates.R   # 2. clean
│   ├── analyze_pvp_certificates.R # 3. standalone figures (13 PNGs)
│   └── interactive_figures.R      # standalone interactive plotly charts
├── run_update.ps1                 # local (Windows) weekly runner, alternative to CI
├── .github/workflows/
│   └── weekly-update.yml          # cloud weekly automation + GitHub Pages publish
├── data/                          # generated datasets (+ last_updated.txt)
└── figures/                       # generated standalone charts (git-ignored)
```

---

## License

This project is dual-licensed:

- **Code** (R scripts, Quarto document code, configuration files): [MIT License](LICENSE).
  Use, copy, modify, and distribute freely, minimal restrictions.
- **Data, written analysis, and visualisations**: [CC BY 4.0](LICENSE-DATA).
  Share and adapt for any purpose, including commercially, as long as you give
  appropriate credit.

Both license files contain only the standard, unmodified license text (so GitHub and
other tooling can detect them correctly). This section is where the project-specific
context lives instead.

## How to cite

If you use this tool or its data, please cite it:

> Subash, Ambika. 2026. "Who owns India's plant varieties? PVP Certification Explorer
> (India)." Centre for Economic Studies and Planning, Jawaharlal Nehru University.
> <https://doi.org/10.5281/zenodo.21140353>

BibTeX:

```bibtex
@misc{subash2026pvp,
  author      = {Subash, Ambika},
  title       = {Who owns {India}'s plant varieties? {PVP} Certification Explorer ({India})},
  year        = {2026},
  institution = {Centre for Economic Studies and Planning, Jawaharlal Nehru University},
  doi         = {10.5281/zenodo.21140353},
  url         = {https://doi.org/10.5281/zenodo.21140353},
  note        = {Data updated weekly}
}
```

The DOI `10.5281/zenodo.21140353` is the concept DOI: it always resolves to the latest
released version. Each release also gets its own version-specific DOI on Zenodo if you
need to cite an exact snapshot.
