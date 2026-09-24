-- Qiskit Fall Fest 2026 @ SNU — secure submission queue and leaderboard
--
-- Run this file once in a fresh Supabase project's SQL editor. It deliberately
-- uses qff_* table names so it can coexist with the earlier demo `submissions`
-- table without deleting data.
--
-- Security model:
--   * Browser users can list active team names, execute submit_solution(...),
--     and read qff_leaderboard.
--   * Browser users cannot read qff_teams or qff_submissions directly.
--   * The local worker uses the service-role key to claim and finish jobs.
--   * Team passwords are stored only as pgcrypto hashes.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.qff_teams (
  id uuid primary key default gen_random_uuid(),
  team_name text not null check (char_length(trim(team_name)) between 1 and 80),
  password_hash text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists qff_teams_name_ci_idx
  on public.qff_teams ((lower(trim(team_name))));

create table if not exists public.qff_submissions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.qff_teams(id),
  qasm text not null check (octet_length(qasm) between 1 and 200000),
  data_qubits smallint[] not null,
  course smallint not null default 3 check (course = 3),
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'scored', 'invalid', 'error')),
  submitted_at timestamptz not null default now(),
  claimed_at timestamptz,
  lease_expires_at timestamptz,
  worker_id text,
  attempt_count integer not null default 0,
  scored_at timestamptz,
  score_a double precision,
  p_acc double precision,
  n_2q integer,
  n_ticks integer,
  public_message text,
  internal_error text
);

create index if not exists qff_submissions_queue_idx
  on public.qff_submissions (status, submitted_at);
create index if not exists qff_submissions_team_idx
  on public.qff_submissions (team_id, submitted_at desc);

