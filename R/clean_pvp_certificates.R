#!/usr/bin/env Rscript
# Clean the full PPVFRA registry (scrape_all_certificates.R output) -> tidy CSV.
# Usage: Rscript clean_pvp_certificates.R [in.csv] [out.csv] [reference_date]
#
# reference_date (YYYY-MM-DD) controls the `is_live` column: a certificate is
# live if its expiry_date falls on or after this date. It defaults to today,
# which is the right behaviour for the weekly-refreshed live dashboard (each
# week's pull explicitly records and displays the date it used - see
# data/reference_date.txt - so it is never a *silent* "as of now").
# A frozen data release (e.g. a Zenodo deposit backing a specific paper) must
# instead pass a fixed reference_date explicitly, so that `is_live` never
# changes if the release is reprocessed later. Record whichever date was used
# in the codebook for that release.

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(janitor); library(lubridate)
})

args           <- commandArgs(trailingOnly = TRUE)
in_file        <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "data/pvp_certificates_all.csv"
out_file       <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "data/pvp_certificates_clean.csv"
reference_date <- if (length(args) >= 3 && nzchar(args[3])) as.Date(args[3]) else Sys.Date()

raw <- read_csv(in_file, col_types = cols(.default = "c")) %>% clean_names()

# robust 4-digit year from any messy date string
year_of <- function(x) as.integer(str_extract(x, "\\b(19|20)\\d{2}\\b"))

# The register mostly uses "16 September 2012" or "28-November-2038", but a
# handful of rows (an older export format, it seems - it recurs across both
# date_of_certificate_issue and maximum_protection_period_up_to) instead use
# "Friday, January 16, 2037". Try both; anything left over stays NA rather
# than being silently coerced.
parse_ppvfr_date <- function(x) {
  s1 <- str_squish(str_replace_all(x, "-", " "))
  d  <- suppressWarnings(as.Date(s1, format = "%d %B %Y"))
  need2 <- is.na(d) & !is.na(x) & nzchar(str_squish(x))
  if (any(need2)) {
    d[need2] <- suppressWarnings(as.Date(str_squish(x[need2]), format = "%A, %B %d, %Y"))
  }
  d
}

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

## ---- applicant-name normalisation (tiers 1 & 2 of the ownership ladder) --
## Tier 1 (applicant_norm): collapse spelling/legal-suffix variants of the
## SAME register entry into one name - "X Ltd" / "X Pvt Ltd" / "X Limited"
## are the same string in the register's own filing history, not a merger.
canon_company <- function(x) {
  y <- str_to_lower(x)
  y <- str_replace(y, "^\\s*(m/s\\.?|messrs\\.?)\\s+", "")
  # strip administrative reissue/correction annotations entirely -- the
  # register appends things like "(reissued with address change, old serial
  # no. 12345)" when a certificate is reissued, and the serial number differs
  # every time, which otherwise splits one firm into many distinct canonical
  # keys. Always a trailing block, never followed by other legitimate content.
  y <- str_replace(y, "\\((reissu\\w*|corrigend\\w*).*$", "")
  y <- str_replace_all(y, "[.,()/]", " ")
  y <- str_replace_all(y, "&", " and "); y <- str_replace_all(y, "\\bseeds\\b", "seed")
  y <- str_replace_all(y, "\\bsciences\\b", "science")
  y <- str_replace_all(y, "crop\\s*science", "cropscience")
  y <- str_replace_all(y, "\\bp\\s+ltd\\b", "ltd")
  y <- str_replace_all(y, "\\b(private|pvt|limited|ltd|llp|company|co|corporation|corp|incorporated|inc)\\b", " ")
  str_squish(y)
}
# NOTE: deliberately no brand/parent-company folding at this tier ("^monsanto"
# -> one bucket, "mahyco" variants -> one bucket, etc.) -- that kind of
# judgment call is exactly what Tiers 2 and 3 exist to make explicitly and
# on documented evidence (CIN match, ownership). Tier 1 must stay a strictly
# mechanical spelling/legal-suffix normalisation of the register's own text,
# or it silently pre-merges entities the codebook says are only merged
# starting at Tier 2/3.

## Tier 2 (applicant_entity): fold register names that are the SAME LEGAL
## ENTITY under a different name, confirmed by shared Corporate Identification
## Number. FLAGGED: the handover text says "nine register names" fold here
## but lists only eight source->target pairs -- the ninth was not found (see
## the flagged discrepancy note in the codebook). Fix the ninth pair here
## once known.
entity_fold <- c(
  "bejo sheetal seed"          = "beejsheetal research",
  "bisco biosciences"          = "limagrain india",
  "dow agrosciences india"     = "corteva crop india",
  "rasi hy veg"                = "acsen agriscience",
  "asha agrisciences"          = "yaaganti seed",
  "monsanto holding"           = "monsanto holdings",
  "rasi seed p"                = "rasi seed",
  "pioneer overseas corporation india branch office" = "pioneer overseas corporation"
)
apply_entity_fold <- function(norm_key) {
  recode(norm_key, !!!entity_fold, .default = norm_key)
}

