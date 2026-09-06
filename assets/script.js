// Qiskit Fall Fest 2026 @ SNU - shared site behavior
// Language toggle (persisted), mobile nav, FAQ accordion is native <details>.

(function () {
  var STORAGE_KEY = "qff-lang";
  var html = document.documentElement;

  function applyLang(lang) {
    lang = lang === "en" ? "en" : "kr";
    html.setAttribute("data-lang", lang);
    html.setAttribute("lang", lang === "kr" ? "ko" : "en");
    document.querySelectorAll(".lang-toggle").forEach(function (btn) {
      if (btn.dataset.disabled === "true") {
        btn.textContent = "EN · coming soon";
        return;
      }
      btn.textContent = lang === "kr" ? "KR / EN" : "EN / KR";
    });
  }

  function initLang() {
    var saved = "kr";
    try { saved = localStorage.getItem(STORAGE_KEY) || "kr"; } catch (e) {}
    applyLang(saved);
  }

  function bindLangToggle() {
    document.querySelectorAll(".lang-toggle").forEach(function (btn) {
      btn.addEventListener("click", function () {
        if (btn.dataset.disabled === "true") {
          btn.classList.add("shake");
          setTimeout(function () { btn.classList.remove("shake"); }, 400);
          return;
        }
        var current = html.getAttribute("data-lang") || "kr";
        var next = current === "kr" ? "en" : "kr";
        try { localStorage.setItem(STORAGE_KEY, next); } catch (e) {}
        applyLang(next);
      });
    });
  }

  function bindMobileNav() {
    var menuBtn = document.querySelector(".menu-btn");
    var nav = document.querySelector("nav.primary-nav ul");
    if (!menuBtn || !nav) return;
    nav.id = "primary-menu";
    menuBtn.setAttribute("aria-controls", nav.id);
    menuBtn.setAttribute("aria-expanded", "false");
    function setOpen(open) {
      nav.setAttribute("data-open", String(open));
      menuBtn.setAttribute("aria-expanded", String(open));
    }
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && nav.getAttribute("data-open") === "true") {
        setOpen(false); menuBtn.focus();
      }
    });
    window.addEventListener("resize", function () {
      if (window.innerWidth > 1250) setOpen(false);
    });
    nav.addEventListener("click", function(e) { if (e.target.closest("a")) setOpen(false); });
    menuBtn.addEventListener("click", function () {
      var open = nav.getAttribute("data-open") === "true";
      setOpen(!open);
    });
  }

  function markActiveNav() {
    var path = window.location.pathname.split("/").pop() || "index.html";
    document.querySelectorAll("nav.primary-nav a[data-nav]").forEach(function (a) {
      if (a.getAttribute("data-nav") === path) {
        a.setAttribute("aria-current", "page");
      }
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    initLang();
    bindLangToggle();
    bindMobileNav();
    markActiveNav();
  });
})();
