# PVP Certification Explorer (India)

An R + Quarto project on India's Plant Variety Protection (PVP) certificates, issued
under the Protection of Plant Varieties & Farmers' Rights Act (PPVFRA), 2001. The full
register is scraped, cleaned, and analysed automatically every week and published as a
two-page interactive dashboard.

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

The site is a two-page [Quarto](https://quarto.org) website, rebuilt automatically every
week from the latest data.

| Page | File | What it's for |
|------|------|----------------|
| **Explore the data** | `index.qmd` | The landing page. Interactive charts (built with Observable Plot inside Quarto's OJS engine) that let you ask the paper's questions of *any* crop, not just cotton: certificate trends, applicant composition, firm-level concentration, a per-crop Gini concentration score, variety category breakdown, cumulative ownership over time, and a full crop-comparison tool. Every chart has a "Save chart as PNG" export button. Firm lookup starts with a browsable top-25 ranking, then a searchable table of every private applicant's crop-by-crop footprint. |
| **Full analysis** | `analysis.qmd` | The write-up: an overview of the register, the headline findings (including a Lorenz curve and Gini coefficient for private cotton ownership), and a detailed cotton case study covering ploidy, VCK enclosure, and EDV registrations. |

Both pages source `R/prep_dashboard.R`, which is the single place data loading, colour
palettes, the company-name deduplication logic, and the Gini function live. That way both
pages always agree on the numbers.

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
| `pvp_certificates_clean.csv` | Cleaned/analysis-ready: normalised categories & sectors, parsed years, cotton & ploidy flags. |
| `last_updated.txt`           | Timestamp of the last successful refresh. |

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
├── index.qmd                      # Explore the data (dashboard homepage)
├── analysis.qmd                   # Full analysis (write-up + cotton case study)
├── _quarto.yml                    # Quarto project + navbar config
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
