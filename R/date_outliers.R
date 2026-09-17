checkPredictedDates <- function(tree_and_sequences, slack_days = 60) {
  tree_tibble <- tree_and_sequences[["tree_tibble"]]
  collection_date <- tree_tibble[["Collection_date"]]

  period_end <- dplyr::recode_values(
    tree_tibble[["collection_date_precision"]],
    "day" ~ collection_date,
    "month" ~ lubridate::ceiling_date(collection_date, "month") - 1,
    "year" ~ lubridate::ceiling_date(collection_date, "year") - 1
  )

  limit <- max(period_end, na.rm = TRUE) + slack_days
  predicted_date <- as.Date(tree_tibble[["predicted_date"]])
  stopifnot(length(predicted_date) == nrow(tree_tibble), !anyNA(predicted_date))

  too_late <- which(predicted_date > limit)

  if (length(too_late) > 0) {
    worst <- utils::head(
      too_late[order(predicted_date[too_late], decreasing = TRUE)],
      5
    )
    stop(
      "nodes dated after ",
      limit,
      ", the latest date any tip could have (n = ",
      length(too_late),
      "):\n",
      paste0(
        "  ",
        tree_tibble[["label"]][worst],
        ": ",
        predicted_date[worst],
        collapse = "\n"
      )
    )
  }

  invisible(tree_and_sequences)
}