clean <- raw %>%
  transmute(
    s_no,
    registration_no    = str_squish(registration_no),
    registration_year  = year_of(registration_no),
    certificate_s_no,
    variety_category   = norm_category(category_of_variety),
    variety_name       = str_squish(denomintion_of_the_candidate_variety),
    crop               = str_squish(crop),
    crop_clean         = str_to_title(str_squish(crop)),
    crop_group         = str_to_title(str_squish(crop_group)),
    applicant          = str_squish(name_of_applicant),
    applicant_category = str_to_title(str_squish(applicant_category)),
    application_no     = str_squish(application_no),
    date_filed_raw     = str_squish(date_of_filling),
    date_issued_raw    = str_squish(date_of_certificate_issue),
    filing_year        = year_of(date_of_filling),
    issue_year         = year_of(date_of_certificate_issue),
    issue_date         = parse_ppvfr_date(date_of_certificate_issue),
    expiry_raw         = str_squish(maximum_protection_period_up_to),
    provisional_protection_claim_raw = str_squish(provisional_protection_claim)
  ) %>%
  mutate(
    sector = case_when(
      applicant_category == "Public" & is_sau(applicant) ~ "SAU",
      TRUE ~ applicant_category
    ),
    # Correct definition: TRUE only for the two cotton crop names themselves.
    # crop_group == "Fibre Crops" is a *different*, legitimately larger set
    # (it also contains Jute) - do not use it here. See README/codebook.
    is_cotton   = crop_clean %in% c("Tetraploid Cotton", "Diploid Cotton"),
    is_complete = !is.na(variety_name) & variety_name != "",

    applicant_key         = canon_company(applicant),
    applicant_entity_key  = apply_entity_fold(applicant_key),

    # The register surfaces revocation only as free text appended to this one
    # field, for exactly one certificate on file (the FL 2027 potato case) -
    # capture it explicitly rather than losing it in a failed date parse.
    is_revoked      = str_detect(expiry_raw, regex("revok", ignore_case = TRUE)),
    revocation_note = if_else(is_revoked, expiry_raw, NA_character_),
    expiry_date     = if_else(
      is_revoked,
      suppressWarnings(as.Date(str_extract(expiry_raw, "\\d{2}/\\d{2}/\\d{4}"), format = "%d/%m/%Y")),
      parse_ppvfr_date(expiry_raw)
    ),
    term_years = as.numeric(expiry_date - issue_date) / 365.25,
    # A revoked certificate's protection ended at revocation, not at the
    # originally scheduled expiry date captured above - never call it live.
    is_live    = if_else(is_revoked, FALSE, expiry_date >= reference_date)
  )

## applicant_norm / applicant_entity: pick, per canonical key, the most
## common as-filed spelling as the display label (same rule the dashboard
## already used ad hoc for chart labels - now persisted as real columns).
label_for_key <- function(df, key_col) {
  df %>% count(.data[[key_col]], applicant) %>%
    group_by(.data[[key_col]]) %>% slice_max(n, n = 1, with_ties = FALSE) %>% ungroup() %>%
    transmute(key = .data[[key_col]], label = applicant)
}
norm_labels   <- label_for_key(clean, "applicant_key")
entity_labels <- label_for_key(clean, "applicant_entity_key")
clean <- clean %>%
  left_join(norm_labels,   by = c("applicant_key" = "key")) %>% rename(applicant_norm = label) %>%
  left_join(entity_labels, by = c("applicant_entity_key" = "key")) %>% rename(applicant_entity = label) %>%
  select(-applicant_key, -applicant_entity_key)

message("Rows: ", nrow(clean))
message("\n== variety_category =="); print(sort(table(clean$variety_category), decreasing = TRUE))
message("\n== sector ==");           print(sort(table(clean$sector), decreasing = TRUE))
message("\nCotton rows (crop_clean-based): ", sum(clean$is_cotton, na.rm = TRUE))
message("Fibre Crops rows (crop_group-based, includes Jute): ",
        sum(clean$crop_group == "Fibre Crops", na.rm = TRUE))
message("\n== certificates by REGISTRATION year ==")
print(table(clean$registration_year, useNA = "ifany"))
message("\nexpiry_date parse failures: ", sum(is.na(clean$expiry_date)), " of ", nrow(clean))
message("Reference date for is_live: ", format(reference_date))
message("Live certificates: ", sum(clean$is_live, na.rm = TRUE), " of ", nrow(clean))
message("Private applicants -- Tier 1 (applicant_norm): ",
        n_distinct(clean$applicant_norm[clean$sector == "Private"]))
message("Private applicants -- Tier 2 (applicant_entity): ",
        n_distinct(clean$applicant_entity[clean$sector == "Private"]))

write_csv(clean, out_file, na = "")
message("\nWrote ", out_file)

ref_file <- file.path(dirname(out_file), "reference_date.txt")
writeLines(paste0("Live-status reference date: ", format(reference_date)), ref_file)
message("Wrote ", ref_file)
