#!/usr/bin/env Rscript
# Build the PPVFRA figures from the cleaned registry.
# Usage: Rscript analyze_pvp_certificates.R [clean.csv] [figdir]

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr)
  library(ggplot2); library(forcats); library(scales); library(stringr)
})

args    <- commandArgs(trailingOnly = TRUE)
in_file <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "data/pvp_certificates_clean.csv"
fig_dir <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "figures"
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

d <- read_csv(in_file, show_col_types = FALSE)

yr_min <- 2009L
theme_set(theme_minimal(base_size = 13))
blue <- "#3b6fb6"
save_fig <- function(p, name, w = 9, h = 5.5) {
  ggsave(file.path(fig_dir, name), p, width = w, height = h, dpi = 150, bg = "white")
  message("  wrote ", file.path(fig_dir, name))
}

# consistent colours across all figures
cat_cols <- c("Farmer" = "#4daf4a", "New" = "#377eb8", "Extant" = "#80b1d3",
              "Extant (Notified)" = "#ff7f00", "Extant (VCK)" = "#e41a1c", "EDV" = "#984ea3")
sector_cols <- c("Farmer" = "#4daf4a", "Private" = "#377eb8", "Public" = "#e41a1c",
                 "SAU" = "#ff7f00", "Individual Breeder" = "#984ea3")
ploidy_cols <- c("Diploid" = "#377eb8", "Tetraploid" = "#e41a1c")
set_cols    <- c("All crops" = "#377eb8", "Cotton" = "#e41a1c")
fill_cat    <- scale_fill_manual(values = cat_cols,    drop = FALSE, na.value = "grey70")
fill_sector <- scale_fill_manual(values = sector_cols, drop = FALSE, na.value = "grey70")
col_sector  <- scale_colour_manual(values = sector_cols, drop = FALSE, na.value = "grey70")

sector_levels <- c("Farmer", "Private", "Public", "SAU", "Individual Breeder")
cat_levels    <- c("Farmer", "New", "Extant", "Extant (Notified)", "Extant (VCK)", "EDV")
paper_groups  <- c("Cereals", "Fibre Crops", "Vegetables", "Legumes",
                   "Oilseeds", "Fruits", "Sugar Crops")

d <- d %>% mutate(
  crop_bucket      = ifelse(crop_group %in% paper_groups, crop_group, "Others"),
  sector           = factor(sector, levels = sector_levels),
  variety_category = factor(variety_category, levels = cat_levels)
)

dd  <- d %>% filter(!is.na(issue_year), issue_year >= yr_min)
cot <- dd %>% filter(is_cotton) %>%
  mutate(ploidy = case_when(
    str_detect(crop, regex("tetraploid", ignore_case = TRUE)) ~ "Tetraploid",
    str_detect(crop, regex("diploid",    ignore_case = TRUE)) ~ "Diploid",
    TRUE ~ NA_character_))

# merge company spelling variants (Ltd / Ltd. / Limited, Pvt / Private, &/and …)
canon_company <- function(x) {
  y <- str_to_lower(x)
  y <- str_replace_all(y, "[.,()]", " ")
  y <- str_replace_all(y, "&", " and ")
  y <- str_replace_all(y, "\\bseeds\\b", "seed")   # seed / seeds -> seed
  # strip legal-form words so "X Ltd" == "X Pvt Ltd" == "X Limited"
  y <- str_replace_all(
    y, "\\b(private|pvt|limited|ltd|llp|company|co|corporation|corp|incorporated|inc)\\b", " ")
  str_squish(y)
}

# merge known aliases whose names share no words (acronyms, parent entities)
alias_company <- function(key) {
  case_when(
    str_detect(key, "maharashtra hybrid seed") | key == "mahyco" ~ "mahyco",
    str_detect(key, "^monsanto")                                 ~ "monsanto",
    TRUE ~ key
  )
}
pretty_names <- c("mahyco"   = "Mahyco (Maharashtra Hybrid Seeds)",
                  "monsanto" = "Monsanto")

