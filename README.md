# Qiskit Fall Fest 2026 @ SNU

Static, no-build demo site for Qiskit Fall Fest 2026, hosted by SQRT (SNU Quantum Research Team), plus a QASM submission + leaderboard flow for the Track A hackathon backed by Supabase.

No framework, no bundler, no `npm install` — every page is plain HTML/CSS/JS, and the only external dependencies (Google Fonts, the Supabase JS client) are loaded via `<link>`/`<script>` tags from a CDN.

## Structure

```
.
├── index.html          Home
├── about.html          About SQRT / Qiskit Fall Fest
├── schedule.html       3-day schedule
├── speakers.html       Speakers (IBM / SNU faculty / SQRT)
├── hackathon.html      Track A + Track B details
├── posters.html        Poster Session
├── faq.html
├── register.html       Sign-up router (Track A / Track B / Poster / Day 1)
├── submit.html         Track A: submit a QASM circuit (writes to Supabase)
├── leaderboard.html    Track A: live standings (reads from Supabase)
├── assets/
│   ├── style.css              design system, incl. 4 switchable color themes
│   ├── script.js               language toggle, theme switcher, mobile nav
│   ├── supabase-config.js      YOUR project URL + anon key go here
│   └── supabase.js             thin client wrapper (submitEntry / fetchLeaderboard)
├── supabase-schema.sql  run once in the Supabase SQL editor
└── .github/workflows/deploy-pages.yml   auto-deploy to GitHub Pages
```

## Previewing locally

Opening `index.html` directly (`file://`) mostly works, but `submit.html` / `leaderboard.html` call `fetch` under the hood and some browsers restrict that from `file://`. Serve the folder instead:

```
python3 -m http.server 8000
# then open http://localhost:8000
```

or `npx serve .` if Node is installed.

## Supabase setup (for submit.html / leaderboard.html)

1. Create a free project at [supabase.com](https://supabase.com).
2. Open the SQL Editor and run `supabase-schema.sql` — creates the `submissions` table and Row Level Security policies (public can insert + read, nothing else).
3. Project Settings → API → copy the **Project URL** and the **anon public** key (not `service_role`) into `assets/supabase-config.js`.
4. A separate scoring backend (not part of this repo) should connect with the `service_role` key, poll `submissions` for `status = 'pending'`, run the QASM circuit, and write back `status` (`scored`/`error`) and `score`.

Until step 3 is done, `submit.html` and `leaderboard.html` will show a clear "not connected yet" message instead of failing silently — that's expected on a fresh clone.

## Deploying to GitHub Pages

`index.html` sits at the repo root and every internal link is relative (`about.html`, `assets/style.css`, no leading slash), so this works correctly whether it's served from a root domain or from a `/repo-name/` subpath.

**Option 1 — Settings only (simplest)**
Repo → Settings → Pages → Source: *Deploy from a branch* → Branch: `main`, folder: `/ (root)` → Save. Live at `https://<org-or-user>.github.io/<repo>/` within a minute or two.

**Option 2 — GitHub Actions (auto-deploys every push)**
A workflow is already included at `.github/workflows/deploy-pages.yml`. Enable it once: Settings → Pages → Source: *GitHub Actions*. Every push to `main` redeploys automatically — no need to touch branch/folder settings again.

Either option is fine; Actions is nicer if multiple people will push updates during the event and you don't want to think about it.

**Custom domain (optional):** if SQRT ever points a real domain at this, add a `CNAME` file at the repo root containing just the domain name, and configure the DNS record per GitHub's docs.

## Embedding as a subpage of the existing Google Site

Once deployed, add a new page in Google Sites (e.g. `sites.google.com/view/sqrt-quantum/qiskit-fall-fest-2026`) and either:
- link out to the GitHub Pages URL, or
- use Insert → Embed → "By URL" to iframe it inline.

See prior discussion in chat for the tradeoffs between the two.

## Notes

- `.nojekyll` disables GitHub Pages' default Jekyll processing (this is a plain static site, not a Jekyll one).
- 4 color themes (original / IBM Quantum Native / SNU Heritage / Quantum Circuit Neon) and the KR/EN language toggle are pure CSS custom properties + vanilla JS, switchable from the header on every page.
- No LICENSE file is included — add one if SQRT wants to formalize reuse terms; otherwise this defaults to all-rights-reserved, which is typically fine for an internal event site.
