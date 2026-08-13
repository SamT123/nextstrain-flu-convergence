# Write date as decimal year like treetime (which makes nextstrain's node dates)
numericDate <- function(dates) {
  lubridate::year(dates) +
    (lubridate::yday(dates) - 0.5) / (365 + lubridate::leap_year(dates))
}

# 1 entry / substitution / window.
# Windows are labelled by their end date
buildWeightTable <- function(window_ratios, windows, gene_lengths) {
  gene_at <- factor(
    rep(names(gene_lengths), gene_lengths),
    levels = names(gene_lengths)
  )
  site_at <- sequence(gene_lengths)

  window_ratios |>
    purrr::map(\(ratios) {
      dplyr::select(ratios[["aas"]], at, from, to, n, expected_n)
    }) |>
    purrr::list_rbind(names_to = "window_name") |>
    dplyr::mutate(
      window_start = as.Date(substr(window_name, 1, 10)),
      at = as.integer(at),
      gene = gene_at[at],
      site = site_at[at],
      expected_n = round(expected_n, 6),
      lcr = round(log2((n + 1) / (expected_n + 1)), 6)
    ) |>
    dplyr::inner_join(windows, by = "window_start", unmatched = "error") |>
    dplyr::select(
      gene,
      site,
      from_aa = from,
      derived_aa = to,
      window_end,
      n,
      expected_n,
      lcr
    ) |>
    dplyr::arrange(window_end, gene, site, from_aa, derived_aa)
}


writeWeightTable <- function(weight_table, path, provenance) {
  writeLines(paste0("# ", provenance), path)
  readr::write_tsv(weight_table, path, append = TRUE, col_names = TRUE)
  path
}

writeWindows <- function(windows, path) {
  windows |>
    dplyr::mutate(
      window_start_numeric = numericDate(window_start),
      window_end_numeric = numericDate(window_end)
    ) |>
    readr::write_tsv(path)
  path
}

packageSha <- function(package) {
  sha <- utils::packageDescription(package)[["RemoteSha"]]
  if (is.null(sha)) {
    stop(package, " has no RemoteSha, install it from GitHub")
  }
  sha
}

buildProvenance <- function(
  alignment_path,
  n_tips,
  windows,
  reference_strain,
  date_precision,
  gene_lengths
) {
  git <- jsonlite::fromJSON(
    fs::path(alignment_path, "git_info", ext = "json"),
    simplifyVector = FALSE
  )

  fields <- c(
    generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    tips = n_tips,
    windows = sprintf(
      "%d (%s to %s, the final window is open-ended)",
      nrow(windows),
      min(windows$window_start),
      max(windows$window_end)
    ),
    "chronumental ref node" = reference_strain,
    "tip date precision" = paste(
      names(date_precision),
      date_precision,
      collapse = ", "
    ),
    alignment = alignment_path,
    "alignment commit" = git[["commit_hash"]],
    "alignment built" = git[["timestamp"]],
    "alignment reference" = git[["reference"]][["id"]],
    convergence = packageSha("convergence"),
    seqUtils = packageSha("seqUtils")
  )

  c(
    "H3N2 HA LCR",
    sprintf(
      "with 1-based numbering within %s",
      paste(
        sprintf("%s (1-%d)", names(gene_lengths), gene_lengths),
        collapse = ", "
      )
    ),
    "window_end: end of the window used to calculate the LCR",
    paste0(names(fields), ": ", fields)
  )
}