## Fig 1
f1 <- dd %>% count(issue_year)
save_fig(ggplot(f1, aes(issue_year, n)) +
           geom_line(color = blue, linewidth = 1) + geom_point(color = blue) +
           geom_text(aes(label = n), vjust = -0.7, size = 3, color = blue) +
           scale_x_continuous(breaks = seq(yr_min, max(f1$issue_year), 2)) +
           labs(title = "Total PPVFRA Certificates Issued — All Crops",
                x = "Year of certificate issue", y = "No. of certificates"),
         "fig01_all_crops_by_year.png")

## Fig 2
f2 <- cot %>% count(issue_year)
save_fig(ggplot(f2, aes(issue_year, n)) +
           geom_line(color = blue, linewidth = 1) + geom_point(color = blue) +
           geom_text(aes(label = n), vjust = -0.7, size = 3, color = blue) +
           scale_x_continuous(breaks = seq(yr_min, max(f2$issue_year), 2)) +
           labs(title = "PPVFRA Certificates Issued — Cotton",
                x = "Year of certificate issue", y = "No. of certificates"),
         "fig02_cotton_by_year.png")

## Fig 3
f3 <- d %>% count(crop_bucket) %>%
  mutate(crop_bucket = fct_relevel(fct_reorder(crop_bucket, n, .desc = TRUE), "Others", after = Inf))
save_fig(ggplot(f3, aes(crop_bucket, n)) +
           geom_col(fill = blue) + geom_text(aes(label = n), vjust = -0.4, size = 3) +
           labs(title = "PPVFRA Certificates — Crop Group Wise", x = NULL, y = "Certificates issued") +
           theme(axis.text.x = element_text(angle = 30, hjust = 1)),
         "fig03_crop_group.png")

## Fig 4
f4 <- d %>% filter(!is.na(variety_category)) %>% count(variety_category)
save_fig(ggplot(f4, aes(variety_category, n, fill = variety_category)) +
           geom_col() + fill_cat + guides(fill = "none") +
           geom_text(aes(label = n), vjust = -0.4, size = 3) +
           labs(title = "PPVFRA Certificates — Category Wise", x = NULL, y = "Certificates issued"),
         "fig04_variety_category.png")

## Fig 5
f5 <- dd %>% filter(variety_category == "Farmer") %>% count(issue_year)
save_fig(ggplot(f5, aes(issue_year, n)) +
           geom_col(fill = cat_cols[["Farmer"]]) + geom_text(aes(label = n), vjust = -0.4, size = 3) +
           scale_x_continuous(breaks = seq(yr_min, max(f5$issue_year), 1)) +
           labs(title = "Certificates Issued for Farmers' Varieties Annually",
                x = "Year of certificate issue", y = "Farmers' certificates") +
           theme(axis.text.x = element_text(angle = 45, hjust = 1)),
         "fig05_farmers_by_year.png")

## Fig 6
f6 <- dd %>% filter(applicant_category == "Public", !is.na(variety_category)) %>%
  count(issue_year, variety_category)
save_fig(ggplot(f6, aes(issue_year, n, fill = variety_category)) + geom_col() + fill_cat +
           scale_x_continuous(breaks = seq(yr_min, max(f6$issue_year), 2)) +
           labs(title = "Certificates Issued to Public Applicants, by Category",
                x = "Year of certificate issue", y = "No. of certificates", fill = "Category"),
         "fig06_public_by_category_year.png")

## Fig 7
f7 <- dd %>% filter(applicant_category == "Private", !is.na(variety_category)) %>%
  count(issue_year, variety_category)
save_fig(ggplot(f7, aes(issue_year, n, fill = variety_category)) + geom_col() + fill_cat +
           scale_x_continuous(breaks = seq(yr_min, max(f7$issue_year), 2)) +
           labs(title = "Certificates Issued to Private Applicants, by Category",
                x = "Year of certificate issue", y = "No. of certificates", fill = "Category"),
         "fig07_private_by_category_year.png")

## Fig 8
f8 <- bind_rows(d %>% count(sector) %>% mutate(set = "All crops"),
                cot %>% count(sector) %>% mutate(set = "Cotton")) %>% filter(!is.na(sector))
