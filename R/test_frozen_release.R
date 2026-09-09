#!/usr/bin/env Rscript
# Snapshot-specific regression test for the v0.3.0 frozen release, backing
# the paper's cited figures. Unlike test_clean_pvp_certificates.R (which
# checks logic that must hold on any pull, growing register included), the
# assertions here are tied to one specific pull and will not hold on a later
# scrape -- that's the point: this is what proves a given output file
# actually reproduces the paper's numbers before it gets deposited.
#
# Usage: Rscript R/test_frozen_release.R <clean.csv produced from the
#   2026-08-09 pull with max_issue_year=2025>

suppressPackageStartupMessages({ library(dplyr); library(readr) })

args    <- commandArgs(trailingOnly = TRUE)
in_file <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "data/pvp_certificates_clean.csv"
d <- read_csv(in_file, show_col_types = FALSE)
priv <- d %>% filter(sector == "Private")

failures <- character(0)
check <- function(desc, actual, expected) {
  ok <- isTRUE(all.equal(actual, expected))
  cat(if (ok) "  [ok] " else "  [FAIL] ", desc, " (got ", actual, ", expected ", expected, ")\n", sep = "")
  if (!ok) failures <<- c(failures, desc)
}

cat("Testing", in_file, "against the audit's reported figures\n\n")
check("total rows",                             nrow(d), 10462)
check("is_cotton.sum()",                        sum(d$is_cotton, na.rm = TRUE), 939)
check("private applicant_norm.nunique()",       n_distinct(priv$applicant_norm), 133)
check("private applicant_entity.nunique()",     n_distinct(priv$applicant_entity), 125)
check("private owner_group.nunique()",          n_distinct(priv$owner_group), 105)

if (length(failures) == 0) {
  cat("\nAll checks passed -- this file reproduces the audit exactly.\n")
} else {
  cat("\n", length(failures), " check(s) FAILED -- see README Codebook for known open items.\n", sep = "")
  quit(status = 1)
}
