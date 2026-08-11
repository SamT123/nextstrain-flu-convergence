readMaturePeptideSpan <- function(alignment_path) {
  genbank_path <- fs::dir_ls(alignment_path, glob = "*.gb")
  stopifnot(length(genbank_path) == 1)

  peptides <- seqUtils::read_genbank(genbank_path)$features |>
    purrr::keep(\(feature) feature$type == "mat_peptide")
  stopifnot(length(peptides) > 0)

  starts <- sort(purrr::map_int(peptides, "start"))
  ends <- sort(purrr::map_int(peptides, "end"))
  width <- max(ends) - min(starts)

  stopifnot(
    "mature peptides aren't next to each other" = identical(
      starts[-1],
      head(ends, -1)
    ),
    "coding span is not a whole number of codons" = width %% 3 == 0
  )

  c(min(starts) + 1L, max(ends))
}