save_fig(ggplot(f8, aes(sector, n, fill = set)) +
           geom_col(position = "dodge") + scale_fill_manual(values = set_cols) +
           geom_text(aes(label = n), position = position_dodge(width = 0.9), vjust = -0.4, size = 3) +
           labs(title = "Applicant Category — Cotton vs All Crops",
                x = "Applicant category", y = "Certificates", fill = NULL),
         "fig08_applicant_cotton_vs_all.png")

## Fig 9
f9 <- cot %>% filter(!is.na(ploidy), !is.na(sector)) %>% count(sector, ploidy)
save_fig(ggplot(f9, aes(sector, n, fill = ploidy)) +
           geom_col(position = "dodge") + scale_fill_manual(values = ploidy_cols) +
           geom_text(aes(label = n), position = position_dodge(width = 0.9), vjust = -0.4, size = 3) +
           labs(title = "Cotton Variety Certificates by Type of Variety (Ploidy)",
                x = "Applicant category", y = "No. of PVP certificates", fill = NULL),
         "fig09_cotton_ploidy_by_applicant.png")

## Fig 10
f10 <- cot %>% filter(!is.na(sector)) %>% count(issue_year, sector)
save_fig(ggplot(f10, aes(issue_year, n, color = sector)) + geom_line(linewidth = 1) + col_sector +
           scale_x_continuous(breaks = seq(yr_min, max(f10$issue_year), 2)) +
           labs(title = "Applicant Composition of Cotton Variety Certification",
                x = "Year of certificate issue", y = "No. of certificates", color = NULL),
         "fig10_cotton_composition_over_time.png")

## Fig 11
f11 <- cot %>% filter(!is.na(variety_category), !is.na(sector)) %>% count(variety_category, sector)
save_fig(ggplot(f11, aes(variety_category, n, fill = sector)) + geom_col() + fill_sector +
           labs(title = "Cotton Variety Certificates by Type of Variety",
                x = "Variety category", y = "No. of certificates", fill = NULL) +
           theme(axis.text.x = element_text(angle = 30, hjust = 1)),
         "fig11_cotton_category_by_applicant.png")

## Fig 12
f12 <- cot %>% filter(applicant_category == "Private", !is.na(variety_category)) %>%
  count(issue_year, variety_category)
save_fig(ggplot(f12, aes(issue_year, n, fill = variety_category)) + geom_col() + fill_cat +
           scale_x_continuous(breaks = seq(yr_min, max(f12$issue_year), 2)) +
           labs(title = "Cotton Variety Certificates by Category — Private Applicants",
                x = "Year of certificate issue", y = "No. of certificates", fill = "Category"),
         "fig12_private_cotton_by_category_year.png")

## Fig 13  (spelling variants merged)
priv <- cot %>% filter(applicant_category == "Private") %>%
  mutate(key = alias_company(canon_company(applicant)))
labels <- priv %>% count(key, applicant) %>% group_by(key) %>%
  slice_max(n, n = 1, with_ties = FALSE) %>% ungroup() %>%
  transmute(key, label = coalesce(unname(pretty_names[key]), applicant))
f13 <- priv %>% count(key, name = "n") %>% left_join(labels, by = "key") %>%
  arrange(desc(n)) %>%
  mutate(label = ifelse(row_number() <= 10, label, "Others")) %>%
  group_by(label) %>% summarise(n = sum(n), .groups = "drop") %>%
  mutate(pct = n / sum(n)) %>% arrange(desc(n))
save_fig(ggplot(f13, aes("", n, fill = fct_reorder(label, n, .desc = TRUE))) +           geom_col(width = 1, color = "white") + coord_polar(theta = "y") +
           geom_text(aes(label = ifelse(pct >= 0.03, percent(pct, accuracy = 0.1), "")),
                     position = position_stack(vjust = 0.5), size = 3) +
           labs(title = "Major Private Applicants — Cotton Variety Certification", fill = NULL) +
           theme_void(base_size = 12),
         "fig13_private_cotton_companies_pie.png")

message("\nDone. All 13 figures saved in ", fig_dir, "/\n")
message("Top private cotton applicants after merging spelling variants:")
print(as.data.frame(head(f13, 11)))
message("\nAll-crops certificates by ISSUE year (compare to your paper Fig 1):")
print(as.data.frame(dd %>% count(issue_year)))
