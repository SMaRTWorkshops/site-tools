/*
 * SMaRT Workshops loader.
 *
 * Runs on Squarespace pages and fills in two kinds of empty placeholder:
 *
 *   <div id="workshop-host"></div>
 *     The card listing on /workshops (snippet.html). Filled from
 *     workshops.html, with working tag filters.
 *
 *   <div class="sw-details"></div>
 *     The format, live sessions, and video access section of an info page
 *     (details-snippet.html). Filled from details/<page>.html, where <page> is
 *     the last part of the page's address, for example lang-r-info. A
 *     data-page="..." attribute on the div overrides that.
 *
 * Each placeholder gets a shadow root, so the styles that come with the content
 * cannot change the rest of the page. build_listing.R writes the content files;
 * this file does not change when the workshops do.
 */
(function () {
  var FALLBACK_BASE = "https://smartworkshops.github.io/site-tools/";
  var EMOJI_FONT = "https://fonts.googleapis.com/css2?family=Noto+Color+Emoji&display=swap";

  var script = document.currentScript;
  var base = script && script.src ? script.src.replace(/[^\/]*$/, "") : FALLBACK_BASE;

  function fill(host, url, loadingHtml, failHtml, after) {
    if (!host || host.shadowRoot) return;
    var shadow = host.attachShadow({ mode: "open" });
    shadow.innerHTML = loadingHtml;

    fetch(url, { cache: "no-cache" })
      .then(function (response) {
        if (!response.ok) throw new Error("HTTP " + response.status);
        return response.text();
      })
      .then(function (html) {
        shadow.innerHTML = html;
        if (after) after(shadow);
      })
      .catch(function (err) {
        console.error("SMaRT Workshops content did not load from " + url + ":", err);
        shadow.innerHTML = failHtml;
      });
  }

  // The card listing ------------------------------------------------------

  var listing = document.getElementById("workshop-host");
  if (listing) {
    // Chrome and Safari ignore @font-face rules that load inside a shadow
    // root, so the emoji font goes on the page itself. The cards still pick it
    // up, because fonts registered on the page are visible inside the shadow
    // root.
    if (!document.querySelector('link[href="' + EMOJI_FONT + '"]')) {
      var fontLink = document.createElement("link");
      fontLink.rel = "stylesheet";
      fontLink.href = EMOJI_FONT;
      document.head.appendChild(fontLink);
    }

    fill(
      listing,
      base + "workshops.html",
      '<p style="text-align:center;color:#64748b;padding:2rem 0">Loading workshops&hellip;</p>',
      '<p style="text-align:center;padding:2rem 0">The workshop list did not load. ' +
        "Please refresh the page to try again.</p>",
      wireFilters
    );
  }

  function wireFilters(root) {
    var filterButtons = root.querySelectorAll(".filter-btn[data-tag]");
    var cards = root.querySelectorAll(".card");

    filterButtons.forEach(function (button) {
      button.addEventListener("click", function () {
        filterButtons.forEach(function (btn) { btn.classList.remove("active"); });
        button.classList.add("active");

        var tag = button.getAttribute("data-tag");
        cards.forEach(function (card) {
          var attr = card.getAttribute("data-tags");
          var cardTags = attr ? attr.split(",").map(function (t) { return t.trim(); }) : [];
          var show = tag === "all" || cardTags.indexOf(tag) !== -1;
          if (card.parentElement) {
            card.parentElement.style.display = show ? "block" : "none";
          }
        });
      });
    });
  }

  // Info-page details -----------------------------------------------------

  var pageFromPath = window.location.pathname.replace(/\/+$/, "").split("/").pop();

  document.querySelectorAll(".sw-details").forEach(function (host) {
    var page = host.getAttribute("data-page") || pageFromPath;
    if (!/^[A-Za-z0-9_-]+$/.test(page)) return;
    fill(
      host,
      base + "details/" + page + ".html",
      "",
      "<p>The workshop schedule did not load. Please refresh the page to try again.</p>",
      null
    );
  });
})();
