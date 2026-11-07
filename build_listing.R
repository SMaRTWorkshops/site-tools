# Builds the workshop listing and the info-page details for the SMaRT
# Workshops website.
#
# Reads this year's tab of the workshop Google Sheet and writes _site/, which
# GitHub Actions publishes to GitHub Pages:
#
#   _site/workshops.html          the listing on the /workshops page: the
#                                 styles and outline from
#                                 templates/listing.html, plus the workshops
#                                 as data that loader.js draws as cards
#   _site/details/<page>.html     the format, live sessions, and video access
#                                 section of each info page, for example
#                                 details/lang-r-info.html for /lang-r-info
#
# The Squarespace pages hold only short code blocks (site/snippet.html and
# site/details-snippet.html). Their script, site/loader.js, fetches these files
# each time a visitor opens the page.
#
# Run locally with:  Rscript build_listing.R
# then open _site/preview.html through a local web server (see README.md).

options(tidyverse.quiet = TRUE)
suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(purrr)
  library(lubridate)
  library(googlesheets4)
  library(jsonlite)
})


# Configuration -----------------------------------------------------------

# The sheet has one tab per year. Change this when the new year's tab is ready.
year <- "2026"

sheet_id <- "118113pxjcst_EZgbxYPyAKDTYmr0v-cEeFudTZ1TVCM"

# Dates before today are struck through, and "today" is taken in this zone, so
# the nightly run on a UTC server does not strike a date a few hours early.
# Session times in the sheet are also in this zone.
local_tz <- "America/New_York"
run_date <- today(tzone = local_tz)

out_dir <- "_site"


# Authentication ----------------------------------------------------------

# In GitHub Actions the key arrives as JSON text in GCP_SERVICE_ACCOUNT, the same
# secret daily-job uses. Locally it is the gitignored service-account.json.
service_account_txt <- Sys.getenv("GCP_SERVICE_ACCOUNT")
if (nzchar(service_account_txt)) {
  gs4_auth(path = service_account_txt)
} else if (file.exists("service-account.json")) {
  gs4_auth(path = "service-account.json")
} else {
  stop("No Google key. Put service-account.json in this folder, ",
       "or set GCP_SERVICE_ACCOUNT to the key's path or JSON text.")
}


read_file_text <- function(path) paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")


# Date and time helpers ---------------------------------------------------

# Turn "Jan 12, 13, 14" into dates. A part without a month name takes the month
# of the part before it.
parse_meeting_dates <- function(date_string, yr) {
  if (is.na(date_string) || str_squish(date_string) == "") return(as.Date(character(0)))

  parts <- str_split(date_string, ",")[[1]] |> str_squish()
  parts <- parts[parts != ""]

  current_month <- NA_character_
  out <- as.Date(rep(NA, length(parts)))
  for (i in seq_along(parts)) {
    m <- str_extract(parts[i], "^[A-Za-z]+")
    if (!is.na(m)) current_month <- m
    d <- str_extract(parts[i], "\\d+")
    if (!is.na(current_month) && !is.na(d)) {
      out[i] <- mdy(paste(current_month, d, yr), quiet = TRUE)
    }
  }
  out
}

# Parse "9:00 AM - 12:00 PM" (Eastern) into start and end clock times. Returns
# NULL for a blank cell and stops the build for one it cannot read, because a
# wrong time on a live workshop page is worse than yesterday's page.
parse_session_et <- function(x, title) {
  if (is.na(x) || str_squish(x) == "") return(NULL)
  ends <- str_split(str_squish(x), "\\s*(-|–|—|to)\\s*")[[1]]
  times <- parse_date_time(paste("2000-01-01", ends), orders = c("Ymd IMp", "Ymd Ip", "Ymd HM"),
                           tz = "UTC", quiet = TRUE)
  if (length(ends) != 2 || any(is.na(times))) {
    stop("Cannot read session_et '", x, "' for '", title, "'. ",
         "Write it like 9:00 AM - 12:00 PM, in Eastern time.")
  }
  format(times, "%H:%M")
}

# "9:30 AM", or "9 AM" on the hour. Built by hand because format codes that
# drop leading zeros (%-I) work on Linux but not in R on macOS or Windows.
fmt_12h <- function(t) {
  h <- hour(t) %% 12
  h[h == 0] <- 12
  m <- minute(t)
  paste0(h, if_else(m == 0, "", sprintf(":%02d", m)), if_else(hour(t) < 12, " AM", " PM"))
}

# "Tue, Jan 12"
fmt_day <- function(d) paste0(format(d, "%a, %b "), mday(d))

