# Builds the workshop listing and the info-page details for the SMaRT
# Workshops website.
#
# Reads this year's tab of the workshop Google Sheet and writes _site/, which
# GitHub Actions publishes to GitHub Pages:
#
#   _site/workshops.html          the card listing on the /workshops page
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

# Format a meeting-date string for a card and strike through the dates already
# past
format_dates_html <- function(date_string, yr) {
  if (is.na(date_string) || date_string == "") return("")

  parts <- str_split(date_string, ",")[[1]] |> str_trim() |> str_squish()
  parts <- parts[parts != ""]

  dates <- parse_meeting_dates(date_string, yr)
  is_past <- !is.na(dates) & dates < run_date

  months <- str_extract(parts, "^[A-Za-z]+")
  month <- months[1]
  nums <- suppressWarnings(as.integer(str_extract(parts, "\\d+")))

  # Only parts after the first that repeat its month, or name none, can join a
  # range. Otherwise "Apr 6, May 7" would print as "Apr 6-7".
  one_month <- all(is.na(months[-1]) | months[-1] == month)

  # Compress sequential numbers
  if (length(parts) > 1 && one_month && all(!is.na(nums)) && all(diff(nums) == 1)) {
    if (all(is_past)) {
      return(paste0("<s class='text-muted opacity-75'>", month, " ", nums[1], "-", nums[length(nums)], "</s>"))
    } else if (all(!is_past)) {
      return(paste0(month, " ", nums[1], "-", nums[length(nums)]))
    }
  }

  formatted_parts <- map2_chr(parts, is_past, ~ {
    if (.y) paste0("<s class='text-muted opacity-75'>", .x, "</s>") else .x
  })

  paste(formatted_parts, collapse = ", ")
}

