/*
 * SMaRT Workshops loader.
 *
 * Runs on Squarespace pages and fills in two kinds of empty placeholder:
 *
 *   <div id="workshop-host"></div>
 *     The card listing on /workshops (snippet.html). Filled from
 *     workshops.html, which holds the styles, the page outline and the
 *     workshops as data. This file draws the cards from the data and runs the
 *     search and filters.
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
    fill(
      listing,
      base + "workshops.html",
      '<p style="text-align:center;color:#666;padding:2rem 0">Loading workshops&hellip;</p>',
      '<p style="text-align:center;padding:2rem 0">The workshop list did not load. ' +
        "Please refresh the page to try again.</p>",
      drawListing
    );
  }

  // The listing ----------------------------------------------------------
  //
  // A live or flipped run is "coming up" until its first day, "in progress"
  // until its last, "finished" for the 48 hours in which its recordings are
  // posted, and after that the workshop moves to "Watch anytime". Days are
  // taken in New York time, like the dates in the sheet. The info pages switch
  // at the same point (posting_days in build_listing.R).

  var POSTING_DAYS = 2;
  var MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  var DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

  // "2027-01-12" as a whole number of days, for arithmetic
  function dayNum(iso) {
    var p = iso.split("-");
    return Date.UTC(+p[0], +p[1] - 1, +p[2]) / 864e5;
  }
  function fromDayNum(n) { return new Date(n * 864e5); }
  function fmtDay(n) { var d = fromDayNum(n); return MON[d.getUTCMonth()] + " " + d.getUTCDate(); }

  function todayInNewYork() {
    // ?sw_today=2027-06-16 previews another day. Nothing else reads it.
    var forced = new URLSearchParams(window.location.search).get("sw_today");
    if (forced && /^\d{4}-\d{2}-\d{2}$/.test(forced)) return dayNum(forced);
    var parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit"
    }).format(new Date());
    return dayNum(parts);
  }

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  // "3 Half-Day" -> "3 half-days", "1 Day" -> "1 day"
  function durationText(x) {
    var m = String(x || "").match(/^(\d+)\s+(.*)$/);
    if (!m) return esc(x || "");
    var n = +m[1], unit = m[2].toLowerCase();
    return esc(n + " " + unit + (n === 1 ? "" : "s"));
  }

  function drawListing(root) {
    var dataEl = root.getElementById("sw-data");
    if (!dataEl) return;
    var data = JSON.parse(dataEl.textContent);
    var $ = function (id) { return root.getElementById(id); };
    var today = todayInNewYork();

    // Each card's state today
    var cards = data.cards.map(function (c) {
      c.days = (c.dates || []).map(dayNum);
      c.instructors = c.instructors || [];
      c.tags = c.tags || [];
      if (c.format === "independent") { c.state = "anytime"; return c; }
      if (!c.days.length) { c.state = "tba"; return c; }
      var first = c.days[0], last = c.days[c.days.length - 1];
      if (today > last + POSTING_DAYS) c.state = "anytime";
      else if (today > last) c.state = "ended";
      else if (today >= first) c.state = "running";
      else c.state = "upcoming";
      return c;
    });

    var counts = {};
    cards.forEach(function (c) {
      c.instructors.forEach(function (n) { counts[n] = (counts[n] || 0) + 1; });
    });

    // The filters live in the page address, so a filtered view can be linked
    var params = new URLSearchParams(window.location.search);
    var S = {
      q: params.get("q") || "",
      instructor: params.get("instructor") || "",
      tags: (params.get("topics") || "").split(",").filter(Boolean)
    };
    if (S.instructor && !counts[S.instructor]) S.instructor = "";

    function writeUrl() {
      var p = new URLSearchParams(window.location.search);
      p.delete("q"); p.delete("instructor"); p.delete("topics");
      if (S.q) p.set("q", S.q);
      if (S.instructor) p.set("instructor", S.instructor);
      if (S.tags.length) p.set("topics", S.tags.join(","));
      var s = p.toString();
      try {
        history.replaceState(history.state, "", window.location.pathname + (s ? "?" + s : "") + window.location.hash);
      } catch (e) { /* a sandboxed preview may refuse; the filters still work */ }
    }

    function hasTag(c, t) { return t === "Free" ? c.free : c.tags.indexOf(t) !== -1; }

    function matches(c) {
      if (S.instructor && c.instructors.indexOf(S.instructor) === -1) return false;
      if (S.q) {
        var hay = (c.title + " " + c.instructors.join(" ") + " " + c.tags.join(" ")).toLowerCase();
        var words = S.q.toLowerCase().split(/\s+/);
        for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) === -1) return false;
      }
      // Any of the picked tags within a group, and every group with a pick
      for (var g = 0; g < data.groups.length; g++) {
        var picked = data.groups[g].tags.filter(function (t) { return S.tags.indexOf(t) !== -1; });
        if (picked.length && !picked.some(function (t) { return hasTag(c, t); })) return false;
      }
      return true;
    }

    function whoHtml(c) {
      return c.instructors.map(function (n) {
        return '<button class="who" data-who="' + esc(n) + '" title="Show workshops by ' + esc(n) + '">' + esc(n) + "</button>";
      }).join(" &amp; ");
    }
    function titleHtml(c) {
      return "<h3>" + (c["new"] ? '<span class="badge new">New</span>' : "") +
        '<a href="' + esc(c.link || "#") + '">' + esc(c.title) + "</a></h3>";
    }
    // Free sits in the card's top-right corner: at the end of the format line
    // on a live card, and at the end of the title row on a recorded one.
    function freeHtml(c) { return c.free ? '<span class="badge free">Free</span>' : ""; }
    function tagsHtml(c) {
      if (!c.tags.length) return "";
      return '<div class="tags">' + c.tags.map(function (t) {
        return '<button class="chip" data-tag="' + esc(t) + '" aria-pressed="' + (S.tags.indexOf(t) !== -1) + '">' + esc(t) + "</button>";
      }).join("") + "</div>";
    }
    function comboHtml(c) {
      if (!c.combo) return "";
      return '<div class="combo" title="Save 20% when you register for this together with another workshop. ' +
        'The combo options are on its page.">Combo pricing available</div>';
    }
    function availHtml(c) {
      if (c.state === "anytime") return '<div class="avail now"><span class="ico">✓</span>Watch now</div>';
      var last = c.days[c.days.length - 1];
      if (c.state === "ended") {
        return '<div class="avail later"><span class="ico">◷</span>Live sessions ended ' + fmtDay(last) +
          " · full recordings by " + fmtDay(last + POSTING_DAYS) + "</div>";
      }
      if (c.first_run) {
        return '<div class="avail later"><span class="ico">◷</span>New workshop: recordings posted ' +
          (c.days.length ? "by " + fmtDay(last + POSTING_DAYS) : "within 48 hours of the last session") + "</div>";
      }
      return '<div class="avail now"><span class="ico">✓</span>Recordings from the last run available now</div>';
    }

    function liveCard(c) {
      var flipped = c.format === "flipped", ended = c.state === "ended";
      // The date block takes the topic's colour, as the recorded cards do, so
      // a workshop keeps its colour before and after its run.
      var topic = topicOf(c);
      var when;
      if (c.days.length) {
        var f = fromDayNum(c.days[0]), l = fromDayNum(c.days[c.days.length - 1]);
        var mon = f.getUTCMonth() === l.getUTCMonth() ? MON[f.getUTCMonth()] : MON[f.getUTCMonth()] + "–" + MON[l.getUTCMonth()];
        var days = c.days.length === 1 ? f.getUTCDate() : f.getUTCDate() + "–" + l.getUTCDate();
        var thisYear = fromDayNum(today).getUTCFullYear();
        var yr = f.getUTCFullYear() !== thisYear ? '<span class="yr">' + f.getUTCFullYear() + "</span>" : "";
        when = '<span class="mon">' + mon + '</span><span class="days">' + days + "</span>" + yr;
      } else {
        when = '<span class="mon">Dates</span><span class="yr">to be announced</span>';
      }
      if (topic) {
        when += '<span class="wtopic"><svg viewBox="0 0 24 24" aria-hidden="true">' + topic.icon + "</svg>" + esc(topic.label) + "</span>";
      }
      var sessions = c.days.map(function (n) {
        var d = fromDayNum(n), t = DOW[d.getUTCDay()] + ", " + fmtDay(n);
        return "<span>" + (n < today ? "<s>" + t + "</s>" : t) + "</span>";
      }).join("");
      var meta = [durationText(c.duration)];
      if (c.time) meta.push(esc(c.time));
      if (c.instructors.length) meta.push(whoHtml(c));
      return '<article class="card live' + (flipped ? " flipped" : "") + (ended ? " ended" : "") + (topic ? " t-" + topic.key : "") + '">' +
        '<div class="when" aria-hidden="true">' + when + "</div>" +
        '<div class="body">' +
        '<div class="fmt"><span class="kind">' + esc(ended ? "Finished" : c.how) + "</span>" +
        (c.state === "running" ? '<span class="pill">In progress</span>' : "") + freeHtml(c) + "</div>" +
        titleHtml(c) +
        '<div class="meta">' + meta.join(" · ") + "</div>" +
        (ended || !sessions ? "" : '<div class="sessions">' + sessions + "</div>") +
        availHtml(c) + comboHtml(c) + tagsHtml(c) +
        "</div></article>";
    }

    // Each recorded workshop takes the colour and icon of its main topic: the
    // first of its tags in this list, so a specific topic wins over a general
    // one (Dyadic over Design, anything over Analysis). The colours are in
    // templates/listing.html.
    var TOPICS = [
      { tag: "Funding", key: "funding", label: "Funding",
        icon: '<rect x="5" y="3" width="14" height="18" rx="1.5"/><path d="M8.5 8h7M8.5 12h7M8.5 16h4"/>' },
      { tag: "Trials", key: "design", label: "Design & Trials",
        icon: '<circle cx="4.5" cy="12" r="1.6"/><path d="M6 12h3.5l4.5-5h6M9.5 12l4.5 5h6"/>' },
      { tag: "Dyadic", key: "dyadic", label: "Dyadic",
        icon: '<circle cx="9" cy="12" r="5.5"/><circle cx="15" cy="12" r="5.5"/>' },
      { tag: "Design", key: "design", label: "Design & Trials",
        icon: '<circle cx="4.5" cy="12" r="1.6"/><path d="M6 12h3.5l4.5-5h6M9.5 12l4.5 5h6"/>' },
      { tag: "Measurement", key: "measurement", label: "Measurement",
        icon: '<path d="M3.5 17a8.5 8.5 0 0 1 17 0"/><path d="M12 17l4.5-5.5"/><circle cx="12" cy="17" r="1.2"/>' },
      { tag: "Programming", key: "programming", label: "Programming",
        icon: '<path d="M8 7l-5 5 5 5M16 7l5 5-5 5M13.5 5l-3 14"/>' },
      { tag: "Longitudinal", key: "longitudinal", label: "Longitudinal",
        icon: '<path d="M3 20h18M3 20V4"/><path d="M6 15.5l4-4.5 3.5 3 6-7"/>' },
      { tag: "Analysis", key: "analysis", label: "Analysis",
        icon: '<path d="M3.5 19.5L20.5 5"/><circle cx="6.5" cy="15" r="1.4"/><circle cx="10.5" cy="13.5" r="1.4"/><circle cx="14" cy="9.5" r="1.4"/><circle cx="17.5" cy="10" r="1.4"/>' }
    ];
    function topicOf(c) {
      for (var i = 0; i < TOPICS.length; i++) if (c.tags.indexOf(TOPICS[i].tag) !== -1) return TOPICS[i];
      return null;
    }
    function topicHtml(t) {
      if (!t) return "";
      return '<div class="topic"><svg viewBox="0 0 24 24" aria-hidden="true">' + t.icon + "</svg>" +
        "<span>" + esc(t.label) + "</span></div>";
    }

    // "Watch now" would be the same on every card here, and the section's
    // heading already says it, so a recorded card does not repeat it.
    function anyCard(c) {
      var t = topicOf(c);
      var meta = [durationText(c.duration)];
      if (c.instructors.length) meta.push(whoHtml(c));
      return '<article class="card anytime' + (t ? " t-" + t.key : "") + '">' + topicHtml(t) +
        '<div class="head">' + titleHtml(c) + freeHtml(c) + "</div>" +
        '<div class="meta">' + meta.join(" · ") + "</div>" +
        comboHtml(c) + tagsHtml(c) + "</article>";
    }

    var ORDER = { running: 0, upcoming: 1, tba: 2, ended: 3 };
    var live = cards.filter(function (c) { return c.state !== "anytime"; }).sort(function (a, b) {
      return ORDER[a.state] - ORDER[b.state] || (a.days[0] || 0) - (b.days[0] || 0);
    });
    var anytime = cards.filter(function (c) { return c.state === "anytime"; }).sort(function (a, b) {
      return a.title.localeCompare(b.title, "en", { sensitivity: "base" });
    });

    // The status line counts from the data, so it is right in any month
    var upN = live.filter(function (c) { return c.state !== "ended"; }).length;
    var nowN = cards.filter(function (c) { return c.state === "anytime" || !c.first_run; }).length;
    $("status").innerHTML =
      (upN ? '<span class="s live"><span class="dot"></span>' + upN + " workshop" + (upN > 1 ? "s" : "") + " coming up on Zoom</span>"
           : '<span class="s none">No live sessions scheduled right now</span>') +
      '<span class="s now">✓ ' + (nowN === cards.length ? "All " + nowN : nowN) + " available to watch now</span>";

    var lastName = function (n) { var p = n.split(" "); return p[p.length - 1]; };
    var names = Object.keys(counts).sort(function (a, b) {
      return lastName(a).localeCompare(lastName(b)) || a.localeCompare(b);
    });

    $("groups").innerHTML = data.groups.map(function (g) {
      return '<div class="group" role="group" aria-label="' + esc(g.label) + '"><span class="group-label">' + esc(g.label) + "</span>" +
        g.tags.map(function (t) { return '<button class="chip" data-tag="' + esc(t) + '">' + esc(t) + "</button>"; }).join("") + "</div>";
    }).join("");
    $("q").value = S.q;

    function render() {
      var L = live.filter(matches), A = anytime.filter(matches);
      $("liveList").innerHTML = L.map(liveCard).join("");
      $("grid").innerHTML = A.map(anyCard).join("");
      $("liveSection").hidden = !L.length;
      $("anySection").hidden = !A.length;
      $("empty").hidden = L.length + A.length > 0;

      var filtering = S.q || S.instructor || S.tags.length;
      $("count").textContent = filtering
        ? "Showing " + (L.length + A.length) + " of " + cards.length + " workshops"
        : cards.length + " workshops";
      $("clear").hidden = !filtering;
      $("filtersToggle").textContent = "Topics & software" + (S.tags.length ? " (" + S.tags.length + ")" : "");
      $("instructor").innerHTML = '<option value="">All instructors</option>' + names.map(function (n) {
        return '<option value="' + esc(n) + '"' + (n === S.instructor ? " selected" : "") + ">" + esc(n) + " (" + counts[n] + ")</option>";
      }).join("");
      root.querySelectorAll("#groups .chip").forEach(function (b) {
        b.setAttribute("aria-pressed", S.tags.indexOf(b.getAttribute("data-tag")) !== -1);
      });
      writeUrl();
    }

    function toggleTag(t) {
      var i = S.tags.indexOf(t);
      if (i === -1) S.tags.push(t); else S.tags.splice(i, 1);
    }
    function clearAll() { S.q = ""; S.instructor = ""; S.tags = []; $("q").value = ""; render(); }

    $("q").addEventListener("input", function (e) { S.q = e.target.value.trim(); render(); });
    $("instructor").addEventListener("change", function (e) { S.instructor = e.target.value; render(); });
    $("filtersToggle").addEventListener("click", function () {
      var open = $("groups").classList.toggle("open");
      $("filtersToggle").setAttribute("aria-expanded", open);
    });
    $("clear").addEventListener("click", clearAll);
    $("clear2").addEventListener("click", clearAll);
    root.addEventListener("click", function (e) {
      var tag = e.target.closest("[data-tag]");
      if (tag) { toggleTag(tag.getAttribute("data-tag")); render(); return; }
      var who = e.target.closest("[data-who]");
      if (who) { S.instructor = who.getAttribute("data-who"); render(); }
    });

    render();
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