# One row of the live-sessions table: the Eastern date and time, and the
# instructor's local time when the instructor_tz cell names a time zone.
session_row_html <- function(date, hm, instructor_tz) {
  start <- ymd_hm(paste(date, hm[1]), tz = local_tz)
  end <- ymd_hm(paste(date, hm[2]), tz = local_tz)
  past <- date < run_date

  et_text <- paste0(fmt_12h(start), "–", fmt_12h(end), " ET")
  local_text <- ""
  if (!is.na(instructor_tz)) {
    ls <- with_tz(start, instructor_tz)
    le <- with_tz(end, instructor_tz)
    # Name the day when the local session falls on a different date
    day_note <- if (as_date(ls) != date) format(ls, "%a ") else ""
    local_text <- paste0(day_note, format(ls, "%H:%M"), "–", format(le, "%H:%M"), " ", format(ls, "%Z"))
  }

  cells <- c(fmt_day(date), et_text, local_text)
  cells <- cells[cells != ""]
  row <- paste0("<td>", cells, "</td>", collapse = "")
  if (past) row <- str_replace_all(row, "<td>(.*?)</td>", "<td><s>\\1</s></td>")
  paste0("<tr>", row, "</tr>")
}


# 1. Read the sheet -------------------------------------------------------

raw <- read_sheet(sheet_id, sheet = year)

# Columns added for the info-page details. A tab without them still builds:
# every row then reads as blank in them.
#   dates_year     year of this row's meeting_dates, when it is not the tab's
#                  year (a January session announced in the autumn)
#   session_et     daily session time in Eastern time, e.g. 9:00 AM - 12:00 PM
#   instructor_tz  the instructor's time zone, e.g. Europe/Stockholm, when the
#                  page also gives the sessions in the instructor's local time
#   videos_now     ticked when buyers of a live workshop get the recordings
#                  from the previous run right away
#   instructor_details
#                  the instructor lines at the top of the info page section,
#                  one instructor per line, e.g. Oscar Kjell, PhD (Lund
#                  University; Vanderbilt University)
for (nm in c("dates_year", "session_et", "instructor_tz", "videos_now", "instructor_details")) {
  if (!nm %in% names(raw)) raw[[nm]] <- NA
}

# For local testing only: an R file that edits `raw`, so a change can be
# previewed without touching the sheet. Never set in GitHub Actions.
if (nzchar(Sys.getenv("LISTING_PATCH"))) source(Sys.getenv("LISTING_PATCH"))

as_text <- function(x) {
  if (is.list(x)) x <- map_chr(x, \(v) if (length(v) == 0 || all(is.na(v))) NA_character_ else as.character(v[[1]]))
  x <- as.character(x)
  x[!is.na(x) & str_squish(x) == ""] <- NA
  x
}

workshops <-
  raw |>
  mutate(
    across(c(title, link, instructors, status_badge, eventtype, duration,
             meeting_dates, tags, session_et, instructor_tz, instructor_details), as_text),
    row_year = coalesce(suppressWarnings(as.integer(as_text(dates_year))), as.integer(year)),
    videos_now = coalesce(as.logical(as_text(videos_now)), FALSE),
    # A blank draft cell hides the row, as it always has: a row added below the
    # checkboxes stays off the site until it gets one.
    draft = coalesce(as.logical(as_text(draft)), TRUE),
    page = str_extract(link, "[^/]+$")
  )

bad_tz <- workshops |> filter(!is.na(instructor_tz), !instructor_tz %in% OlsonNames())
if (nrow(bad_tz) > 0) {
  stop("Unknown instructor_tz '", bad_tz$instructor_tz[1], "' for '", bad_tz$title[1],
       "'. Use a name like Europe/Stockholm (see the tz database list on Wikipedia).")
}

dup_pages <- workshops |> filter(!is.na(page)) |> count(page) |> filter(n > 1)
if (nrow(dup_pages) > 0) {
  stop("Two rows link to the same page: ", paste(dup_pages$page, collapse = ", "))
}


# 2. Cards ----------------------------------------------------------------

# The listing is published as data. loader.js draws the cards from it in the
# visitor's browser, so a run's state (coming up, in progress, just finished,
# watch anytime) follows the visitor's date rather than last night's build.

# How the tag filters are grouped. Any other tag is a topic. The hidden tags are
# not filters: Legacy is on every card, Combo is a line on the card, and New is
# a badge on the card.
software_tags <- c("R", "Mplus", "SPSS")
other_tags <- c("Free", "Advanced")
hidden_tags <- c("Legacy", "Combo", "New")

