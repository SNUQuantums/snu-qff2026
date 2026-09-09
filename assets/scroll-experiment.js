// Home-only chapter transition test; native scrolling and focus remain available.
(function () {
  if (!document.body.classList.contains('reference-home')) return;
  var reduced = matchMedia('(prefers-reduced-motion: reduce)');
  var sections = Array.from(document.querySelectorAll('main > section:not(.reference-hero), .site-footer'));
  var targets = sections.map(function (section) {
    var content = section.firstElementChild;
    content.classList.add('chapter-content');
    return { section:section, content:content };
  });
  document.body.classList.add('chapter-mode');
  document.documentElement.classList.add('home-chapters');
  var pending = false;
  function render() {
    pending = false;
    var height = innerHeight;
    targets.forEach(function (item) {
      var rect = item.section.getBoundingClientRect();
      // A short, distinct entrance; long sections remain fully readable throughout.
      var enter = Math.max(0, Math.min(1, (height * .92 - rect.top) / (height * .38)));
      var leave = Math.max(0, Math.min(1, rect.bottom / (height * .25)));
      var progress = reduced.matches ? 1 : Math.min(enter, leave);
      var eased = progress * progress * (3 - 2 * progress);
      item.content.style.setProperty('--chapter-opacity', String(eased));
      item.content.style.setProperty('--chapter-shift', ((1 - eased) * 48) + 'px');
      item.content.style.setProperty('--chapter-scale', String(.965 + eased * .035));
    });
  }
  function queue() { if (!pending) { pending = true; requestAnimationFrame(render); } }
  addEventListener('scroll', queue, {passive:true});
  addEventListener('resize', queue);
  reduced.addEventListener('change', queue);
  render();
})();