# The next upcoming date, for sorting the cards. Falls back to the first date if
# all are past.
get_sort_date <- function(date_string, yr) {
  dates <- parse_meeting_dates(date_string, yr)
  dates <- dates[!is.na(dates)]
  if (length(dates) == 0) return(as.Date(NA))
  future <- dates[dates >= run_date]
  if (length(future) > 0) min(future) else min(dates)
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


# Tag pills shown on each card
make_tags <- function(tags) {
  if (is.na(tags)) return("")
  tags_sep <- str_squish(str_split(tags, ";")[[1]])
  tags_sep <- tags_sep[tags_sep != ""]
  if (length(tags_sep) == 0) return("")

  out <- map_chr(tags_sep, \(tag) {
    if (tag %in% c("Free", "New")) {
      str_glue('<span class="btn btn-sm filter-btn tag-emph">{tag}</span>')
    } else {
      str_glue('<span class="btn btn-outline-secondary btn-sm filter-btn">{tag}</span>')
    }
  })
  str_c(out, collapse = " ")
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

cards <-
  workshops |>
  filter(!draft) |>
  mutate(
    tags = if_else(!is.na(status_badge), if_else(is.na(tags), status_badge, str_c(tags, ";", status_badge)), tags),
    sortable_date = map2_vec(meeting_dates, row_year, get_sort_date),
    details = str_glue("{duration} Online Workshop"),
    videos_line = if_else(
      videos_now & coalesce(eventtype != "Independent", FALSE),
      "<br /><span class='fw-semibold text-dark'>Recordings available now</span>",
      ""
    ),
    format_class = case_when(
      str_detect(eventtype, "Live") ~ "format-live",
      str_detect(eventtype, "Flipped") ~ "format-flipped",
      str_detect(eventtype, "Independent") ~ "format-indep",
      TRUE ~ "format-self"
    ),
    format_icon = case_when(
      str_detect(eventtype, "Live") ~ "<span class='color-emoji'>🔴</span>",
      str_detect(eventtype, "Flipped") ~ "<span class='color-emoji'>🟣</span>",
      str_detect(eventtype, "Independent") ~ "<span class='color-emoji'>🟢</span>",
      TRUE ~ ""
    ),
    bottom_footer = case_when(
      eventtype == "Independent" ~ str_glue("<span class='d-flex align-items-center gap-2'><span class='color-emoji'>💻</span> Fully Asynchronous</span> <span class='ms-auto format-badge {format_class} d-flex align-items-center gap-1'>Independent {format_icon}</span>"),
      TRUE ~ str_glue("<span class='d-flex align-items-center gap-2'><span class='color-emoji'>📅</span> <span>{map2_chr(meeting_dates, row_year, format_dates_html)}</span></span> <span class='ms-auto format-badge {format_class} d-flex align-items-center gap-1'>{eventtype} {format_icon}</span>")
    )
  ) |>
  arrange(sortable_date, title) |>
  mutate(
    tagscomma = str_replace_all(tags, pattern = ";", replacement = ","),
    tagstring = map_chr(tags, make_tags)
  )

# A sheet that reads as empty (a renamed tab, every row still a draft) would
# otherwise publish an empty listing over the good one. Failing here leaves the
# last published listing in place.
if (nrow(cards) == 0) {
  stop("No published workshops in the '", year, "' tab. Nothing was written.")
}

all_tags <- cards |>
  pull(tags) |>
  str_split(";") |>
  unlist() |>
  str_squish()

unique_tags <- sort(unique(all_tags[all_tags != "" & !is.na(all_tags)]))

button_html_all <- '<button class="btn btn-outline-dark btn-sm filter-btn active" data-tag="all" title="Show all workshops">All</button>'

button_html_tags <- map_chr(unique_tags, \(tag) {
  str_glue('<button class="btn btn-outline-secondary btn-sm filter-btn" data-tag="{tag}" title="Show only {tag}">{tag}</button>')
}) |>
  str_c(collapse = "\n    ")

filter_buttons_html <- str_c(button_html_all, "\n    ", button_html_tags)

# This is what used to sit inside <template id="workshop-template"> in the
# pasted code block. loader.js puts it into a shadow root, so the Bootstrap CSS
# here styles the cards and nothing else on the Squarespace page. The emoji font
# is not linked here: browsers ignore fonts linked inside a shadow root, so
# loader.js adds that link to the page itself.
part1_top <- '<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">

<style>
  .color-emoji {
    font-family: \'Noto Color Emoji\', sans-serif;
    font-size: 1.1em;
    line-height: 1;
  }
  .card {
    background: white;
    border: 1px solid #e2e8f0;
    border-radius: 12px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
    transition: transform 0.2s ease, box-shadow 0.2s ease;
  }

  .card:hover {
    transform: translateY(-4px);
    box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1),
                0 4px 6px -2px rgba(0, 0, 0, 0.05);
  }

  .card-title {
    margin: 0;
    font-size: 1.25rem;
    font-weight: 700;
    color: #1a202c;
  }

  .tag {
    font-size: 0.75rem;
    font-weight: 600;
    color: #4a5568;
    background-color: #f7fafc;
    border: 1px solid #000000;
    border-radius: 20px;
    padding: 4px 12px;
  }

  .tag-emph {
    background-color: #f1f5f9 !important;
    border-color: #64748b !important;
    color: #334155 !important;
    font-weight: 700 !important;
  }

  .filter-btn {
    border: 1px solid currentColor !important;
    border-radius: 50rem !important;
    padding: 2px 10px !important;
    font-size: 0.75rem !important;
    line-height: 1.5 !important;
    box-shadow: none !important;
  }

  .format-live { color: #991b1b; }      /* Dark Red */
  .format-flipped { color: #6b21a8; }   /* Deep Purple */
  .format-indep { color: #166534; }     /* Dark Green */

  .format-badge {
    font-size: 0.95rem;
    font-weight: 700;
  }
</style>

<div class="mb-4 d-flex justify-content-center flex-wrap gap-2">
  <span class="me-2 fw-bold align-self-center">Filter by Tag:</span>
  '

part1_bottom <- '
</div>

<div class="row row-cols-1 row-cols-md-3 g-4">
'

part1 <- str_c(part1_top, filter_buttons_html, part1_bottom)

part2 <- str_c(str_glue(
  '
  <div class="col">
    <div class="card h-100 position-relative custom-shadow" data-tags="{cards$tagscomma}">

      <div class="card-body d-flex flex-column flex-grow-1">
        <h5 class="card-title fw-bold mb-2">{cards$title}</h5>

        <p class="card-text mb-0 text-muted small">
          {cards$details}<br />
          <span class="fst-italic">{cards$instructors}</span>{cards$videos_line}
        </p>

        <div class="mt-auto pt-3">{cards$tagstring}</div>

        <a href="{cards$link}" class="stretched-link"></a>
      </div>

      <div class="card-footer bg-light border-top">
        <div class="small fw-bold text-dark d-flex align-items-center">
          {cards$bottom_footer}
        </div>
      </div>

    </div>
  </div>
  '
), collapse = "")

part3 <- '
</div>
'

built_note <- str_c(
  "<!-- Built ", format(now(tzone = local_tz), "%Y-%m-%d %H:%M %Z"),
  " from the '", year, "' tab by build_listing.R. Do not edit by hand. -->\n"
)

listing <- str_c(built_note, part1, part2, part3)


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

    if (row$videos_now) {
      out <- c(out,
        '<p class="label" style="margin-bottom:0">What you get when you register:</p>',
        paste0(
          "<ol>",
          "<li><strong>Right away:</strong> the complete recordings from the previous run of this workshop.</li>",
          "<li><strong>During the live sessions:</strong> join on Zoom and ask the instructor questions.</li>",
          "<li><strong>After each live session:</strong> its recording is posted to your workshop page.</li>",
          "</ol>"
        ))
    } else {
      out <- c(out, '<p><span class="label">Video Availability:</span><br>Each live session is recorded and posted to your workshop page.</p>')
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
