#!/usr/bin/env Rscript

# Parse the HTML table(s) of granted PVP certificates from India's
# Plant Variety registry (plantauthority.gov.in) into tidy CSV files.
#
# Usage (from the repo root):
#   Rscript R/parse_pvp_certificates.R
#   Rscript R/parse_pvp_certificates.R "https://plantauthority.gov.in/node/3044" data
#
# install.packages(c("rvest", "tidyverse", "janitor"))

suppressPackageStartupMessages({
  library(rvest); library(dplyr); library(purrr)
  library(janitor); library(readr)
})

args    <- commandArgs(trailingOnly = TRUE)
url     <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "https://plantauthority.gov.in/node/3044"
out_dir <- if (length(args) >= 2 && nzchar(args[2])) args[2] else "data"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

ua <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

read_page <- function(url) {
  message("Fetching: ", url)
  if (requireNamespace("httr", quietly = TRUE)) {
    resp <- httr::GET(url, httr::user_agent(ua))
    httr::stop_for_status(resp)
    read_html(httr::content(resp, as = "text", encoding = "UTF-8"))
  } else {
    Sys.setenv(HTTPUserAgent = ua); read_html(url)
  }
}

tidy_table <- function(node) {
  df <- tryCatch(html_table(node, fill = TRUE, header = TRUE), error = function(e) NULL)
  if (is.null(df) || nrow(df) == 0 || ncol(df) == 0) return(NULL)
  df %>%
    as_tibble(.name_repair = "unique") %>%
    clean_names() %>%
    mutate(across(where(is.character), ~ na_if(trimws(.x), ""))) %>%
    remove_empty(c("rows", "cols"))
}

page   <- read_page(url)
tables <- html_elements(page, "table")
if (length(tables) == 0) {
  stop("No <table> found. Data may be JS-rendered; use the 'chromote' package instead.")
}
message("Found ", length(tables), " table(s).")

tidied  <- map(tables, tidy_table)
written <- imap_chr(tidied, function(df, i) {
  if (is.null(df) || nrow(df) == 0) { message("  Table ", i, ": skipped."); return(NA_character_) }
  file <- file.path(out_dir, sprintf("pvp_certificates_table_%02d.csv", i))
  write_csv(df, file, na = "")
  message("  Table ", i, ": ", nrow(df), " rows x ", ncol(df), " cols -> ", file)
  file
})
written <- written[!is.na(written)]
if (length(written) == 0) stop("Tables found but none parseable.")
message("\nDone. Wrote ", length(written), " file(s):\n  ", paste(written, collapse = "\n  "))