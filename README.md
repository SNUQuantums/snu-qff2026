# Qiskit Fall Fest 2026 @ SNU

Static, no-build demo site for Qiskit Fall Fest 2026, hosted by SQRT (SNU Quantum Research Team), plus a circuit submission + leaderboard flow for the hackathon backed by Supabase.

No framework, no bundler, no `npm install` — every page is plain HTML/CSS/JS, and the only external dependencies (Google Fonts, the Supabase JS client) are loaded via `<link>`/`<script>` tags from a CDN.

## Structure

```
.
├── index.html          Home
├── about.html          About SQRT / Qiskit Fall Fest (unlinked)
├── schedule.html       Pre-festival online sessions and the 3-day schedule, incl. speakers
├── ideathon.html       Ideathon topic, templates, reference cases, participant cards
├── ideathon-cases.html Three reference cases of quantum technology in use
├── hackathon.html      Problem (revealed on release), team registration link, circuit
│                       submission, paged leaderboard, per-team submission history
├── register.html       Four registration overlays: Ideathon, Hackathon, speaker RSVP,
│                       poster abstract (the last two embed Google Forms)
├── faq.html
├── assets/
│   ├── style.css              design system
│   ├── event.css              Ideathon / Hackathon / Register components
│   ├── script.js              language toggle, mobile nav
│   ├── supabase-config.js     project URL + public/anon key go here
│   ├── supabase.js            guarded RPC wrapper (registration, submission, leaderboard)
│   └── downloads/             Ideathon pitch deck and lean canvas templates
├── supabase-schema.sql  private queue, team auth, worker RPCs, leaderboard, registration
└── .github/workflows/deploy-pages.yml   auto-deploy to GitHub Pages
```

## Previewing locally

Opening `index.html` directly (`file://`) mostly works, but `hackathon.html`, `ideathon.html`, and `register.html` call `fetch` under the hood and some browsers restrict that from `file://`. Serve the folder instead:

```
python3 -m http.server 8000
# then open http://localhost:8000
```

or `npx serve .` if Node is installed.

For a private end-to-end test with a localhost Supabase database and the real
scoring worker, follow [LOCAL_TESTING.md](LOCAL_TESTING.md). Nothing is pushed
to GitHub or a hosted Supabase project in that workflow.

## Supabase setup (for hackathon.html / ideathon.html / register.html)

1. Create a free project at [supabase.com](https://supabase.com).
2. Open the SQL Editor and run `supabase-schema.sql`. (A project set up from the first version of this file runs `supabase-migrate-v2.sql` first, then `supabase-schema.sql` again.) It creates private team/submission tables, a public sanitized leaderboard, and the guarded RPCs used by the browser and worker.
3. Project Settings → API → copy the **Project URL** and **public/anon** key (never the service-role key) into `assets/supabase-config.js`.
4. Create teams in the SQL Editor with `select public.admin_upsert_team('Team name', 'random-password-at-least-8-chars');`.
5. On the private scoring machine, configure and run the worker in the `snu-qff/worker` directory. Its service-role key belongs only in the worker's local `.env` file.

Event timing (registration opening, problem release, deadlines) and the hackathon problem link live in `qff_settings`, never in this repository; `event_status()` reveals the link only after the release time. Ideathon participants and hackathon teams register themselves through `register_ideathon(...)` and `register_hackathon_team(...)`; contact details stay in private tables. See `supabase-migrate-v4-registration.sql` for the organizer notes.

The browser can list active team display names for the submission dropdown, execute
`submit_solution(...)`, read its own team's results through `team_submissions(...)`
(which checks the team password and returns the judge's public message, never the
internal error), and read `qff_leaderboard`. It never reads submitted circuits,
password hashes, or internal judge diagnostics. Team/password validation happens inside the
database function before a private queue row is created.

Until step 3 is done, the Hackathon, Ideathon, and Register pages will show a clear "not connected yet" message instead of failing silently — that's expected on a fresh clone.

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
