-- Bring a Supabase project created from the first version of supabase-schema.sql
-- up to date. Run this once in the SQL editor, then run supabase-schema.sql
-- again: every statement there is safe to repeat, and it replaces
-- submit_solution and finish_submission and adds team_submissions.
--
-- The first version ranked a different score, which cannot be compared with
-- 1-F, so the leaderboard starts over. Submissions are kept.

alter table public.qff_leaderboard add column if not exists score_key double precision;
alter table public.qff_leaderboard alter column n_ticks drop not null;
delete from public.qff_leaderboard;
alter table public.qff_leaderboard alter column score_key set not null;
