#!/usr/bin/env Rscript
# Regression tests for R/clean_pvp_certificates.R.
# Usage: Rscript R/test_clean_pvp_certificates.R [clean.csv]
#
# These check the *logic* the cleaning step must always satisfy, not exact
# row counts -- the register grows every week, so any hardcoded total drifts
# out of date by design. Counts tied to one specific frozen pull (e.g. the
# figures reported in a paper) belong in a codebook note for that release,
# not here.

suppressPackageStartupMessages({ library(dplyr); library(readr) })

args     <- commandArgs(trailingOnly = TRUE)
in_file  <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "data/pvp_certificates_clean.csv"
d <- read_csv(in_file, show_col_types = FALSE)

failures <- character(0)
check <- function(desc, expr) {
  ok <- isTRUE(tryCatch(expr, error = function(e) FALSE))
  cat(if (ok) "  [ok] " else "  [FAIL] ", desc, "\n", sep = "")
  if (!ok) failures <<- c(failures, desc)
}

cat("Testing", in_file, "(", nrow(d), "rows )\n\n")

## Priority 1: the cotton flag
check("no Jute row has is_cotton == TRUE",
      !any(d$crop_clean == "Jute" & d$is_cotton, na.rm = TRUE))
check("is_cotton is TRUE only for Tetraploid/Diploid Cotton crop_clean values",
      all(d$crop_clean[d$is_cotton] %in% c("Tetraploid Cotton", "Diploid Cotton")))
check("crop_group 'Fibre Crops' is a superset of is_cotton (contains Jute too)",
      sum(d$crop_group == "Fibre Crops", na.rm = TRUE) >= sum(d$is_cotton, na.rm = TRUE))

## Priority 2: expiry / term / live
check("expiry_date is parsed for effectively all rows (allow the one genuinely
       ambiguous revoked-certificate case as the only routine exception)",
      mean(is.na(d$expiry_date)) < 0.001)
check("a revoked certificate is never marked live",
      !any(d$is_revoked & d$is_live, na.rm = TRUE))
check("term_years is not substantially negative wherever it's non-missing
       (a small number of register rows have expiry exactly one calendar day
       before issue -- see README Codebook -- so allow that, not arbitrary
       negative terms)",
      all(d$term_years[!is.na(d$term_years)] > -0.01))
check("is_live is never TRUE past its own expiry_date",
      !any(d$is_live & !is.na(d$expiry_date) &
             d$expiry_date < as.Date(sub("^Live-status reference date: ", "",
               readLines(file.path(dirname(in_file), "reference_date.txt"))[1])),
           na.rm = TRUE))

## Priority 3 (tiers 1-3, mechanical/monotonicity properties only -- exact
## counts against a specific pull belong in test_frozen_release.R, since the
## register keeps growing)
check("applicant_entity never splits what applicant_norm already merged
       (Tier 2 is always a coarsening of Tier 1, never a refinement)",
      {
        norm_to_entity <- d %>% distinct(applicant_norm, applicant_entity)
        !any(duplicated(norm_to_entity$applicant_norm))
      })
check("owner_group never splits what applicant_entity already merged
       (Tier 3 is always a coarsening of Tier 2, never a refinement)",
      {
        entity_to_owner <- d %>% distinct(applicant_entity, owner_group)
        !any(duplicated(entity_to_owner$applicant_entity))
      })
check("every private-sector row has a non-missing applicant_norm/applicant_entity/owner_group",
      all(!is.na(d$applicant_norm[d$sector == "Private"])) &&
      all(!is.na(d$applicant_entity[d$sector == "Private"])) &&
      all(!is.na(d$owner_group[d$sector == "Private"])))

if (length(failures) == 0) {
  cat("\nAll checks passed.\n")
} else {
  cat("\n", length(failures), " check(s) FAILED:\n", sep = "")
  for (f in failures) cat("  - ", f, "\n", sep = "")
  quit(status = 1)
}
