-- Test mode (*_test objects): rank 1-F at three significant figures, as the real tables do
-- since supabase-migrate-v11-three-digits.sql. Run once in the Supabase SQL editor. Safe to rerun.

create or replace function public.finish_submission_test(
  p_submission_id uuid,
  p_worker_id text,
  p_status text,
  p_score_a double precision default null,
  p_p_acc double precision default null,
  p_n_2q integer default null,
  p_n_ticks integer default null,
  p_public_message text default null,
  p_internal_error text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_submission public.qff_test_submissions%rowtype;
begin
  if p_status not in ('scored', 'invalid', 'error') then
    raise exception 'Invalid terminal status';
  end if;
  if p_status = 'scored' and (
    p_score_a is null or p_n_2q is null
    or p_score_a = 'NaN'::double precision
    or abs(p_score_a) = 'Infinity'::double precision
  ) then
    raise exception 'A scored submission requires a finite score and a gate count';
  end if;

  update public.qff_test_submissions
  set status = p_status,
      score_a = case when p_status = 'scored' then p_score_a else null end,
      p_acc = p_p_acc,
      n_2q = p_n_2q,
      n_ticks = p_n_ticks,
      public_message = left(p_public_message, 500),
      internal_error = left(p_internal_error, 4000),
      scored_at = now(),
      lease_expires_at = null
  where id = p_submission_id
    and status = 'processing'
    and worker_id = p_worker_id
  returning * into v_submission;

  if v_submission.id is null then
    raise exception 'Submission lease is missing or belongs to another worker';
  end if;

  if p_status = 'scored' then
    insert into public.qff_test_leaderboard (
      team_id, submission_id, team_name, score_a, score_key, n_2q, n_ticks, p_acc, submitted_at
    )
    select s.team_id, s.id, t.team_name, s.score_a,
           -- three significant figures: 0.0025971 -> 0.00260
           to_char(s.score_a, '9.99EEEE')::double precision,
           s.n_2q, s.n_ticks, s.p_acc, s.submitted_at
    from public.qff_test_submissions as s
    join public.qff_test_teams as t on t.id = s.team_id
    where s.id = v_submission.id
    on conflict (team_id) do update
      set submission_id = excluded.submission_id,
          team_name = excluded.team_name,
          score_a = excluded.score_a,
          score_key = excluded.score_key,
          n_2q = excluded.n_2q,
          n_ticks = excluded.n_ticks,
          p_acc = excluded.p_acc,
          submitted_at = excluded.submitted_at,
          updated_at = now()
      where (excluded.score_key, excluded.n_2q, excluded.submitted_at)
          < (qff_test_leaderboard.score_key, qff_test_leaderboard.n_2q, qff_test_leaderboard.submitted_at);
  end if;
end;
$$;

-- Rebuild the test board: a team's best can change at three figures.
delete from public.qff_test_leaderboard;
insert into public.qff_test_leaderboard (
  team_id, submission_id, team_name, score_a, score_key, n_2q, n_ticks, p_acc, submitted_at
)
select distinct on (s.team_id)
       s.team_id, s.id, t.team_name, s.score_a,
       to_char(s.score_a, '9.99EEEE')::double precision,
       s.n_2q, s.n_ticks, s.p_acc, s.submitted_at
from public.qff_test_submissions as s
join public.qff_test_teams as t on t.id = s.team_id
where s.status = 'scored' and s.score_a is not null and s.n_2q is not null
order by s.team_id, to_char(s.score_a, '9.99EEEE')::double precision, s.n_2q, s.submitted_at;

select team_name, score_key, n_2q, p_acc, submitted_at
from public.qff_test_leaderboard
order by score_key, n_2q, submitted_at;
