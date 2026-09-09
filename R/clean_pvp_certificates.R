#!/usr/bin/env Rscript
# Clean the full PPVFRA registry (scrape_all_certificates.R output) -> tidy CSV.
# Usage: Rscript clean_pvp_certificates.R [in.csv] [out.csv] [reference_date] [max_issue_year]
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
#
# max_issue_year (integer, optional) drops certificates issued after that
# calendar year. This is a *period boundary for one specific analysis*, not
# a data-quality filter -- the paper's cited figures compare complete
# calendar years through 2025, so its frozen release passes 2025 to exclude
# the partial 2026 year. The live, continuously-updated dashboard should NOT
# set this (leave unset / NA), since dropping "this year so far" forever
# would defeat the point of a weekly refresh.

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(janitor); library(lubridate)
})

args           <- commandArgs(trailingOnly = TRUE)
in_file        <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "data/pvp_certificates_all.csv"
out_file       <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "data/pvp_certificates_clean.csv"
reference_date <- if (length(args) >= 3 && nzchar(args[3])) as.Date(args[3]) else Sys.Date()
max_issue_year <- if (length(args) >= 4 && nzchar(args[4])) as.integer(args[4]) else NA_integer_

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

## ---- applicant-name normalisation: three tiers ---------------------------
##
## Tier 1 (applicant_norm), "as published": mechanical spelling/legal-suffix
## normalisation of the register's own applicant string. No brand- or
## parent-company judgment calls happen here -- "Monsanto Holding Pvt Ltd"
## and "Monsanto Holdings Pvt Ltd" stay distinct Tier-1 names, since as filed
## they are distinct legal names. That kind of call belongs to Tiers 2/3,
## made explicitly and on documented evidence (CIN match, ownership).
##
## Tier 2 (applicant_entity), "same legal entity": Tier 1 folded further
## wherever a shared Corporate Identification Number confirms two register
## names are the same legal entity (data/same_entity_merges.csv).
##
## Tier 3 (owner_group), "ownership-adjusted": Tier 2 folded again wherever
## a documented, evidence-backed ownership relationship (majority control,
## verified by CIN/regulatory filing/rating-agency disclosure -- never a
## bare promoter-family or director link) puts two entities under one
## controlling group (data/A1_ownership_crosswalk.csv). See README Codebook
## for what does and doesn't count as control, and why this tier must never
## be used for period/time-series concentration (several of the underlying
## relationships postdate certificates they would otherwise govern).
##
## Layer 1 (mechanical, runs on every applicant string, old or new):
strip_ms_prefix    <- function(x) str_replace(x, regex("^\\s*(m/s\\.?|messrs\\.?)\\s+", ignore_case = TRUE), "")
strip_reissue_note <- function(x) str_replace(x, "\\((reissu\\w*|corrigend\\w*).*$", "")
canon_legal_suffix <- function(y) {
  y <- str_replace_all(y, regex("\\bpvt\\.?\\s+(ltd\\.?|limited)\\b", ignore_case = TRUE), "Private Limited")
  y <- str_replace_all(y, regex("\\bp\\.?\\s+ltd\\.?", ignore_case = TRUE), "P Limited")
  y <- str_replace_all(y, regex("\\bco\\.?\\s+ltd\\.?", ignore_case = TRUE), "Co Limited")
  y <- str_replace_all(y, regex("\\bltd\\.?", ignore_case = TRUE), "Limited")
  y
}
# A small set of acronyms that naive title-casing would mangle ("Dcm", "Jk",
# "Lp"). Validated against every historical applicant string, not guessed:
# other candidate acronyms (VNR, UACI, "AG") were tried and dropped because
# the audited ground truth (data/applicant_normalisation_lookup.csv) does
# NOT preserve them ("Vnr Seeds...", "Uaci Seeds...", "...Bayer Crop Sciences
# Ag" all stay lower-case-tailed there) -- preserving them here would produce
# a *different* Tier-1 spelling for future new applicants than for the
# existing ones using the same tokens.
acronyms <- c("DCM", "JK", "LP")
restore_acronyms <- function(y) {
  for (a in acronyms) y <- str_replace_all(y, regex(paste0("\\b", a, "\\b"), ignore_case = TRUE), a)
  y
}
layer1_normalise <- function(x) {
  y <- strip_ms_prefix(x)
  y <- strip_reissue_note(y)
  y <- canon_legal_suffix(y)
  y <- str_replace_all(y, "\\.", "")
  y <- str_squish(y)
  y <- str_to_title(y)
  y <- restore_acronyms(y)
  y
}

