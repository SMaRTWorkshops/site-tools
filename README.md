# site-tools

This repo builds two parts of the SMaRT Workshops website from the "Workshop Cards" Google Sheet:

- The workshop listing on the /workshops page.
- The details section of each info page: format, live session dates and times, and what a buyer gets.

The sheet has one tab per year. GitHub Actions runs `build_listing.R` every night and publishes the result to GitHub Pages. Each Squarespace page holds a two-line code block that loads the published content each time a visitor opens the page. You do not paste HTML into Squarespace to update the site.

## Update the site

1. Edit the sheet.
2. Wait for the nightly run, or open the Actions tab, select "Publish workshop listing", and click "Run workflow".

If the R packages come from the cache, the run takes about two minutes. After it finishes, Squarespace pages show the new content within ten minutes, because GitHub Pages lets browsers cache files for that long.

The listing works out each live run's state when a visitor opens the page, in New York time, so it never waits for the nightly run:

| When | Where the workshop shows |
| --- | --- |
| Before the first meeting date | "Coming up on Zoom", with its dates. |
| From the first to the last meeting date | "Coming up on Zoom", with "In progress" under its dates. Past dates are struck through. |
| The two days after the last date | "Coming up on Zoom", with "Finished" under its dates and "Full recordings by" the date 48 hours after the last day. |
| After that | "Watch anytime". |

The info page follows the same rule, at the nightly run: after those two days it describes a recorded workshop ("Recorded lectures, watch anytime" and "Workshop recordings available now!"). So after a run you do not need to change `eventtype` to `Independent`. When the row gets next year's dates, the card and the info page show the live version again.

The line above the search box ("1 live workshop coming up · All 32 available to watch now") is counted the same way, so it is right in any month.

## The /workshops page

The code block fills in everything under the "Available Workshops" title: a one-line introduction, the status line, links to discounts, group rates and invoices, the search and filters, and the two sections of cards. The introduction, the discounts and the format explanations used to be Squarespace text and an accordion above the code block. That content is now in the listing, so those blocks are deleted.

The listing uses the site's own fonts and colours (Granville, Brandon Grotesque and the gold accent). It reads them from Squarespace's site styles, so a change there carries over.

Colour on the cards means topic. Each card under "Watch anytime" opens with a tinted band in the colour of its main topic, with an icon, and a card under "Coming up on Zoom" has the same colour and icon in its date block (grey once the run has finished), so a workshop keeps its colour before and after its run. The format is said in words, with a coloured dot. The main topic is the first of the workshop's tags in this order: Funding, Trials, Dyadic, Design, Measurement, Programming, Longitudinal, Analysis, so a specific topic wins over a general one. Design and Trials share a colour and the label "Design & Trials". The order is the `TOPICS` list in `site/loader.js`, and the colours are in `templates/listing.html`. A new topic tag needs an entry in both, or its cards have no band.

The search matches titles, instructors and tags. The instructor menu lists everyone, and a co-taught workshop counts for each of its instructors. Clicking an instructor's name on a card selects them. The filters are kept in the page address, so a filtered view can be linked, for example `/workshops?instructor=Aidan%20Wright` or `/workshops?topics=Mplus`.

## Sheet columns

The card and the info page for a workshop read the same row.

| Column | What it holds |
| --- | --- |
| `title` | Shown on the card. |
| `instructors` | Shown on the card. Separate co-instructors with `&`, for example `Amie Gordon & Kate Thorson`. Each name becomes a filter in the instructor menu. |
| `tags`, `status_badge` | Separated by semicolons. Most tags become filters, grouped as Topic, Software (`R`, `Mplus`, `SPSS`) and Other (`Free`, `Advanced`). A tag that is not in Software or Other is a Topic. Three tags are not filters: `Legacy` is on every workshop and is not shown; `Combo` shows "Combo pricing available" on the card; `New` shows a New badge on a recorded workshop's card. `Free` also shows a Free badge. The badges sit in the card's top-right corner. |
| `link` | The info page address. Its last part (for example `lang-r-info`) names the details file. |
| `eventtype` | `Live`, `Flipped`, or `Independent`. These words are not shown to visitors. The card and the info page say instead "Lectures live on Zoom", "Recorded lectures plus live Zoom meetings", or "Recorded lectures, watch anytime" (set in `how_taught` in `build_listing.R`). A live or flipped workshop shows under "Coming up on Zoom" until 48 hours after its last date, then under "Watch anytime" (see above). |
| `duration` | For example `3 Day` or `3 Half-Day`. The card shows "3 half-days", and the info page shows "3 Half-Day Workshop · Lectures live on Zoom". |
| `meeting_dates` | For example `Jan 12, 13, 14`. A day without a month takes the month before it. For a live workshop whose dates are not set yet, write `TBA` or leave it blank: the card says "Dates to be announced". |
| `dates_year` | The year of `meeting_dates`. If it is the tab's year, leave it blank. Fill it in for a session in the next year, for example a January session in the 2026 tab. |
| `session_et` | The daily session time in Eastern time, for example `9:00 AM - 12:00 PM`. The card shows it once, and the info page shows it for each date. |
| `instructor_tz` | The instructor's time zone, for example `Europe/Stockholm`. When it is filled in, the info page also shows each session in that zone, with daylight saving time worked out per date. Leave it blank for instructors in the US. |
| `videos_now` | Tick it for every live or flipped workshop that has run before: buyers get the recordings from the previous run right away. The card then says "Recordings from the last run available now", and the info page lists what the buyer gets and when. **Leave it blank only for a workshop on its first run.** The card then says "New: recordings by" the date 48 hours after the last session. |
| `instructor_details` | The instructor lines at the top of the info page section, for example `Oscar Kjell, PhD (Lund University; Vanderbilt University)`. Put each instructor on a new line in the cell (Ctrl+Enter, or Cmd+Enter on a Mac). With two or more lines, the label reads "Instructors:". If the cell is blank, the section has no instructor lines. |
| `draft` | Tick it to hide the card. A blank cell also hides the card. The info page details section is built either way. |

