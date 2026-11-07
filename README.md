# site-tools

This repo builds the workshop listing on the SMaRT Workshops website.

The listing comes from the "Workshop Cards" Google Sheet, one tab per year. GitHub Actions runs `build_listing.R` every night and publishes the result to GitHub Pages. The Squarespace page holds a two-line code block that loads the published listing each time a visitor opens the page. You do not paste HTML into Squarespace to update the listing.

## Update the listing

1. Edit the sheet.
2. Wait for the nightly run, or open the Actions tab, select "Publish workshop listing", and click "Run workflow".

If the R packages come from the cache, the run takes about two minutes. After it finishes, the Squarespace page shows the new listing within ten minutes, because GitHub Pages lets browsers cache files for that long.

The nightly run also strikes through meeting dates that are past. It uses New York time.

## Start a new year

The sheet has one tab per year. When the new tab is ready, change `year` at the top of `build_listing.R` and push to `main`.

## Files

| File | What it does |
| --- | --- |
| `build_listing.R` | Reads the sheet and writes `_site/workshops.html`. Also copies `site/` into `_site/`. |
| `site/loader.js` | Runs on the Squarespace page. Fetches `workshops.html` into a shadow root (a sealed part of the page) so that the Bootstrap CSS styles only the cards. Wires up the tag filter buttons. |
| `site/snippet.html` | The code block on the Squarespace page. You paste it once. |
| `site/preview.html` | A test page that loads the listing the same way Squarespace does. |
| `.github/workflows/publish.yml` | The nightly build and the deploy to GitHub Pages. |

## Run it locally

The script needs the Google service account key. Copy `service-account.json` into this folder. Git ignores it.

```bash
Rscript build_listing.R
```

To see the result, serve `_site/` and open the preview page. If you open the file directly from disk, the browser blocks the loader's request.

```bash
python3 -m http.server 8765 --directory _site
```

Then open <http://localhost:8765/preview.html>.

## Credentials

This repo is public. Never commit a key.

- In GitHub Actions, the key is the repository secret `GCP_SERVICE_ACCOUNT`. It holds the full JSON text of the key. It is the same key that `daily-job` uses.
- On your computer, the key is `service-account.json` in this folder, which `.gitignore` excludes.

The sheet ID is in `build_listing.R`. The ID alone gives no access: a reader also needs the service account key or a Google account that the sheet is shared with.

## If the listing does not load

If the Squarespace page cannot fetch `workshops.html`, it shows "The workshop list did not load". Open the Actions tab and look at the last run. A failed build leaves the previous listing in place. If the year tab has no published workshops, the build stops on purpose. This prevents an empty listing.
