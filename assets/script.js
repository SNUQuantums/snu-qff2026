// Qiskit Fall Fest 2026 @ SNU - shared site behavior
// Language toggle (persisted), color theme switcher (persisted), mobile nav,
// FAQ accordion is native <details>.

(function () {
  var STORAGE_KEY = "qff-lang";
  var THEME_KEY = "qff-theme";
  var THEMES = ["original", "ibm", "snu", "neon"];
  var html = document.documentElement;

  function applyTheme(theme) {
    if (THEMES.indexOf(theme) === -1) theme = "original";
    html.setAttribute("data-theme", theme);
    document.querySelectorAll(".theme-dot").forEach(function (dot) {
      var isActive = dot.dataset.themeOption === theme;
      dot.setAttribute("data-active", isActive ? "true" : "false");
      dot.setAttribute("aria-pressed", isActive ? "true" : "false");
    });
  }

  function initTheme() {
    var saved = localStorage.getItem(THEME_KEY) || "original";
    applyTheme(saved);
  }

  function bindThemeSwitch() {
    document.querySelectorAll(".theme-dot").forEach(function (dot) {
      dot.addEventListener("click", function () {
        var theme = dot.dataset.themeOption;
        localStorage.setItem(THEME_KEY, theme);
        applyTheme(theme);
      });
    });
  }

  function applyLang(lang) {
    html.setAttribute("data-lang", lang);
    document.querySelectorAll(".lang-toggle").forEach(function (btn) {
      if (btn.dataset.disabled === "true") {
        btn.textContent = "EN · coming soon";
        return;
      }
      btn.textContent = lang === "kr" ? "KR / EN" : "EN / KR";
    });
  }

  function initLang() {
    var saved = localStorage.getItem(STORAGE_KEY) || "kr";
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
        localStorage.setItem(STORAGE_KEY, next);
        applyLang(next);
      });
    });
  }

  function bindMobileNav() {
    var menuBtn = document.querySelector(".menu-btn");
    var nav = document.querySelector("nav.primary-nav ul");
    if (!menuBtn || !nav) return;
    menuBtn.addEventListener("click", function () {
      var open = nav.getAttribute("data-open") === "true";
      nav.setAttribute("data-open", open ? "false" : "true");
      nav.style.display = open ? "none" : "flex";
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
    initTheme();
    bindThemeSwitch();
    bindMobileNav();
    markActiveNav();
  });
})();
