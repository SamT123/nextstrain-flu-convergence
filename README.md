# nextstrain-flu-convergence

This pipeline calculates Log Convergence Ratios (LCR) for every amino acid substitution in H3N2 HA in one-year windows, for colouring the public `nextstrain/seasonal-flu`
tree.

For more details on the method, see:

> Turner SA, Pattinson DJ, Fouchier RAM, Smith DJ (2026). Predicting the
> antigenic evolution of seasonal influenza viruses using phylogenetic
> convergence. _bioRxiv_ 2026.04.10.717627.
> doi:[10.64898/2026.04.10.717627](https://doi.org/10.64898/2026.04.10.717627)

## Running

1. Create the conda environment (`iqtree`,
   `cmaple`, `usher`, `chronumental`):

```
conda env create -f environment.yml
```

2. Build:

```
`./run.sh -b`.
```

## Output

### `results/lcr_weights.tsv`

A table containing LCR scores for each substitution in each time window:

| column       | meaning                                                                                                              |
| ------------ | -------------------------------------------------------------------------------------------------------------------- |
| `gene`       | `HA1` or `HA2`                                                                                                       |
| `site`       | 1-based position within the gene: HA1 1–329, HA2 1–221                                                               |
| `from_aa`    | ancestral amino acid                                                                                                 |
| `derived_aa` | derived amino acid                                                                                                   |
| `window_end` | end of the window                                                                                                    |
| `n`          | number of times the substitutions occurred on branches within the time window                                        |
| `expected_n` | number of times the substitutions was expected to occurr on branches within the time window, based on the null model |
| `weight`     | `log2((n + 1) / (expected_n + 1))`                                                                                   |

### `results/lcr_windows.tsv`

Start & end dates of windows, and end date as a decimal year in the same convention as treetime.