If the build cannot read `meeting_dates`, `session_et` or `instructor_tz`, it stops with a message that names the workshop. The site keeps the previous content until you fix the cell.

## Start a new year

When the new tab is ready, change `year` at the top of `build_listing.R` and push to `main`.

## Files

| File | What it does |
| --- | --- |
| `build_listing.R` | Reads the sheet. Writes `_site/workshops.html` and one `_site/details/<page>.html` per info page. Also copies `site/` into `_site/`. |
| `templates/listing.html` | The styles and outline of the /workshops listing. The build adds the workshops to it as data and publishes it as `workshops.html`. |
| `site/loader.js` | Runs on the Squarespace pages. Fills each placeholder from the matching file. Puts the content in a shadow root (a sealed part of the page), so its styles change nothing else on the page. On /workshops it draws the cards from the data and runs the search and filters. |
| `site/snippet.html` | The code block on the /workshops page. |
| `site/details-snippet.html` | The code block on each info page. It is the same on every page, because the loader takes the page name from the page's address. |
| `site/preview.html`, `site/preview-details.html` | Test pages that load the content the same way Squarespace does. |
| `.github/workflows/publish.yml` | The nightly build and the deploy to GitHub Pages. |

## Move an info page to the details section

Do this once per info page.

1. In the sheet, fill in `instructor_details` for the workshop. Run the workflow.
2. In Squarespace, open the page. Edit the text block that starts with "Instructor:".
3. Delete the instructor, "Workshop Format", and "Video Availability" lines, and the blank lines after them. The text block now starts with the description.
4. Above that text block, add a code block. Paste the contents of `site/details-snippet.html` into it.
5. Save. Then open the page while signed out of Squarespace, because the section does not run while you are signed in and editing.

## Run it locally

The script needs the Google service account key. Copy `service-account.json` into this folder. Git ignores it.

```bash
Rscript build_listing.R
```

To preview a change without editing the sheet, write an R file that edits the data frame `raw`, and name it in `LISTING_PATCH`:

```bash
LISTING_PATCH=my-patch.R Rscript build_listing.R
```

To see the result, serve `_site/` and open a preview page. If you open the file directly from disk, the browser blocks the loader's request.

```bash
python3 -m http.server 8765 --directory _site
```

Then open <http://localhost:8765/preview.html> for the listing (add `?sw_today=2027-06-16` to see it as it will look on another day), or <http://localhost:8765/preview-details.html?page=lang-r-info> for an info page section.

## Credentials

This repo is public. Never commit a key. Never put a Zoom link, a materials link, or anything else from a paywalled page in the sheet, because the build publishes it.

- In GitHub Actions, the key is the repository secret `GCP_SERVICE_ACCOUNT`. It holds the full JSON text of the key. It is the same key that `daily-job` uses.
- On your computer, the key is `service-account.json` in this folder, which `.gitignore` excludes.

The sheet ID is in `build_listing.R`. The ID alone gives no access: a reader also needs the service account key or a Google account that the sheet is shared with.

## If something does not load

If a page cannot fetch its file, it shows "The workshop list did not load" or "The workshop schedule did not load". Open the Actions tab and look at the last run. A failed build leaves the previous content in place. If the year tab has no published workshops, the build stops on purpose. This prevents an empty listing.
