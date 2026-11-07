/*
 * SMaRT Workshops listing loader.
 *
 * The Squarespace code block (snippet.html) holds an empty
 * <div id="workshop-host"> and this script. The script fetches workshops.html
 * from the same folder it was loaded from and puts it into a shadow root on the
 * host, so the listing's Bootstrap CSS cannot restyle the rest of the page.
 * build_listing.R writes workshops.html; this file does not change when the
 * workshops do.
 */
(function () {
  var FALLBACK_BASE = "https://smartworkshops.github.io/site-tools/";
  var EMOJI_FONT = "https://fonts.googleapis.com/css2?family=Noto+Color+Emoji&display=swap";

  // Chrome and Safari ignore @font-face rules that load inside a shadow root,
  // so the emoji font goes on the page itself. The cards still pick it up,
  // because fonts registered on the page are visible inside the shadow root.
  if (!document.querySelector('link[href="' + EMOJI_FONT + '"]')) {
    var fontLink = document.createElement("link");
    fontLink.rel = "stylesheet";
    fontLink.href = EMOJI_FONT;
    document.head.appendChild(fontLink);
  }

  var script = document.currentScript;
  var base = script && script.src ? script.src.replace(/[^\/]*$/, "") : FALLBACK_BASE;

  var host = document.getElementById("workshop-host");
  if (!host || host.shadowRoot) return;

  var shadow = host.attachShadow({ mode: "open" });
  shadow.innerHTML =
    '<p style="text-align:center;color:#64748b;padding:2rem 0">Loading workshops&hellip;</p>';

  fetch(base + "workshops.html", { cache: "no-cache" })
    .then(function (response) {
      if (!response.ok) throw new Error("HTTP " + response.status);
      return response.text();
    })
    .then(function (html) {
      shadow.innerHTML = html;
      wireFilters(shadow);
    })
    .catch(function (err) {
      console.error("SMaRT Workshops listing did not load:", err);
      shadow.innerHTML =
        '<p style="text-align:center;padding:2rem 0">The workshop list did not load. ' +
        "Please refresh the page to try again.</p>";
    });

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
})();
