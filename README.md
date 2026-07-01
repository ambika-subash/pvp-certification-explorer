# PVP Certification Explorer (India)

R-based exploratory project on India's Plant Variety Protection (PVP) certificates,
issued under the Protection of Plant Varieties & Farmers' Rights Act (PPVFRA), 2001.

**Focus**
- Who dominates PVP certificates over time (private firms vs public institutions vs farmers).
- How crop-wise and firm-wise concentration evolves, with a particular lens on **cotton**, as it concerns my own research objectives.

This repo is part of a broader portfolio on agritech, biotechnology regulation, and tech-policy analytics.

---

## Data

- **Source**: the PPV&FR Authority's public certificate register:
  <https://plantauthority.gov.in/list-certificates>
- **Coverage**: every granted certificate (~10,500+ and growing), 2007 onward.
- The register is scraped, cleaned, and analysed entirely in R. A weekly job keeps the
  dataset current automatically (see [Automation](#automation)).
- The data is published at https://ambika-subash.github.io/pvp-certification-explorer/ .

Generated data files (tracked in `data/`):

| File | Description |
|------|-------------|
| `pvp_certificates_all.csv`   | Raw scrape of the full register (one row per certificate). |
| `pvp_certificates_clean.csv` | Cleaned/analysis-ready: normalised categories & sectors, parsed years, cotton & ploidy flags, SAU split. |
| `last_updated.txt`           | Timestamp of the last successful refresh. |

---

## Pipeline

Three scripts, run in order. Each reads the previous one's output.

| Step | Script | Input → Output |
|------|--------|----------------|
| 1. Scrape  | `scrape_all_certificates.R`  | live website → `data/pvp_certificates_all.csv` |
| 2. Clean   | `clean_pvp_certificates.R`   | `…_all.csv` → `data/pvp_certificates_clean.csv` |
| 3. Figures | `analyze_pvp_certificates.R` | `…_clean.csv` → `figures/*.png` (13 charts) |

Extras:
- `interactive_figures.R` - interactive **plotly** HTML versions of the time-series charts.
- `check_values.R`, `diagnose_raw.R` - quick data-inspection helpers.

### Cleaning notes
- Category/sector/crop labels are case-normalised (`FARMER`/`farmer` → `Farmer`, etc.).
- **Years** are extracted by regex from the (inconsistently formatted) issue-date field;
  all time-series use **year of certificate issue**.
- **SAU** applicants are split out of "Public" using an applicant-name heuristic.
- **Cotton ploidy** (diploid/tetraploid) is read from the crop field.
- For the company chart, spelling variants (`Ltd`/`Ltd.`/`Limited`, `Pvt`/`Private`) and
  known aliases (e.g. Mahyco ↔ Maharashtra Hybrid Seeds) are merged.

---

## Usage

Requires R (≥ 4.1). Install the packages once:

```r
install.packages(c(
  "rvest", "httr", "dplyr", "readr", "janitor", "purrr", "stringr",
  "tidyr", "lubridate", "ggplot2", "forcats", "scales",
  "plotly", "htmlwidgets"
))
```

Then, from the repo root:

```sh
Rscript scrape_all_certificates.R     # fetch the full register
Rscript clean_pvp_certificates.R      # build the clean dataset
Rscript analyze_pvp_certificates.R    # render the 13 figures into figures/
Rscript interactive_figures.R         # (optional) interactive HTML charts
```

The scraper caches each page under `data/pages/`; delete that folder to force a
fully fresh pull.

> **Windows tip:** close the CSVs in Excel before running — an open file locks it and
> the scripts/git will fail to write.

---

## Figures

Thirteen charts are written to `figures/` (git-ignored — regenerated on demand):

1. Total certificates per year - all crops
2. Certificates per year - cotton
3. Crop-group-wise totals
4. Variety-category-wise totals
5. Farmers' varieties issued per year
6. Public applicants by category × year
7. Private applicants by category × year
8. Applicant category - cotton vs all crops
9. Cotton by ploidy × applicant
10. Cotton applicant composition over time
11. Cotton by variety category × applicant
12. Private cotton by category × year
13. Major private cotton applicants (share)

A consistent colour palette is used across figures (e.g. Farmer = green, EDV = purple)
so charts line up visually side by side.

---

## Automation

A GitHub Actions workflow (`.github/workflows/weekly-update.yml`) runs the full pipeline
**every Sunday (06:00 UTC)** on GitHub's servers:

1. Re-scrapes the register, rebuilds the clean dataset and all figures.
2. Commits refreshed data back to the repo (only when the register actually changed),
   updating `data/last_updated.txt`.
3. Uploads the figures as a downloadable **artifact** on the run.
4. Updates the data write-up and figures published at https://ambika-subash.github.io/pvp-certification-explorer/

It can also be triggered manually from the repo's **Actions** tab (*Run workflow*).

A local Windows alternative (`run_update.ps1` + Task Scheduler) is included for running
the same pipeline on your own machine instead of the cloud.

---

## Repository layout

```
.
├── scrape_all_certificates.R      # 1. scrape
├── clean_pvp_certificates.R       # 2. clean
├── analyze_pvp_certificates.R     # 3. figures (13 PNGs)
├── interactive_figures.R          # interactive plotly charts
├── check_values.R, diagnose_raw.R # inspection helpers
├── run_update.ps1                 # local (Windows) weekly runner — alternative to CI
├── .github/workflows/
│   └── weekly-update.yml          # cloud weekly automation
├── data/                          # generated datasets (+ last_updated.txt)
└── figures/                       # generated charts (git-ignored)
```
