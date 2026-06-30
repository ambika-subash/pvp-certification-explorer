#!/usr/bin/env Rscript

# Clean the raw PVP certificate table into an analysis-ready CSV.
# Usage: Rscript clean_pvp_certificates.R [in.csv] [out.csv]

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr)
  library(lubridate); library(janitor)
})

args     <- commandArgs(trailingOnly = TRUE)
in_file  <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "data/pvp_certificates_table_01.csv"
out_file <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "data/pvp_certificates_clean.csv"

raw <- read_csv(in_file, show_col_types = FALSE) %>% clean_names()

clean <- raw %>%
  transmute(
    certificate_no      = as.integer(certificate_s_no),
    registration_no     = str_squish(registration_no),
    registration_year   = as.integer(str_extract(registration_no, "\\d{4}")),
    variety_category    = str_to_title(str_squish(category_of_variety)),
    variety_name        = str_squish(denomination_of_the_candidate_variety),
    crop                = str_to_title(str_squish(crop)),
    crop_group          = str_to_title(str_squish(crop_group)),
    applicant           = str_squish(name_of_applicant),
    sector              = str_to_title(str_squish(applicant_category)),
    application_no      = str_squish(application_no),
    date_filed          = suppressWarnings(dmy(date_of_filling)),
    date_issued         = suppressWarnings(dmy(date_of_certificate_issue)),
    protection_until    = suppressWarnings(dmy(maximum_protection_period_up_to)),
    provisional_claim   = str_squish(provisional_protection_claim)
  ) %>%
  mutate(
    issue_year  = year(date_issued),
    is_complete = !is.na(variety_name) & variety_name != ""
  )

message("Rows total      : ", nrow(clean))
message("Incomplete rows : ", sum(!clean$is_complete), " (no variety name)")
message("Sectors         : ", paste(sort(unique(na.omit(clean$sector))), collapse = ", "))
message("Issue years     : ",
        suppressWarnings(min(clean$issue_year, na.rm = TRUE)), " - ",
        suppressWarnings(max(clean$issue_year, na.rm = TRUE)))

write_csv(clean, out_file, na = "")
message("Wrote ", out_file)