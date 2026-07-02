#!/usr/bin/env Rscript
# Interactive (plotly) versions of the PPVFRA time-series charts.
# Usage: Rscript interactive_figures.R [clean.csv] [outdir]
#
# install.packages(c("plotly", "htmlwidgets"))

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr)
  library(plotly); library(htmlwidgets)
})

args    <- commandArgs(trailingOnly = TRUE)
in_file <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "data/pvp_certificates_clean.csv"
out_dir <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "figures/interactive"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

d   <- read_csv(in_file, show_col_types = FALSE) %>%
  filter(!is.na(issue_year), issue_year >= 2009)
cot <- d %>% filter(is_cotton)

# selfcontained = FALSE avoids a pandoc dependency (writes html + a _files dir)
save_html <- function(p, name) {
  f <- file.path(out_dir, name)
  saveWidget(p, f, selfcontained = FALSE)
  message("  wrote ", f)
}

## 1. all crops by year
a <- d %>% count(issue_year)
save_html(
  plot_ly(a, x = ~issue_year, y = ~n, type = "scatter", mode = "lines+markers",
          line = list(color = "#3b6fb6"),
          hovertemplate = "%{x}: %{y} certificates<extra></extra>") %>%
    layout(title = "PPVFRA Certificates Issued — All Crops",
           xaxis = list(title = "Year of certificate issue"),
           yaxis = list(title = "No. of certificates")),
  "all_crops_by_year.html")

## 2. cotton by year
b <- cot %>% count(issue_year)
save_html(
  plot_ly(b, x = ~issue_year, y = ~n, type = "scatter", mode = "lines+markers",
          line = list(color = "#3b6fb6"),
          hovertemplate = "%{x}: %{y} certificates<extra></extra>") %>%
    layout(title = "PPVFRA Certificates Issued — Cotton",
           xaxis = list(title = "Year of certificate issue"),
           yaxis = list(title = "No. of certificates")),
  "cotton_by_year.html")

## 3. cotton applicant composition over time
sector_cols <- c("Farmer" = "#4daf4a", "Private" = "#377eb8", "Public" = "#e41a1c",
                 "SAU" = "#ff7f00", "Individual Breeder" = "#984ea3")
cc <- cot %>% filter(!is.na(sector)) %>% count(issue_year, sector)
save_html(
  plot_ly(cc, x = ~issue_year, y = ~n, color = ~sector, colors = sector_cols,
          type = "scatter", mode = "lines+markers") %>%
    layout(title = "Cotton Variety Certification — Applicant Composition Over Time",
           xaxis = list(title = "Year of certificate issue"),
           yaxis = list(title = "No. of certificates")),
  "cotton_composition_over_time.html")

message("\nDone. Interactive charts in ", out_dir, "/ — open the .html files in a browser.")
