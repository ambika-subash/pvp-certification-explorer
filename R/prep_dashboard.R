#!/usr/bin/env Rscript
# Shared data prep + palettes + helpers for both index.qmd (explorer) and
# analysis.qmd (full write-up). Sourced by both, so there's one source of
# truth for column names, colours, and the private-firm-name merging logic.

library(dplyr); library(readr); library(tidyr); library(stringr)
library(ggplot2); library(forcats); library(scales); library(plotly)

d <- read_csv("data/pvp_certificates_clean.csv", show_col_types = FALSE)

yr_min <- 2009L
theme_set(theme_minimal(base_size = 13) + theme(
  axis.title.x = element_text(margin = margin(t = 10)),
  axis.title.y = element_text(margin = margin(r = 10))
))
accent <- "#0d9488"   # teal - generic/non-category charts (certs over time, crop groups)
muted  <- "#6b7280"   # grey - deliberate backdrop colour (e.g. "All crops" baseline bars)
cat_cols <- c("Farmer"="#4daf4a","New"="#377eb8","Extant"="#80b1d3",
              "Extant (Notified)"="#ff7f00","Extant (VCK)"="#e41a1c","EDV"="#984ea3")
sector_cols <- c("Farmer"="#4daf4a","Private"="#377eb8","Public"="#e41a1c",
                 "SAU"="#ff7f00","Individual Breeder"="#984ea3")
ploidy_cols <- c("Diploid"="#377eb8","Tetraploid"="#e41a1c")
set_cols    <- c("All crops"=accent,"Cotton"="#e41a1c")
sector_levels <- c("Farmer","Private","Public","SAU","Individual Breeder")
cat_levels    <- c("Farmer","New","Extant","Extant (Notified)","Extant (VCK)","EDV")
paper_groups  <- c("Cereals","Fibre Crops","Vegetables","Legumes","Oilseeds","Fruits","Sugar Crops")

d <- d %>% mutate(
  crop_bucket      = ifelse(crop_group %in% paper_groups, crop_group, "Others"),
  sector           = factor(sector, levels = sector_levels),
  variety_category = factor(variety_category, levels = cat_levels))
dd  <- d %>% filter(!is.na(issue_year), issue_year >= yr_min)
cot <- dd %>% filter(is_cotton) %>%
  mutate(ploidy = case_when(
    str_detect(crop, regex("tetraploid", ignore_case = TRUE)) ~ "Tetraploid",
    str_detect(crop, regex("diploid",    ignore_case = TRUE)) ~ "Diploid",
    TRUE ~ NA_character_))

## collapse company-name spelling variants (Ltd / Ltd. / Limited, Pvt / Private…)
canon_company <- function(x){
  y <- str_to_lower(x)
  y <- str_replace(y, "^\\s*(m/s\\.?|messrs\\.?)\\s+", "")  # strip "M/S" / "Messrs" prefix
  # strip administrative reissue/correction annotations entirely -- the
  # register appends things like "(reissued with address change, old serial
  # no. 12345)" when a certificate is reissued, and the serial number
  # differs every time, which otherwise splits one firm into many distinct
  # canonical keys (this is what was fragmenting Pioneer Overseas
  # Corporation into a dozen-plus "different" firms). These annotations
  # sometimes contain nested parentheses of their own (e.g. a former name
  # in brackets inside the reissue note), so strip from the opening marker
  # straight to the end of the string rather than trying to match a single
  # balanced parenthetical -- it is always a trailing block, never followed
  # by other legitimate content.
  y <- str_replace(y, "\\((reissu\\w*|corrigend\\w*).*$", "")
  y <- str_replace_all(y, "[.,()/]", " ")
  y <- str_replace_all(y, "&", " and "); y <- str_replace_all(y, "\\bseeds\\b", "seed")
  # spelling/spacing noise for the same entity, not a different legal
  # entity: "Sciences" vs "Science", "Crop Science" vs "CropScience". Legal
  # jurisdiction suffixes (LP / AG / Ltd) are left untouched by this, so
  # entities that are genuinely different (e.g. a US LP vs a German AG)
  # still end up as separate keys after the suffix-stripping step below.
  y <- str_replace_all(y, "\\bsciences\\b", "science")
  y <- str_replace_all(y, "crop\\s*science", "cropscience")
  # "P Ltd" is a common Indian abbreviation for "Private Limited"; only
  # collapse it in that specific adjacent position, not standalone "P"
  # elsewhere, since that could be a legitimate initial in some other name
  y <- str_replace_all(y, "\\bp\\s+ltd\\b", "ltd")
  y <- str_replace_all(y, "\\b(private|pvt|limited|ltd|llp|company|co|corporation|corp|incorporated|inc)\\b", " ")
  str_squish(y)
}
alias_company <- function(key) case_when(
  str_detect(key, "maharashtra hybrid seed") | key == "mahyco" ~ "mahyco",
  str_detect(key, "^monsanto") ~ "monsanto",
  str_detect(key, "^pioneer overseas") ~ "pioneer overseas",
  # genuine data-entry typos ("Sees" for "Seeds", "Hybris" for "Hybrid") plus
  # a location suffix, none of which canon_company()'s regex can generalise
  str_detect(key, "^shakti vardhak") ~ "shakti vardhak hybrid seed",
  str_detect(key, "^ganga kaveri seed") ~ "ganga kaveri seed",
  TRUE ~ key)
