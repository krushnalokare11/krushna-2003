/* ============================================================
   [YOUR NAME] — academic portfolio
   Three small features. Nothing here needs editing.

   1. Mobile menu open/close
   2. Highlight the nav link for the section you're reading
   3. Filter the publication list by type
   ============================================================ */

(function () {
  "use strict";

  /* ---------- 1. mobile menu ---------- */
  var toggle = document.getElementById("navToggle");
  var nav = document.getElementById("siteNav");

  if (toggle && nav) {
    toggle.addEventListener("click", function () {
      var open = nav.classList.toggle("open");
      toggle.setAttribute("aria-expanded", String(open));
    });

    // close after tapping a link, so the page isn't hidden behind the menu
    nav.addEventListener("click", function (e) {
      if (e.target.tagName === "A") {
        nav.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
      }
    });

    // close on Escape
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && nav.classList.contains("open")) {
        nav.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
        toggle.focus();
      }
    });
  }

  /* ---------- 2. active section in the nav ----------
     Smooth scrolling itself is handled by CSS (scroll-behavior:smooth),
     so this only tracks which section is on screen. */
  var links = Array.prototype.slice.call(document.querySelectorAll('.site-nav a[href^="#"]'));
  var targets = links
    .map(function (a) { return document.querySelector(a.getAttribute("href")); })
    .filter(Boolean);

  if ("IntersectionObserver" in window && targets.length) {
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var id = entry.target.id;
        links.forEach(function (a) {
          var match = a.getAttribute("href") === "#" + id;
          a.classList.toggle("active", match);
          if (match) { a.setAttribute("aria-current", "true"); }
          else { a.removeAttribute("aria-current"); }
        });
      });
    }, { rootMargin: "-70px 0px -65% 0px", threshold: 0 });

    targets.forEach(function (t) { observer.observe(t); });
  }

  /* ---------- 3. publication filter ---------- */
  var filterBar = document.querySelector(".pub-filter");
  var pubs = Array.prototype.slice.call(document.querySelectorAll(".pub"));
  var empty = document.getElementById("pubEmpty");

  if (filterBar && pubs.length) {
    filterBar.addEventListener("click", function (e) {
      var btn = e.target.closest("button[data-filter]");
      if (!btn) return;

      var kind = btn.dataset.filter;
      var shown = 0;

      filterBar.querySelectorAll("button").forEach(function (b) {
        b.setAttribute("aria-selected", String(b === btn));
      });

      pubs.forEach(function (li) {
        var show = kind === "all" || li.dataset.kind === kind;
        li.hidden = !show;
        if (show) shown++;
      });

      if (empty) empty.hidden = shown !== 0;
    });
  }

  /* ---------- footer year ---------- */
  var year = document.getElementById("year");
  if (year) year.textContent = new Date().getFullYear();
})();
