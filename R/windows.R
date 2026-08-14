makeWindows <- function(
  first_start,
  width,
  increment,
  min_width,
  last_date
) {
  starts <- seq(first_start, last_date, by = increment)
  starts <- starts[starts + lubridate::period(min_width) <= last_date]

  window_end <- starts + lubridate::period(width) - 1
  window_end[length(starts)] <- last_date

  tibble::tibble(window_start = starts, window_end = window_end)
}