split_cell <- function(x, pattern) {
  if (is.na(x)) return(character(0))
  out <- str_squish(str_split(x, pattern)[[1]])
  out[out != ""]
}

# "8 AM–11 AM ET", from a session_et cell
session_text <- function(x, title) {
  hm <- parse_session_et(x, title)
  if (is.null(hm)) return(NA_character_)
  t <- ymd_hm(paste("2000-01-01", hm), tz = "UTC")
  # \u2013 is an en dash, written as an escape so the output does not depend
  # on the locale R runs in
  paste0(fmt_12h(t[1]), "\u2013", fmt_12h(t[2]), " ET")
}

card_data <- function(row) {
  tags <- split_cell(row$tags, ";")
  format <- case_when(
    str_detect(coalesce(row$eventtype, ""), "Live") ~ "live",
    str_detect(coalesce(row$eventtype, ""), "Flipped") ~ "flipped",
    TRUE ~ "independent"
  )
  live <- format != "independent"

  has_dates <- live && str_detect(coalesce(row$meeting_dates, ""), "\\d")
  dates <- if (has_dates) parse_meeting_dates(row$meeting_dates, row$row_year) else as.Date(character(0))
  # A date cell with numbers that will not read would put a live workshop on
  # the wrong days. "TBA" or a blank cell is fine: the card says dates to come.
  if (any(is.na(dates))) {
    stop("Cannot read meeting_dates '", row$meeting_dates, "' for '", row$title, "'. ",
         "Write them like Jan 12, 13, 14.")
  }

  list(
    title = row$title,
    link = row$link,
    duration = row$duration,
    instructors = I(split_cell(row$instructors, "\\s*(&|;|\\s+and\\s+)\\s*")),
    format = format,
    dates = I(format(sort(dates), "%Y-%m-%d")),
    time = if (live) session_text(row$session_et, row$title) else NA_character_,
    # A live or flipped workshop without last run's videos is on its first run:
    # every returning live workshop comes with them.
    first_run = live && !row$videos_now,
    new = (live && !row$videos_now) || "New" %in% tags,
    free = "Free" %in% tags,
    combo = "Combo" %in% tags,
    tags = I(setdiff(tags, c(hidden_tags, "Free")))
  )
}

cards <-
  workshops |>
  filter(!draft) |>
  mutate(tags = if_else(!is.na(status_badge), if_else(is.na(tags), status_badge, str_c(tags, ";", status_badge)), tags))

# A sheet that reads as empty (a renamed tab, every row still a draft) would
# otherwise publish an empty listing over the good one. Failing here leaves the
# last published listing in place.
if (nrow(cards) == 0) {
  stop("No published workshops in the '", year, "' tab. Nothing was written.")
}

card_list <- map(seq_len(nrow(cards)), \(i) card_data(cards[i, ]))

# Free is a filter too, though the card shows it as a badge rather than a tag.
all_tags <- sort(unique(c(
  unlist(map(card_list, "tags")),
  if (any(map_lgl(card_list, "free"))) "Free"
)))
filter_groups <- list(
  list(label = "Topic", tags = I(setdiff(all_tags, c(software_tags, other_tags)))),
  list(label = "Software", tags = I(intersect(software_tags, all_tags))),
  list(label = "Other", tags = I(intersect(other_tags, all_tags)))
)
filter_groups <- keep(filter_groups, \(g) length(g$tags) > 0)

built_note <- str_c(
  "<!-- Built ", format(now(tzone = local_tz), "%Y-%m-%d %H:%M %Z"),
  " from the '", year, "' tab by build_listing.R. Do not edit by hand. -->\n"
)

listing_json <-
  toJSON(
    list(groups = filter_groups, cards = card_list),
    auto_unbox = TRUE, na = "null", null = "null"
  ) |>
  # The data sits inside a <script> element, which a "</" in a title would end.
  str_replace_all(fixed("</"), "<\\/")

listing <-
  read_file_text("templates/listing.html") |>
  str_replace(fixed("<!-- DATA -->"), str_c(
    '<script type="application/json" id="sw-data">', listing_json, "</script>"
  ))
listing <- str_c(built_note, listing)


# 3. Info-page details ----------------------------------------------------

