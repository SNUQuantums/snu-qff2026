-- Qiskit Fall Fest 2026 @ SNU - Supabase schema for hackathon submissions
--
-- Paste this into your Supabase project's SQL editor (Project -> SQL Editor
-- -> New query) and run it once. This creates the table the frontend
-- (submit.html / leaderboard.html) reads from and writes to, plus the Row
-- Level Security (RLS) policies that let the public anon key insert new
-- submissions and read the leaderboard, without allowing it to edit scores
-- or read contact emails back out.
--
-- Your separate scoring backend should connect with the service_role key
-- (never expose that key in frontend code) so it can bypass RLS, read
-- pending submissions, run the QASM, and write back status/score.

create extension if not exists "pgcrypto";

create table if not exists submissions (
  id uuid primary key default gen_random_uuid(),
  team_name text not null,
  contact_email text,
  qasm text not null,
  status text not null default 'pending' check (status in ('pending', 'scored', 'error')),
  score numeric,
  notes text,
  submitted_at timestamptz not null default now()
);

alter table submissions enable row level security;

-- Anyone (the anon key used by submit.html) can insert a new submission.
create policy "public can insert submissions"
  on submissions for insert
  to anon
  with check (true);

-- Anyone (the anon key used by leaderboard.html) can read rows.
-- NOTE: this also exposes contact_email to anyone querying the table
-- directly via the anon key. If that's a concern, either:
--   (a) have leaderboard.html select only the columns it needs (it already
--       does: team_name, score, status, submitted_at - contact_email is
--       never requested by the frontend), or
--   (b) create a `public_leaderboard` view that excludes contact_email and
--       point fetchLeaderboard() at that view instead of the base table.
create policy "public can read submissions"
  on submissions for select
  to anon
  using (true);

-- No update/delete policy is created for anon - only your scoring backend
-- (using the service_role key, which bypasses RLS entirely) should be able
-- to change status/score.