## Layer 2 (human-maintained overrides), applied by exact match on the
## as-filed applicant string, for the residue Layer 1 can't derive on its
## own (private->public conversions, trade-name changes, typo-renames --
## see data/entity_exceptions.csv). Validated by running Layer 1 against
## every historical applicant and diffing against the audited
## applicant_normalisation_lookup.csv: 235 of 236 rows matched exactly on
## the first pass; the one residual mismatch ("Bayer CropScience LP", whose
## camelCase spelling Layer 1 doesn't split) is folded in as an additional
## exceptions row rather than hand-waved away, per "let the diff define the
## exception set."
load_lookup <- function(path, key_col, value_col) {
  if (!file.exists(path)) return(tibble(key = character(), value = character()))
  read_csv(path, show_col_types = FALSE) %>%
    transmute(key = str_squish(.data[[key_col]]), value = .data[[value_col]]) %>%
    distinct(key, .keep_all = TRUE)
}
known_lookup <- load_lookup("data/applicant_normalisation_lookup.csv", "applicant", "applicant_norm")
exceptions   <- load_lookup("data/entity_exceptions.csv", "applicant", "applicant_norm")

compute_applicant_norm <- function(applicant) {
  key <- str_squish(applicant)
  from_lookup     <- known_lookup$value[match(key, known_lookup$key)]
  from_exceptions <- exceptions$value[match(key, exceptions$key)]
  layer1          <- layer1_normalise(applicant)
  coalesce(from_lookup, from_exceptions, layer1)
}

## Tier 2 fold (data/same_entity_merges.csv: applicant_norm -> applicant_entity)
entity_fold <- load_lookup("data/same_entity_merges.csv", "applicant_norm", "applicant_entity")
apply_entity_fold <- function(norm) coalesce(entity_fold$value[match(norm, entity_fold$key)], norm)

## Tier 3 fold (data/A1_ownership_crosswalk.csv: "Register name (as
## recorded)" -> "Group assigned", keyed at whatever tier the crosswalk's
## own rows happen to use -- it lists both pre- and post-Tier-2 names for
## the pairs Tier 2 already folds, so joining on applicant_entity after
## Tier 2 gets the right group either way). A blank or missing assignment
## means "no documented group" -- the entity stands as its own group, not
## silently merged into anything.
owner_fold <- load_lookup("data/A1_ownership_crosswalk.csv", "Register name (as recorded)", "Group assigned") %>%
  mutate(value = na_if(str_squish(value), ""))
apply_owner_fold <- function(entity) coalesce(owner_fold$value[match(entity, owner_fold$key)], entity)

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

    applicant_norm   = compute_applicant_norm(applicant),
    applicant_entity = apply_entity_fold(applicant_norm),
    owner_group      = apply_owner_fold(applicant_entity),

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

## Weekly-refresh triage: any as-filed applicant string that isn't already in
## the audited lookup is new since the audit. Its applicant_norm above is
## still computed (degrade-safe -- it appears as itself, never silently
## mismerged), but it hasn't been reviewed for entity/ownership folding, so
## it's queued for a human to check rather than trusted silently. Name and
## same-entity tiers still refresh automatically every week; the ownership
## tier only changes once a person has reviewed the queue and, if warranted,
## added a row to A1_ownership_crosswalk.csv -- majority control needs
## documentary evidence a script can't gather on its own.
## Restricted to the private sector: Tier 2/3 folding is only meaningful
## there, and the lookup only ever covered private applicants -- flagging
## every never-before-seen Farmer/Public/SAU name would just bury the
## signal (there are thousands of distinct farmer names alone).
review_queue <- clean %>%
  filter(sector == "Private", !str_squish(applicant) %in% known_lookup$key) %>%
  distinct(applicant, applicant_norm, applicant_entity, owner_group) %>%
  arrange(applicant)
queue_file <- file.path(dirname(out_file), "applicant_review_queue.csv")
if (nrow(review_queue) > 0) {
  write_csv(review_queue, queue_file)
  message("\n", nrow(review_queue), " applicant string(s) not in the audited lookup -- ",
          "wrote ", queue_file, " for review.")
} else if (file.exists(queue_file)) {
  file.remove(queue_file)
}

## Period filter: see the max_issue_year argument note at the top of this
## file. Applied last, after every other column (including is_live, which
## should reflect the full register regardless) has been computed.
if (!is.na(max_issue_year)) {
  n_before <- nrow(clean)
  clean <- clean %>% filter(is.na(issue_year) | issue_year <= max_issue_year)
  message("\nPeriod filter: dropped ", n_before - nrow(clean),
          " row(s) issued after ", max_issue_year, ".")
}

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
message("Private applicants -- Tier 3 (owner_group): ",
        n_distinct(clean$owner_group[clean$sector == "Private"]))

write_csv(clean, out_file, na = "")
message("\nWrote ", out_file)

ref_file <- file.path(dirname(out_file), "reference_date.txt")
writeLines(paste0("Live-status reference date: ", format(reference_date)), ref_file)
message("Wrote ", ref_file)
