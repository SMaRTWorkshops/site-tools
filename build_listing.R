# Builds the workshop listing for the SMaRT Workshops website.
#
# Reads this year's tab of the workshop Google Sheet and writes _site/, which
# GitHub Actions publishes to GitHub Pages. The Squarespace page holds only the
# short code block in site/snippet.html; its script (site/loader.js) fetches
# _site/workshops.html each time a visitor opens the page.
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


# Helpers -----------------------------------------------------------------

# Format a meeting-date string and strike through the dates already past
format_dates_html <- function(date_string, current_year) {
  if (is.na(date_string) || date_string == "") return("")

  # Split by comma, trim all whitespace, and drop any empty trailing elements
  parts <- str_split(date_string, ",")[[1]] |> str_trim() |> str_squish()
  parts <- parts[parts != ""]

  current_month <- NA_character_
  is_past <- logical(length(parts))

  for (i in seq_along(parts)) {
    m <- str_extract(parts[i], "^[A-Za-z]+")
    if (!is.na(m)) current_month <- m

    d <- str_extract(parts[i], "\\d+")
    if (!is.na(current_month) && !is.na(d)) {
      date_val <- mdy(paste(current_month, d, current_year), quiet = TRUE)
      is_past[i] <- !is.na(date_val) && date_val < run_date
    }
  }

  month <- str_extract(parts[1], "^[A-Za-z]+")
  nums <- suppressWarnings(as.integer(str_extract(parts, "\\d+")))

  # Compress sequential numbers
  if (length(parts) > 1 && all(!is.na(nums)) && all(diff(nums) == 1)) {
    if (all(is_past)) {
      return(paste0("<s class='text-muted opacity-75'>", month, " ", nums[1], "-", nums[length(nums)], "</s>"))
    } else if (all(!is_past)) {
      return(paste0(month, " ", nums[1], "-", nums[length(nums)]))
    }
  }

  # Apply HTML tags to individual parts using paste0 for strict spacing
  formatted_parts <- map2_chr(parts, is_past, ~ {
    if (.y) {
      paste0("<s class='text-muted opacity-75'>", .x, "</s>")
    } else {
      .x
    }
  })

  return(paste(formatted_parts, collapse = ", "))
}

# Find the next upcoming date for sorting
get_sort_date <- function(day_list, current_year) {
  if (length(day_list) == 0 || all(is.na(day_list))) return(as.Date(NA))

  current_month <- NA_character_
  parsed_dates <- as.Date(character(0))

  for (p in day_list) {
    # Extract month if present, otherwise carry over the previous month
    m <- str_extract(p, "^[A-Za-z]+")
    if (!is.na(m)) current_month <- m

    # Extract day number
    d <- str_extract(p, "\\d+")

    if (!is.na(current_month) && !is.na(d)) {
      date_val <- mdy(paste(current_month, d, current_year), quiet = TRUE)
      if (!is.na(date_val)) {
        parsed_dates <- c(parsed_dates, date_val)
      }
    }
  }

  if (length(parsed_dates) == 0) return(as.Date(NA))

  future_dates <- parsed_dates[parsed_dates >= run_date]

  if (length(future_dates) > 0) {
    return(min(future_dates)) # Sort by the next closest future date
  } else {
    return(min(parsed_dates)) # Fallback: original start date if all are in the past
  }
}

# Tag pills shown on each card
make_tags <- function(tags) {
  if (is.na(tags)) {
    return("")
  }
  tags_sep <- str_squish(str_split(tags, ";")[[1]])
  tags_sep <- tags_sep[tags_sep != ""]
  if (length(tags_sep) == 0) {
    return("")
  }

  out <- map_chr(tags_sep, \(tag) {
    if (tag %in% c("Free", "New")) {
      str_glue('<span class="btn btn-sm filter-btn tag-emph">{tag}</span>')
    } else {
      str_glue('<span class="btn btn-outline-secondary btn-sm filter-btn">{tag}</span>')
    }
  })
  str_c(out, collapse = " ")
}


# 1. Process the workshop data --------------------------------------------

cards <-
  read_sheet(sheet_id, sheet = year) |>
  filter(draft != TRUE) |>
  mutate(
    tags = if_else(!is.na(status_badge) & status_badge != "", str_c(tags, ";", status_badge), tags),
    day_list = str_split(meeting_dates, ","),
    day_list = map(day_list, str_squish),
    sortable_date = map_vec(day_list, ~ get_sort_date(.x, year)),
    details = str_glue("{duration} Online Workshop"),
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
      TRUE ~ str_glue("<span class='d-flex align-items-center gap-2'><span class='color-emoji'>📅</span> <span>{map_chr(meeting_dates, ~ format_dates_html(.x, year))}</span></span> <span class='ms-auto format-badge {format_class} d-flex align-items-center gap-1'>{eventtype} {format_icon}</span>")
    )
  ) |>
  arrange(sortable_date, title) |>
  select(-day_list, -sortable_date, -format_class, -format_icon) |>
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


# 2. Filter buttons, one per unique tag -----------------------------------

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


# 3. Assemble the listing -------------------------------------------------

# This is what used to sit inside <template id="workshop-template"> in the
# pasted code block. loader.js puts it into a shadow root, so the Bootstrap CSS
# here styles the cards and nothing else on the Squarespace page.
part1_top <- '<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link href="https://fonts.googleapis.com/css2?family=Noto+Color+Emoji&display=swap" rel="stylesheet">

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
          <span class="fst-italic">{cards$instructors}</span>
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

listing <- str_c(
  "<!-- Built ", format(now(tzone = local_tz), "%Y-%m-%d %H:%M %Z"),
  " from the '", year, "' tab by build_listing.R. Do not edit by hand. -->\n",
  part1, part2, part3
)


# 4. Write _site/ ---------------------------------------------------------

unlink(out_dir, recursive = TRUE)
dir.create(out_dir)
invisible(file.copy(list.files("site", full.names = TRUE), out_dir))
writeLines(listing, file.path(out_dir, "workshops.html"), useBytes = TRUE)

message("Wrote ", nrow(cards), " workshops to ", file.path(out_dir, "workshops.html"))
