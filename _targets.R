library(targets)

tar_option_set(
  packages = c(
    "dplyr",
    "fs",
    "lubridate",
    "purrr",
    "readr",
    "stringr",
    "tibble"
  ),
  workspace_on_error = TRUE
)

tar_source()

ALIGNMENT_PATH <- Sys.getenv(
  "ALIGNMENT_PATH",
  "../flu-alignments/results/H3-HA-human-dedup"
)
RESULTS_DIR <- "results"

FIRST_WINDOW_START <- as.Date("2012-04-01")
WINDOW_WIDTH <- "1 year"
WINDOW_INCREMENT <- "6 months"
MIN_WINDOW_WIDTH <- "6 months"

INITIAL_IQTREE_SIZE <- 10
CASCADE_SIZES <- c(100, 1000)
TREE_SEED <- 100
CHRONUMENTAL_STEPS <- 10000
TREE_INFO_SEED <- 1

list(
  tar_target(
    results_dir,
    {
      fs::dir_create(fs::path(RESULTS_DIR, "tree"))
      RESULTS_DIR
    }
  ),

  tar_target(
    alignment_gitinfo,
    fs::file_copy(
      fs::path(ALIGNMENT_PATH, "git_info", ext = "json"),
      fs::path(results_dir, "aln_git_info", ext = "json"),
      overwrite = TRUE
    ),
    format = "file"
  ),

  tar_target(reference, readReference(ALIGNMENT_PATH)),
  tar_target(coding_range, reference$range),
  tar_target(gene_lengths, reference$gene_lengths),
  tar_target(reference_nucleotides, reference$nucleotides),
  tar_target(reference_amino_acids, reference$amino_acids),

  # alignment and windows -----
  tar_target(
    alignment,
    {
      aln <- fs::path(ALIGNMENT_PATH, "aln", ext = "RDS") |>
        readRDS() |>
        mutate(
          dna_sequence = str_sub(dna_aln, coding_range[1], coding_range[2])
        ) |>
        filter(collection_date >= FIRST_WINDOW_START) |>
        mutate(
          chronumental_date = recode_values(
            collection_date_precision,
            "day" ~ format(collection_date, "%Y-%m-%d"),
            "month" ~ format(collection_date, "%Y-%m"),
            "year" ~ format(collection_date, "%Y")
          )
        ) |>
        select(
          Isolate_name = isolate_name,
          Isolate_unique_identifier = isolate_unique_identifier,
          Collection_date = collection_date,
          collection_date_precision,
          chronumental_date,
          dna_sequence
        )

      stopifnot(!anyNA(aln$chronumental_date))
      aln
    }
  ),

  tar_target(last_collection_date, max(alignment$Collection_date)),

  tar_target(
    windows,
    makeWindows(
      first_start = FIRST_WINDOW_START,
      width = WINDOW_WIDTH,
      increment = WINDOW_INCREMENT,
      min_width = MIN_WINDOW_WIDTH,
      last_date = last_collection_date
    )
  ),

  tar_target(
    time_windows,
    purrr::map2(
      as.character(windows$window_start),
      as.character(windows$window_end),
      c
    ) |>
      purrr::set_names(as.character(windows$window_start))
  ),

  # make tree -----
  tar_target(
    tree,
    seqUtils::make_iterative_tree(
      alignment = alignment,
      tree_path = fs::path(results_dir, "tree", "tree", ext = "nwk"),
      initial_iqtree_size = INITIAL_IQTREE_SIZE,
      cascade_sizes = CASCADE_SIZES,
      work_dir = fs::path(results_dir, "tree"),
      seed = TREE_SEED
    )
  ),

  tar_target(
    rooted_tree,
    seqUtils::root_tree_using_outsequence(
      tree = tree,
      sequences = alignment |>
        pull(dna_sequence, Isolate_unique_identifier),
      outsequence = reference_nucleotides
    )
  ),

  tar_target(
    collapsed_tree,
    ape::di2multi(rooted_tree, tol = 1e-10)
  ),

  tar_target(
    tree_and_sequences,
    convergence::makeTreeAndSequences(
      tree = collapsed_tree,
      sequences = alignment
    )
  ),

  # time calibration and ASR -----

  tar_target(
    chronumental_reference_strain,
    alignment |>
      filter(collection_date_precision == "day") |>
      arrange(Collection_date, Isolate_unique_identifier) |>
      slice(1) |>
      pull(Isolate_unique_identifier)
  ),

  tar_target(
    chronumental_tree_and_sequences,
    convergence::toChronumentalTree(
      tree_and_sequences,
      reference_strain = chronumental_reference_strain,
      date_column = "chronumental_date",
      n_steps = CHRONUMENTAL_STEPS,
      genome_size = nchar(reference_nucleotides)
    )
  ),

  tar_target(
    usher_tree_and_sequences,
    convergence::addASRusher(
      chronumental_tree_and_sequences,
      nuc_ref = reference_nucleotides,
      aa_ref = reference_amino_acids
    )
  ),

  # convergence scores -----
  tar_target(
    tree_info,
    convergence::getTreeSizeAndNucRates(
      usher_tree_and_sequences,
      convergence:::maxlike_models$normal_model,
      seed = TREE_INFO_SEED
    )
  ),

  tar_target(
    window_ratios,
    {
      tree_and_sequences_dated <- usher_tree_and_sequences
      tree_and_sequences_dated$tree_tibble$predicted_date_char <- format(
        tree_and_sequences_dated$tree_tibble$predicted_date,
        format = "%Y-%m-%d"
      )

      convergence::getTimeIntervalSubstitutionRatios(
        tree_and_sequences = tree_and_sequences_dated,
        tree_info = tree_info,
        time_windows = time_windows,
        positions = seq_len(nchar(reference_amino_acids)),
        date_column = "predicted_date_char",
        calculate_p_values = FALSE
      )
    }
  ),

  # export -----
  tar_target(
    weight_table,
    buildWeightTable(window_ratios, windows, gene_lengths)
  ),

  tar_target(
    provenance,
    buildProvenance(
      alignment_path = ALIGNMENT_PATH,
      n_tips = ape::Ntip(collapsed_tree),
      windows = windows,
      window_width = WINDOW_WIDTH,
      window_increment = WINDOW_INCREMENT,
      min_window_width = MIN_WINDOW_WIDTH,
      reference_strain = chronumental_reference_strain,
      date_precision = table(alignment$collection_date_precision),
      gene_lengths = gene_lengths
    )
  ),

  tar_target(
    weight_tsv,
    writeWeightTable(
      weight_table,
      fs::path(results_dir, "lcr_weights", ext = "tsv"),
      provenance
    ),
    format = "file"
  ),

  tar_target(
    windows_tsv,
    writeWindows(windows, fs::path(results_dir, "lcr_windows", ext = "tsv")),
    format = "file"
  )
)
