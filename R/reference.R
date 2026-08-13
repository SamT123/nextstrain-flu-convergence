readReference <- function(alignment_path) {
  genbank_path <- fs::dir_ls(alignment_path, glob = "*.gb")
  stopifnot(length(genbank_path) == 1)

  record <- seqUtils::read_genbank(genbank_path)
  orfs <- seqUtils::extract_orfs(
    record,
    record$sequence,
    types = c("sig_peptide", "mat_peptide")
  )

  genes <- tibble::tibble(
    gene = names(orfs),
    start = purrr::map_int(orfs, \(orf) orf$parts[[1]]$start),
    end = purrr::map_int(orfs, \(orf) orf$parts[[1]]$end)
  ) |>
    dplyr::arrange(start)
  widths <- genes$end - genes$start + 1L

  stopifnot(
    "coding features aren't next to each other" = all(
      genes$start[-1] == head(genes$end, -1) + 1L
    ),
    "a coding feature is not a whole number of codons" = all(widths %% 3 == 0)
  )

  coding_range <- c(min(genes$start), max(genes$end))
  nucleotides <- toupper(
    stringr::str_sub(record$sequence, coding_range[1], coding_range[2])
  )

  list(
    range = coding_range,
    gene_lengths = purrr::set_names(widths %/% 3L, genes$gene),
    nucleotides = nucleotides,
    amino_acids = seqUtils::translate(nucleotides)
  )
}
