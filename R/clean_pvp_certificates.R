#!/usr/bin/env Rscript
# Clean the full PPVFRA registry (scrape_all_certificates.R output) -> tidy CSV.
# Usage: Rscript clean_pvp_certificates.R [in.csv] [out.csv]

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(janitor)
})

args     <- commandArgs(trailingOnly = TRUE)
in_file  <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "data/pvp_certificates_all.csv"
out_file <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "data/pvp_certificates_clean.csv"

raw <- read_csv(in_file, col_types = cols(.default = "c")) %>% clean_names()

# robust 4-digit year from any messy date string
year_of <- function(x) as.integer(str_extract(x, "\\b(19|20)\\d{2}\\b"))

norm_category <- function(x) {
  x <- str_squish(x)
  case_when(
    str_detect(x, regex("vck",    ignore_case = TRUE)) ~ "Extant (VCK)",
    str_detect(x, regex("notif",  ignore_case = TRUE)) ~ "Extant (Notified)",
    str_detect(x, regex("edv",    ignore_case = TRUE)) ~ "EDV",
    str_detect(x, regex("^new$",  ignore_case = TRUE)) ~ "New",
    str_detect(x, regex("^farmer",ignore_case = TRUE)) ~ "Farmer",
    str_detect(x, regex("^extant$",ignore_case = TRUE))~ "Extant",
    TRUE ~ x
  )
}

# State Agricultural Universities, detected from applicant names
is_sau <- function(name) str_detect(name, regex(
  "agric(ultural)? univ|krishi vidya|vishwa ?vidyalaya|vidyapeeth|\\bSAU\\b|\\bUAS\\b|horticultural univ|veterinary",
  ignore_case = TRUE))

clean <- raw %>%
  transmute(
    s_no,
    registration_no    = str_squish(registration_no),
    registration_year  = year_of(registration_no),
    certificate_s_no,
    variety_category   = norm_category(category_of_variety),
    variety_name       = str_squish(denomintion_of_the_candidate_variety),
    crop               = str_squish(crop),
    crop_group         = str_to_title(str_squish(crop_group)),
    applicant          = str_squish(name_of_applicant),
    applicant_category = str_to_title(str_squish(applicant_category)),
    application_no     = str_squish(application_no),
    date_filed_raw     = str_squish(date_of_filling),
    date_issued_raw    = str_squish(date_of_certificate_issue),
    filing_year        = year_of(date_of_filling),
    issue_year         = year_of(date_of_certificate_issue)
  ) %>%
  mutate(
    sector = case_when(
      applicant_category == "Public" & is_sau(applicant) ~ "SAU",
      TRUE ~ applicant_category
    ),
    is_cotton   = str_detect(crop, regex("cotton", ignore_case = TRUE)) |
      str_detect(crop_group, regex("fibre", ignore_case = TRUE)),
    is_complete = !is.na(variety_name) & variety_name != ""
  )

message("Rows: ", nrow(clean))
message("\n== variety_category =="); print(sort(table(clean$variety_category), decreasing = TRUE))
message("\n== sector ==");           print(sort(table(clean$sector), decreasing = TRUE))
message("\nCotton rows: ", sum(clean$is_cotton, na.rm = TRUE))
message("\n== certificates by REGISTRATION year ==")
print(table(clean$registration_year, useNA = "ifany"))

write_csv(clean, out_file, na = "")
message("\nWrote ", out_file)