# The section of an info page under the instructor line: format, live session
# dates and times, and what a buyer gets. It inherits the page's font and
# colour. The size and centring copy the "Instructor:" text above it, which
# Squarespace sets as Large text: --large-text-size-value is the site's own
# setting for that size and reaches inside the shadow root.
details_style <- '<style>
  :host {
    display: block;
    text-align: center;
    font-size: calc((var(--large-text-size-value, 1.6) - 1) * 1.2vw + 1rem);
    line-height: 1.6;
  }
  p { margin: 0 0 1em; }
  .label { font-weight: 700; }
  table { border-collapse: collapse; margin: 0 auto 1em; text-align: left; }
  td { padding: 0 0.75em; vertical-align: top; }
  td:last-child { opacity: 0.75; }
  ol { display: inline-block; margin: 0 0 1em; padding-left: 1.4em; text-align: left; max-width: 34em; }
  li { margin: 0 0 0.35em; }
  @media (max-width: 600px) {
    table { text-align: center; }
    td { display: block; padding: 0; }
    tr { display: block; margin: 0 0 0.6em; }
  }
</style>
'

escape_html <- function(x) {
  x |>
    str_replace_all("&", "&amp;") |>
    str_replace_all("<", "&lt;") |>
    str_replace_all(">", "&gt;")
}

make_details <- function(row) {
  live <- !is.na(row$eventtype) && row$eventtype != "Independent"
  where <- if (live) " on Zoom" else ""
  out <- character(0)

  if (!is.na(row$instructor_details)) {
    lines <- str_split(row$instructor_details, "\\s*\\n\\s*")[[1]]
    lines <- escape_html(lines[lines != ""])
    label <- if (length(lines) > 1) "Instructors:" else "Instructor:"
    out <- c(out, str_glue('<p><span class="label">{label}</span><br>{paste(lines, collapse = "<br>")}</p>'))
  }

  out <- c(out, str_glue('<p><span class="label">Workshop Format:</span><br>{row$duration} {row$eventtype} Workshop{where}</p>'))

  if (live) {
    dates <- parse_meeting_dates(row$meeting_dates, row$row_year)
    dates <- dates[!is.na(dates)]
    hm <- parse_session_et(row$session_et, row$title)
    if (length(dates) > 0) {
      if (is.null(hm)) {
        rows <- paste0("<tr><td>", fmt_day(dates), "</td></tr>", collapse = "")
      } else {
        rows <- paste(map_chr(dates, \(d) session_row_html(d, hm, row$instructor_tz)), collapse = "")
      }
      out <- c(out, str_glue('<p class="label" style="margin-bottom:0">Live Sessions ({format(dates[1], "%Y")}):</p>'),
               str_glue("<table>{rows}</table>"))
    }

    # The promise: a run's recordings are on the workshop page within 48 hours
    # after its last day ends, so by the end of the second day after it.
    posted_by <- if (length(dates) > 0) paste0(" (by ", fmt_day(max(dates) + 2), ")") else ""

    if (row$videos_now) {
      out <- c(out,
        '<p class="label" style="margin-bottom:0">What you get when you register:</p>',
        paste0(
          "<ol>",
          "<li><strong>Right away:</strong> the complete recordings from the previous run of this workshop.</li>",
          "<li><strong>During the live sessions:</strong> join on Zoom and ask the instructor questions.</li>",
          "<li><strong>After the last live session:</strong> the new recordings are posted to your workshop page within 48 hours", posted_by, ".</li>",
          "</ol>"
        ))
    } else {
      out <- c(out, paste0('<p><span class="label">Video Availability:</span><br>Every live session is recorded. ',
                           'The recordings are posted to your workshop page within 48 hours after the last session ends',
                           posted_by, '.</p>'))
    }
    out <- c(out, "<p>Attending live is optional, because every session is recorded. We encourage you to join if you can: it is your chance to ask the instructor questions.</p>")
  } else {
    out <- c(out, '<p><span class="label">Video Availability:</span><br>Workshop recordings available now!</p>')
  }

  str_c(built_note, details_style, str_c(out, collapse = "\n"), "\n")
}

# Every row with a page and a format gets a section, drafts included, because an
# info page can be up before its card is.
detail_pages <- workshops |> filter(!is.na(page), !is.na(eventtype), !is.na(duration))


# 4. Write _site/ ---------------------------------------------------------

unlink(out_dir, recursive = TRUE)
dir.create(file.path(out_dir, "details"), recursive = TRUE)
invisible(file.copy(list.files("site", full.names = TRUE), out_dir))
writeLines(listing, file.path(out_dir, "workshops.html"), useBytes = TRUE)

for (i in seq_len(nrow(detail_pages))) {
  row <- detail_pages[i, ]
  writeLines(make_details(row), file.path(out_dir, "details", paste0(row$page, ".html")), useBytes = TRUE)
}

message("Wrote ", nrow(cards), " workshops to ", file.path(out_dir, "workshops.html"))
message("Wrote ", nrow(detail_pages), " info-page sections to ", file.path(out_dir, "details"))
