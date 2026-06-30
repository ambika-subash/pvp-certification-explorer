#!/usr/bin/env Rscript
# Crawl ALL pages of the PPVFRA certificate list and combine into one CSV.
# Resumable: each page is cached under data/pages/, so a crash just means re-run.
# With 100 rows/page the registry is ~106 pages.
#
# Test first:  Rscript scrape_all_certificates.R --max=3
# Full crawl:  Rscript scrape_all_certificates.R
# Overrides: --items=100  --extra="items_per_page=100"  --page_param=page
#            --start=0  --max=200  --delay=1  --force=true

suppressPackageStartupMessages({
  library(rvest); library(httr); library(dplyr)
  library(readr); library(janitor); library(purrr); library(stringr)
})

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[1]) else default
}

base_url   <- get_arg("url",        "https://plantauthority.gov.in/list-certificates")
page_param <- get_arg("page_param", "page")
items      <- get_arg("items",      "100")
extra      <- get_arg("extra",      "")
start_page <- as.integer(get_arg("start", "0"))
max_pages  <- as.integer(get_arg("max",   "200"))
delay      <- as.numeric(get_arg("delay", "1"))
pages_dir  <- get_arg("pages_dir",  "data/pages")
out_file   <- get_arg("out",        "data/pvp_certificates_all.csv")
force      <- tolower(get_arg("force", "false")) %in% c("true", "1", "yes")

extra_query <- if (nzchar(extra)) {
  extra
} else if (nzchar(items)) {
  paste0("items_per_page=", items)
} else {
  ""
}

dir.create(pages_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)

ua <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

fetch_html <- function(url, tries = 4) {
  for (i in seq_len(tries)) {
    resp <- tryCatch(GET(url, user_agent(ua), timeout(60)), error = function(e) e)
    if (!inherits(resp, "error") && status_code(resp) == 200)
      return(read_html(content(resp, as = "text", encoding = "UTF-8")))
    Sys.sleep(2 ^ i)
  }
  stop("Failed to fetch after ", tries, " tries: ", url)
}

parse_page <- function(page) {
  tabs <- html_elements(page, "table")
  if (length(tabs) == 0) return(tibble())
  dfs <- map(tabs, ~ tryCatch(html_table(.x, fill = TRUE, header = TRUE),
                              error = function(e) NULL))
  dfs <- dfs[!map_lgl(dfs, is.null)]
  if (length(dfs) == 0) return(tibble())
  df  <- dfs[[which.max(map_int(dfs, nrow))]]
  df %>% as_tibble(.name_repair = "unique") %>% clean_names()
}

pad <- function(n) formatC(n, width = 5, flag = "0")

message("Crawling: ", base_url, "  (param '", page_param, "', 0-indexed)")
prev_sig <- NULL; total_rows <- 0L; p <- start_page
repeat {
  if (p - start_page + 1 > max_pages) { message("Hit max_pages cap."); break }
  cache <- file.path(pages_dir, paste0("page_", pad(p), ".csv"))
  if (file.exists(cache) && !force) {
    df <- suppressMessages(read_csv(cache, show_col_types = FALSE, col_types = cols(.default = "c")))
    if (nrow(df) == 0) { message("Cached page ", p, " empty -> end."); break }
    sig <- paste(utils::head(df[[1]], 3), collapse = "|")
    if (!is.null(prev_sig) && identical(sig, prev_sig)) break
    prev_sig <- sig; total_rows <- total_rows + nrow(df); p <- p + 1; next
  }
  qs  <- sub("^&", "", paste(c(extra_query, paste0(page_param, "=", p)), collapse = "&"))
  df  <- parse_page(fetch_html(paste0(base_url, "?", qs)))
  if (nrow(df) == 0) { message("Page ", p, ": no rows -> end of pager."); break }
  sig <- paste(utils::head(df[[1]], 3), collapse = "|")
  if (!is.null(prev_sig) && identical(sig, prev_sig)) {
    message("Page ", p, " repeats previous -> end."); break
  }
  write_csv(df, cache, na = "")
  prev_sig <- sig; total_rows <- total_rows + nrow(df)
  if (p %% 10 == 0 || p == start_page)
    message("  page ", p, "  (+", nrow(df), " rows; total ", total_rows, ")")
  Sys.sleep(delay); p <- p + 1
}

files <- sort(list.files(pages_dir, pattern = "^page_\\d+\\.csv$", full.names = TRUE))
message("\nCombining ", length(files), " page(s)...")
all <- files %>%
  map(~ suppressMessages(read_csv(.x, show_col_types = FALSE, col_types = cols(.default = "c")))) %>%
  bind_rows()
before <- nrow(all)
all <- distinct(all)   # drop only EXACT full-row duplicates; keep every certificate
write_csv(all, out_file, na = "")
message("Wrote ", out_file, ": ", nrow(all), " rows (", before - nrow(all),
        " dupes removed), ", ncol(all), " cols.")
message("Columns: ", paste(names(all), collapse = ", "))
print(utils::head(all, 3))