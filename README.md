# site-tools

This repo builds two parts of the SMaRT Workshops website from the "Workshop Cards" Google Sheet:

- The workshop listing on the /workshops page.
- The details section of each info page: format, live session dates and times, and what a buyer gets.

The sheet has one tab per year. GitHub Actions runs `build_listing.R` every night and publishes the result to GitHub Pages. Each Squarespace page holds a two-line code block that loads the published content each time a visitor opens the page. You do not paste HTML into Squarespace to update the site.

## Update the site

1. Edit the sheet.
2. Wait for the nightly run, or open the Actions tab, select "Publish workshop listing", and click "Run workflow".

If the R packages come from the cache, the run takes about two minutes. After it finishes, Squarespace pages show the new content within ten minutes, because GitHub Pages lets browsers cache files for that long.

The nightly run also strikes through meeting dates that are past. It uses New York time.

## Sheet columns

The card and the info page for a workshop read the same row.

| Column | What it holds |
| --- | --- |
| `title`, `instructors`, `tags`, `status_badge` | Shown on the card. |
| `link` | The info page address. Its last part (for example `lang-r-info`) names the details file. |
| `eventtype` | `Live`, `Flipped`, or `Independent`. |
| `duration` | For example `3 Day` or `3 Half-Day`. The card shows "3 Half-Day Online Workshop", and the info page shows "3 Half-Day Live Workshop on Zoom". |
| `meeting_dates` | For example `Jan 12, 13, 14`. A day without a month takes the month before it. |
| `dates_year` | The year of `meeting_dates`. If it is the tab's year, leave it blank. Fill it in for a session in the next year, for example a January session in the 2026 tab. |
| `session_et` | The daily session time in Eastern time, for example `9:00 AM - 12:00 PM`. The info page shows it for each date. |
| `instructor_tz` | The instructor's time zone, for example `Europe/Stockholm`. When it is filled in, the info page also shows each session in that zone, with daylight saving time worked out per date. Leave it blank for instructors in the US. |
| `videos_now` | If buyers of a live workshop get the recordings from the previous run right away, tick it. The card then says "Recordings available now", and the info page lists what the buyer gets and when. |
| `draft` | Tick it to hide the card. A blank cell also hides the card. The info page details section is built either way. |

If the build cannot read `session_et` or `instructor_tz`, it stops with a message that names the workshop. The site keeps the previous content until you fix the cell.

## Start a new year

When the new tab is ready, change `year` at the top of `build_listing.R` and push to `main`.

## Files

| File | What it does |
| --- | --- |
| `build_listing.R` | Reads the sheet. Writes `_site/workshops.html` and one `_site/details/<page>.html` per info page. Also copies `site/` into `_site/`. |
| `site/loader.js` | Runs on the Squarespace pages. Fills each placeholder from the matching file. Puts the content in a shadow root (a sealed part of the page), so its styles change nothing else on the page. Wires up the tag filter buttons. |
| `site/snippet.html` | The code block on the /workshops page. |
| `site/details-snippet.html` | The code block on each info page. It is the same on every page, because the loader takes the page name from the page's address. |
| `site/preview.html`, `site/preview-details.html` | Test pages that load the content the same way Squarespace does. |
| `.github/workflows/publish.yml` | The nightly build and the deploy to GitHub Pages. |

## Move an info page to the details section

Do this once per info page.

1. In Squarespace, open the page and edit the text block that holds "Instructor:", "Workshop Format:", and "Video Availability:".
2. Delete the "Workshop Format" and "Video Availability" lines. Keep the instructor lines.
3. Below that text block, add a code block. Paste the contents of `site/details-snippet.html` into it.
4. Save, then open the page while signed out of Squarespace. The section does not run while you are signed in and editing.

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

Then open <http://localhost:8765/preview.html> for the listing, or <http://localhost:8765/preview-details.html?page=lang-r-info> for an info page section.

## Credentials

This repo is public. Never commit a key. Never put a Zoom link, a materials link, or anything else from a paywalled page in the sheet, because the build publishes it.

- In GitHub Actions, the key is the repository secret `GCP_SERVICE_ACCOUNT`. It holds the full JSON text of the key. It is the same key that `daily-job` uses.
- On your computer, the key is `service-account.json` in this folder, which `.gitignore` excludes.

The sheet ID is in `build_listing.R`. The ID alone gives no access: a reader also needs the service account key or a Google account that the sheet is shared with.

## If something does not load

If a page cannot fetch its file, it shows "The workshop list did not load" or "The workshop schedule did not load". Open the Actions tab and look at the last run. A failed build leaves the previous content in place. If the year tab has no published workshops, the build stops on purpose. This prevents an empty listing.