-- Contains only the best scored submission for each team and only public data.
create table if not exists public.qff_leaderboard (
  team_id uuid primary key references public.qff_teams(id),
  submission_id uuid not null unique references public.qff_submissions(id),
  team_name text not null,
  score_a double precision not null,
  n_2q integer not null,
  n_ticks integer not null,
  submitted_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.qff_teams enable row level security;
alter table public.qff_submissions enable row level security;
alter table public.qff_leaderboard enable row level security;

revoke all on table public.qff_teams from anon, authenticated;
revoke all on table public.qff_submissions from anon, authenticated;
revoke all on table public.qff_leaderboard from anon, authenticated;
grant select on table public.qff_leaderboard to anon, authenticated;
grant all on table public.qff_teams, public.qff_submissions, public.qff_leaderboard to service_role;

drop policy if exists "public leaderboard is readable" on public.qff_leaderboard;
create policy "public leaderboard is readable"
  on public.qff_leaderboard for select
  to anon, authenticated
  using (true);

-- Organizer-only helper. Call from the SQL editor or with the service-role key.
create or replace function public.admin_upsert_team(
  p_team_name text,
  p_password text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid;
  v_name text := trim(p_team_name);
begin
  if char_length(v_name) not between 1 and 80 then
    raise exception 'Team name must contain 1 to 80 characters';
  end if;
  if char_length(p_password) < 8 then
    raise exception 'Submission password must contain at least 8 characters';
  end if;

  insert into public.qff_teams (team_name, password_hash, active)
  values (v_name, extensions.crypt(p_password, extensions.gen_salt('bf', 10)), true)
  on conflict ((lower(trim(team_name)))) do update
    set team_name = excluded.team_name,
        password_hash = excluded.password_hash,
        active = true
  returning id into v_team_id;

  return v_team_id;
end;
$$;

-- Public dropdown source. This reveals active display names only; password
-- hashes and all other team fields remain inaccessible to browser users.
create or replace function public.list_active_teams()
returns table (team_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select t.team_name
  from public.qff_teams as t
  where t.active
  order by lower(t.team_name), t.team_name;
$$;

-- Public browser entry point. It authenticates the team and inserts only a
-- queued job; callers never receive access to either private table.
create or replace function public.submit_solution(
  p_team_name text,
  p_password text,
  p_qasm text,
  p_data_qubits smallint[]
)
returns table (submission_id uuid, status text, submitted_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.qff_teams%rowtype;
  v_name text := trim(p_team_name);
begin
  select * into v_team
  from public.qff_teams
  where lower(trim(team_name)) = lower(v_name)
    and active
  for update;

  if v_team.id is null
     or extensions.crypt(p_password, v_team.password_hash) <> v_team.password_hash then
    raise exception 'Invalid team name or submission password';
  end if;

  if octet_length(p_qasm) not between 1 and 200000 then
    raise exception 'QASM must be between 1 byte and 200 KB';
  end if;
  if array_length(p_data_qubits, 1) <> 7
     or exists (select 1 from unnest(p_data_qubits) as q where q < 0 or q >= 12)
     or (select count(distinct q) from unnest(p_data_qubits) as q) <> 7 then
    raise exception 'data_qubits must contain 7 distinct integers from 0 through 11';
  end if;

  if exists (
    select 1 from public.qff_submissions as recent
    where recent.team_id = v_team.id
      and recent.submitted_at > now() - interval '5 seconds'
  ) then
    raise exception 'Please wait five seconds before submitting again';
  end if;

  return query
  insert into public.qff_submissions as s (team_id, qasm, data_qubits)
  values (v_team.id, p_qasm, p_data_qubits)
  returning s.id, s.status, s.submitted_at;
end;
$$;

-- Atomically leases one job. Expired leases are retried up to three times.
create or replace function public.claim_submission(
  p_worker_id text,
  p_lease_seconds integer default 120
)
returns table (
  id uuid,
  team_name text,
  qasm text,
  data_qubits smallint[],
  course smallint,
  attempt_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if char_length(trim(p_worker_id)) = 0 then
    raise exception 'worker id is required';
  end if;
  if p_lease_seconds not between 10 and 3600 then
    raise exception 'lease must be between 10 and 3600 seconds';
  end if;

  return query
  with candidate as (
    select s.id
    from public.qff_submissions as s
    where (
      s.status = 'queued'
      or (s.status = 'processing' and s.lease_expires_at < now())
    )
      and s.attempt_count < 3
    order by s.submitted_at
    for update skip locked
    limit 1
  ), claimed as (
    update public.qff_submissions as s
    set status = 'processing',
        claimed_at = now(),
        lease_expires_at = now() + make_interval(secs => p_lease_seconds),
        worker_id = p_worker_id,
        attempt_count = s.attempt_count + 1,
        internal_error = null
    from candidate as c
    where s.id = c.id
    returning s.*
  )
  select c.id, t.team_name, c.qasm, c.data_qubits, c.course, c.attempt_count
  from claimed as c
  join public.qff_teams as t on t.id = c.team_id;
end;
$$;

-- Finishes a leased job and updates the team's best public result when the new
-- result wins by (A, two-qubit gates, ticks, submission time).
create or replace function public.finish_submission(
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
  v_submission public.qff_submissions%rowtype;
begin
  if p_status not in ('scored', 'invalid', 'error') then
    raise exception 'Invalid terminal status';
  end if;
  if p_status = 'scored' and (
    p_score_a is null or p_n_2q is null or p_n_ticks is null
    or p_score_a = 'NaN'::double precision
    or abs(p_score_a) = 'Infinity'::double precision
  ) then
    raise exception 'A scored submission requires finite score and tie-break metrics';
  end if;

  update public.qff_submissions
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
    insert into public.qff_leaderboard (
      team_id, submission_id, team_name, score_a, n_2q, n_ticks, submitted_at
    )
    select s.team_id, s.id, t.team_name, s.score_a, s.n_2q, s.n_ticks, s.submitted_at
    from public.qff_submissions as s
    join public.qff_teams as t on t.id = s.team_id
    where s.id = v_submission.id
    on conflict (team_id) do update
      set submission_id = excluded.submission_id,
          team_name = excluded.team_name,
          score_a = excluded.score_a,
          n_2q = excluded.n_2q,
          n_ticks = excluded.n_ticks,
          submitted_at = excluded.submitted_at,
          updated_at = now()
      where (excluded.score_a, excluded.n_2q, excluded.n_ticks, excluded.submitted_at)
          < (qff_leaderboard.score_a, qff_leaderboard.n_2q,
             qff_leaderboard.n_ticks, qff_leaderboard.submitted_at);
  end if;
end;
$$;

revoke all on function public.admin_upsert_team(text, text) from public, anon, authenticated;
revoke all on function public.list_active_teams() from public;
revoke all on function public.submit_solution(text, text, text, smallint[]) from public;
revoke all on function public.claim_submission(text, integer) from public, anon, authenticated;
revoke all on function public.finish_submission(uuid, text, text, double precision, double precision, integer, integer, text, text) from public, anon, authenticated;

grant execute on function public.admin_upsert_team(text, text) to service_role;
grant execute on function public.list_active_teams() to anon, authenticated, service_role;
grant execute on function public.submit_solution(text, text, text, smallint[]) to anon, authenticated, service_role;
grant execute on function public.claim_submission(text, integer) to service_role;
grant execute on function public.finish_submission(uuid, text, text, double precision, double precision, integer, integer, text, text) to service_role;

-- Example for creating a real team from the SQL editor:
-- select public.admin_upsert_team('Team Bell', 'replace-with-a-random-password');