pretty_names <- c("mahyco" = "Mahyco (Maharashtra Hybrid Seeds)", "monsanto" = "Monsanto",
                  "pioneer overseas" = "Pioneer Overseas Corporation",
                  "shakti vardhak hybrid seed" = "Shakti Vardhak Hybrid Seeds")

# Gini coefficient of a vector of firm-level counts: 0 = every firm holds an
# equal share, 1 = one firm holds everything.
gini <- function(x){
  x <- sort(x)
  n <- length(x)
  if (n <= 1 || sum(x) == 0) return(NA_real_)
  (2 * sum(seq_len(n) * x) / (n * sum(x))) - (n + 1) / n
}

# Full ranked, deduplicated, labelled list of private firms in df (one row
# per firm, not bucketed into "Others"). Both the chart and any inline text
# stats about "the top N firms" should be built from this, so a number
# quoted in prose can never drift out of sync with what a chart shows.
top_firms_ranked <- function(df){
  priv <- df %>% filter(applicant_category == "Private") %>%
    mutate(key = alias_company(canon_company(applicant)))
  labels <- priv %>% count(key, applicant) %>% group_by(key) %>%
    slice_max(n, n = 1, with_ties = FALSE) %>% ungroup() %>%
    transmute(key, label = coalesce(unname(pretty_names[key]), applicant))
  priv %>% count(key, name = "n") %>% left_join(labels, by = "key") %>%
    arrange(desc(n)) %>% mutate(pct = 100 * n / sum(n))
}

# "and"-joined prose list like "A (10%), B (8%), and C (5%)" from the top
# n_top rows of a top_firms_ranked() table.
top_firms_prose <- function(ranked, n_top, digits = 1){
  top <- ranked %>% slice_head(n = n_top)
  parts <- paste0(top$label, " (", round(top$pct, digits), " percent)")
  if (length(parts) <= 1) return(parts)
  paste0(paste(parts[-length(parts)], collapse = ", "), ", and ", parts[length(parts)])
}

top_firms_bar <- function(df, n_top = 8, title){
  f <- top_firms_ranked(df) %>%
    mutate(label = ifelse(row_number() <= n_top, label, "Others")) %>%
    group_by(label) %>% summarise(n = sum(n), .groups = "drop") %>% arrange(n)
  ggplot(f, aes(x = n, y = fct_reorder(label, n))) +
    geom_col(fill = sector_cols[["Private"]]) +
    geom_text(aes(label = comma(n)), hjust = -0.2, size = 3) +
    scale_x_continuous(labels = comma, expand = expansion(mult = c(0, .18))) +
    labs(title = title, x = "Certificates", y = NULL)
}

## ---- shared prep for the interactive explorer (index.qmd) ----------------
top_crops <- d %>% filter(!is.na(crop)) %>% count(crop, sort = TRUE) %>%
  slice_head(n = 20) %>% pull(crop)
# diploid cotton is a small share of an already-small subset, so it rarely
# clears the top-20-by-volume cutoff above; force it into the dropdown list
# regardless of rank so it stays explorable
diploid_crops <- d %>% filter(!is.na(crop), str_detect(str_to_lower(crop), "diploid")) %>%
  distinct(crop) %>% pull(crop)
top_crops <- union(top_crops, diploid_crops)
crop_categories <- sort(unique(na.omit(d$crop_bucket)))

# tag rows under both their crop group and individual crop name, so either
# the category dropdown or the crop dropdown can filter the same dataset
sel_for <- function(df) bind_rows(
  df %>% filter(!is.na(crop_bucket)) %>% mutate(sel = as.character(crop_bucket)),
  df %>% filter(crop %in% top_crops)  %>% mutate(sel = crop))
chr <- function(df) df %>% mutate(across(where(is.factor), as.character))

n_total <- nrow(d)
last_updated <- tryCatch(sub("^Last updated: ", "", readLines("data/last_updated.txt", warn = FALSE)[1]),
                         error = function(e) format(Sys.Date()))
