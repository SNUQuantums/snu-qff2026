-- Qiskit Fall Fest 2026 @ SNU — secure submission queue and leaderboard
--
-- Run this file once in a fresh Supabase project's SQL editor. It deliberately
-- uses qff_* table names so it can coexist with the earlier demo `submissions`
-- table without deleting data. A project created from the first version of
-- this file is brought up to date by supabase-migrate-v2.sql instead.
--
-- The `qasm` column holds the submitted circuit text (OpenQASM 2.0) and
-- `score_a` holds the score 1-F; the names are historical.
--
-- Security model:
--   * Browser users can list active team names, execute submit_solution(...),
--     read their own team's results with team_submissions(...) (password
--     required), and read qff_leaderboard.
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
  -- score_a at two significant figures, the precision the ranking uses
  score_key double precision not null,
  n_2q integer not null,
  n_ticks integer,
  p_acc double precision,
  submitted_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.qff_teams enable row level security;
alter table public.qff_submissions enable row level security;
-- Acceptance of the leaderboard entry (added after the first deployment; rerunnable).
alter table public.qff_leaderboard add column if not exists p_acc double precision;

alter table public.qff_leaderboard enable row level security;

revoke all on table public.qff_teams from anon, authenticated;
revoke all on table public.qff_submissions from anon, authenticated;
revoke all on table public.qff_leaderboard from anon, authenticated;
grant select on table public.qff_leaderboard to anon, authenticated;
grant all on table public.qff_teams, public.qff_submissions, public.qff_leaderboard to service_role;

-- Organizer settings, one row. Change the cooldown during the event with
--   update public.qff_settings set cooldown_seconds = 300;
create table if not exists public.qff_settings (
  id boolean primary key default true check (id),
  cooldown_seconds integer not null default 600 check (cooldown_seconds >= 0)
);
insert into public.qff_settings (id) values (true) on conflict (id) do nothing;
alter table public.qff_settings enable row level security;
revoke all on table public.qff_settings from anon, authenticated;
grant all on table public.qff_settings to service_role;

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
-- How long a team must wait before its next submission, and why. A team waits
-- for the cooldown after its last submission, and while a submission of its own
-- is still queued or being graded. A graded job whose worker died stops counting
-- once its lease runs out, so a stuck row cannot block a team for good.
create or replace function public.team_wait(p_team_id uuid)
returns table (wait_seconds integer, pending boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select
    greatest(0, ceil(extract(epoch from (
      (select max(s.submitted_at) from public.qff_submissions as s where s.team_id = p_team_id)
      + make_interval(secs => (select cooldown_seconds from public.qff_settings))
      - now()))))::integer,
    exists (
      select 1 from public.qff_submissions as s
      where s.team_id = p_team_id
        and (s.status = 'queued' or (s.status = 'processing' and s.lease_expires_at > now()))
    );
$$;

-- Queued submissions of any team ahead of this one; no team names are exposed.
create or replace function public.queue_ahead(p_submitted_at timestamptz)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from public.qff_submissions as s
  where s.status = 'queued' and s.submitted_at < p_submitted_at;
$$;

-- Public browser entry point. It authenticates the team and inserts only a
-- queued job; callers never receive access to either private table. A refusal
-- for waiting reads "Next submission allowed in N seconds" or "Previous
-- submission is still queued or being graded", which the submit page parses.
drop function if exists public.submit_solution(text, text, text, smallint[]);
create function public.submit_solution(
  p_team_name text,
  p_password text,
  p_qasm text,
  p_data_qubits smallint[]
)
returns table (submission_id uuid, status text, submitted_at timestamptz, ahead integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.qff_teams%rowtype;
  v_name text := trim(p_team_name);
  v_wait integer;
  v_pending boolean;
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
    raise exception 'The circuit must be between 1 byte and 200 KB';
  end if;
  if array_length(p_data_qubits, 1) <> 7
     or exists (select 1 from unnest(p_data_qubits) as q where q < 0 or q >= 36)
     or (select count(distinct q) from unnest(p_data_qubits) as q) <> 7 then
    raise exception 'data_qubits must contain 7 distinct integers from 0 through 35';
  end if;

  select w.wait_seconds, w.pending into v_wait, v_pending from public.team_wait(v_team.id) as w;
  if v_pending then
    raise exception 'Previous submission is still queued or being graded';
  end if;
  if v_wait > 0 then
    raise exception 'Next submission allowed in % seconds', v_wait;
  end if;

  return query
  with ins as (
    insert into public.qff_submissions as s (team_id, qasm, data_qubits)
    values (v_team.id, p_qasm, p_data_qubits)
    returning s.id, s.status, s.submitted_at
  )
  select ins.id, ins.status, ins.submitted_at, public.queue_ahead(ins.submitted_at) from ins;
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
-- result wins by (1-F at two significant figures, two-qubit gates, submission
-- time).
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
    p_score_a is null or p_n_2q is null
    or p_score_a = 'NaN'::double precision
    or abs(p_score_a) = 'Infinity'::double precision
  ) then
    raise exception 'A scored submission requires a finite score and a gate count';
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
      team_id, submission_id, team_name, score_a, score_key, n_2q, n_ticks, p_acc, submitted_at
    )
    select s.team_id, s.id, t.team_name, s.score_a,
           -- two significant figures: 0.002597 -> 0.0026
           to_char(s.score_a, '9.9EEEE')::double precision,
           s.n_2q, s.n_ticks, s.p_acc, s.submitted_at
    from public.qff_submissions as s
    join public.qff_teams as t on t.id = s.team_id
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
          < (qff_leaderboard.score_key, qff_leaderboard.n_2q, qff_leaderboard.submitted_at);
  end if;
end;
$$;

-- A team's own recent submissions, with the judge's public message, so a team
-- can see why a circuit failed. Authenticated like submit_solution; internal
-- errors and circuit text are not returned. Dropped first because create or
-- replace cannot change the columns a function returns.
drop function if exists public.team_submissions(text, text, integer);
create function public.team_submissions(
  p_team_name text,
  p_password text,
  p_limit integer default 20
)
returns table (
  submission_id uuid,
  status text,
  submitted_at timestamptz,
  scored_at timestamptz,
  score double precision,
  acceptance double precision,
  n_2q integer,
  public_message text,
  worker text,
  ahead integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_team public.qff_teams%rowtype;
begin
  select * into v_team
  from public.qff_teams
  where lower(trim(team_name)) = lower(trim(p_team_name))
    and active;

  if v_team.id is null
     or extensions.crypt(p_password, v_team.password_hash) <> v_team.password_hash then
    raise exception 'Invalid team name or submission password';
  end if;

  return query
  select s.id, s.status, s.submitted_at, s.scored_at, s.score_a, s.p_acc, s.n_2q, s.public_message,
         s.worker_id,
         case when s.status = 'queued' then public.queue_ahead(s.submitted_at) end
  from public.qff_submissions as s
  where s.team_id = v_team.id
  order by s.submitted_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100);
end;
$$;

-- When a team may submit next, for the countdown on the submit page.
create or replace function public.team_next_submission(p_team_name text, p_password text)
returns table (wait_seconds integer, pending boolean, cooldown_seconds integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_team public.qff_teams%rowtype;
begin
  select * into v_team
  from public.qff_teams
  where lower(trim(team_name)) = lower(trim(p_team_name))
    and active;

  if v_team.id is null
     or extensions.crypt(p_password, v_team.password_hash) <> v_team.password_hash then
    raise exception 'Invalid team name or submission password';
  end if;

  return query
  select w.wait_seconds, w.pending, (select c.cooldown_seconds from public.qff_settings as c)
  from public.team_wait(v_team.id) as w;
end;
$$;

revoke all on function public.admin_upsert_team(text, text) from public, anon, authenticated;
revoke all on function public.list_active_teams() from public;
revoke all on function public.submit_solution(text, text, text, smallint[]) from public;
revoke all on function public.team_submissions(text, text, integer) from public;
revoke all on function public.team_next_submission(text, text) from public;
revoke all on function public.team_wait(uuid) from public, anon, authenticated;
revoke all on function public.queue_ahead(timestamptz) from public, anon, authenticated;
revoke all on function public.claim_submission(text, integer) from public, anon, authenticated;
revoke all on function public.finish_submission(uuid, text, text, double precision, double precision, integer, integer, text, text) from public, anon, authenticated;

grant execute on function public.admin_upsert_team(text, text) to service_role;
grant execute on function public.list_active_teams() to anon, authenticated, service_role;
grant execute on function public.submit_solution(text, text, text, smallint[]) to anon, authenticated, service_role;
grant execute on function public.team_submissions(text, text, integer) to anon, authenticated, service_role;
grant execute on function public.team_next_submission(text, text) to anon, authenticated, service_role;
grant execute on function public.team_wait(uuid) to service_role;
grant execute on function public.queue_ahead(timestamptz) to service_role;
grant execute on function public.claim_submission(text, integer) to service_role;
grant execute on function public.finish_submission(uuid, text, text, double precision, double precision, integer, integer, text, text) to service_role;

-- Example for creating a real team from the SQL editor:
-- select public.admin_upsert_team('Team Bell', 'replace-with-a-random-password');

-- ===== v4: registration, event timing, gated problem (same statements as supabase-migrate-v4-registration.sql) =====
-- Supabase SQL editor (or `supabase db query --linked -f`). Safe to rerun.
--
-- What this adds:
--   * Event timing and the hackathon problem link live in qff_settings, never
--     in the public site repository. event_status() returns the problem link
--     and brief only after hackathon_problem_opens_at.
--   * Ideathon participants register from the browser through
--     register_ideathon(...). The public card list (list_ideathon_participants)
--     exposes name, affiliation, self-PR, tags, and team status only. Phone,
--     email, team name, and teammates stay in the private table.
--   * Hackathon teams register themselves through register_hackathon_team(...),
--     which stores the leader's contact details privately in qff_teams.
--   * submit_solution refuses submissions before the problem opens and after
--     the deadline.
--   * The public leaderboard hides teams that have been deactivated, so test
--     teams can be switched off without deleting anything.

-- ---------------------------------------------------------------- settings --
alter table public.qff_settings
  add column if not exists ideathon_registration_opens_at timestamptz not null default '2026-10-16 00:00:00+09',
  add column if not exists hackathon_registration_opens_at timestamptz not null default '2026-10-16 00:00:00+09',
  add column if not exists hackathon_problem_opens_at timestamptz not null default '2026-10-22 22:00:00+09',
  add column if not exists ideathon_deadline_at timestamptz not null default '2026-10-29 17:00:00+09',
  add column if not exists hackathon_deadline_at timestamptz not null default '2026-10-30 12:00:00+09',
  add column if not exists hackathon_problem_url text,
  add column if not exists hackathon_problem_brief_kr text,
  add column if not exists hackathon_problem_brief_en text,
  add column if not exists ideathon_submission_url text;

-- Public, read-only view of the timing. Secrets are returned only once open.
create or replace function public.event_status()
returns table (
  now_at timestamptz,
  ideathon_registration_opens_at timestamptz,
  hackathon_registration_opens_at timestamptz,
  hackathon_problem_opens_at timestamptz,
  ideathon_deadline_at timestamptz,
  hackathon_deadline_at timestamptz,
  ideathon_registration_open boolean,
  hackathon_registration_open boolean,
  hackathon_problem_open boolean,
  hackathon_submissions_open boolean,
  hackathon_problem_url text,
  hackathon_problem_brief_kr text,
  hackathon_problem_brief_en text,
  ideathon_submission_url text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    now(),
    s.ideathon_registration_opens_at,
    s.hackathon_registration_opens_at,
    s.hackathon_problem_opens_at,
    s.ideathon_deadline_at,
    s.hackathon_deadline_at,
    now() >= s.ideathon_registration_opens_at,
    now() >= s.hackathon_registration_opens_at,
    now() >= s.hackathon_problem_opens_at,
    now() >= s.hackathon_problem_opens_at and now() < s.hackathon_deadline_at,
    case when now() >= s.hackathon_problem_opens_at then s.hackathon_problem_url end,
    case when now() >= s.hackathon_problem_opens_at then s.hackathon_problem_brief_kr end,
    case when now() >= s.hackathon_problem_opens_at then s.hackathon_problem_brief_en end,
    s.ideathon_submission_url
  from public.qff_settings as s;
$$;

-- -------------------------------------------------------- ideathon teams --
create table if not exists public.qff_ideathon_participants (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 60),
  affiliation text not null check (char_length(trim(affiliation)) between 1 and 120),
  self_pr text not null check (char_length(trim(self_pr)) between 1 and 600),
  tags text[] not null default '{}'
    check (tags <@ array['Quantum Technology','Coding','Design','Marketing','Presentation']::text[]),
  has_team boolean not null default false,
  team_name text check (team_name is null or char_length(trim(team_name)) between 1 and 80),
  phone text not null check (char_length(trim(phone)) between 5 and 30),
  email text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  -- up to three teammates: [{"name":..,"phone":..,"email":..}]
  teammates jsonb not null default '[]'::jsonb check (jsonb_typeof(teammates) = 'array'),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists qff_ideathon_participants_email_idx
  on public.qff_ideathon_participants ((lower(trim(email))));

alter table public.qff_ideathon_participants enable row level security;
revoke all on table public.qff_ideathon_participants from anon, authenticated;
grant all on table public.qff_ideathon_participants to service_role;

create or replace function public.register_ideathon(
  p_name text,
  p_affiliation text,
  p_self_pr text,
  p_tags text[],
  p_has_team boolean,
  p_team_name text,
  p_phone text,
  p_email text,
  p_teammates jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_mate jsonb;
  v_teammates jsonb := coalesce(p_teammates, '[]'::jsonb);
begin
  if now() < (select ideathon_registration_opens_at from public.qff_settings) then
    raise exception 'Ideathon registration is not open yet';
  end if;
  if coalesce(array_length(p_tags, 1), 0) > 5
     or (select count(distinct t) from unnest(p_tags) as t) <> coalesce(array_length(p_tags, 1), 0) then
    raise exception 'Choose each tag at most once';
  end if;

  if not coalesce(p_has_team, false) then
    v_teammates := '[]'::jsonb;
  else
    if char_length(trim(coalesce(p_team_name, ''))) = 0 then
      raise exception 'Team name is required when you already have a team';
    end if;
    if jsonb_typeof(v_teammates) <> 'array' or jsonb_array_length(v_teammates) > 3 then
      raise exception 'A team may list at most three additional members';
    end if;
    for v_mate in select * from jsonb_array_elements(v_teammates) loop
      if jsonb_typeof(v_mate) <> 'object'
         or char_length(trim(coalesce(v_mate->>'name', ''))) not between 1 and 60
         or char_length(trim(coalesce(v_mate->>'phone', ''))) not between 5 and 30
         or coalesce(v_mate->>'email', '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        raise exception 'Each teammate needs a name, phone number, and email';
      end if;
    end loop;
    -- keep only the three known keys
    select coalesce(jsonb_agg(jsonb_build_object(
             'name', trim(m->>'name'), 'phone', trim(m->>'phone'), 'email', trim(m->>'email'))), '[]'::jsonb)
      into v_teammates
      from jsonb_array_elements(v_teammates) as m;
  end if;

  begin
    insert into public.qff_ideathon_participants
      (name, affiliation, self_pr, tags, has_team, team_name, phone, email, teammates)
    values
      (trim(p_name), trim(p_affiliation), trim(p_self_pr), coalesce(p_tags, '{}'),
       coalesce(p_has_team, false),
       case when coalesce(p_has_team, false) then trim(p_team_name) end,
       trim(p_phone), trim(p_email), v_teammates)
    returning id into v_id;
  exception
    when unique_violation then
      raise exception 'This email address is already registered';
    when check_violation then
      raise exception 'Please check the length and format of each field';
  end;

  return v_id;
end;
$$;

-- Public cards. Participants still looking for a team come first. Dropped first
-- because a later section changes the returned columns.
drop function if exists public.list_ideathon_participants();
create or replace function public.list_ideathon_participants()
returns table (
  participant_id uuid,
  name text,
  affiliation text,
  self_pr text,
  tags text[],
  has_team boolean,
  registered_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.name, p.affiliation, p.self_pr, p.tags, p.has_team, p.created_at
  from public.qff_ideathon_participants as p
  where p.active
  order by p.has_team, p.created_at;
$$;

-- -------------------------------------------------------- hackathon teams --
alter table public.qff_teams
  add column if not exists leader_name text,
  add column if not exists leader_phone text,
  add column if not exists leader_email text,
  add column if not exists registered_at timestamptz;

create or replace function public.register_hackathon_team(
  p_team_name text,
  p_password text,
  p_leader_name text,
  p_phone text,
  p_email text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_name text := trim(p_team_name);
begin
  if now() < (select hackathon_registration_opens_at from public.qff_settings) then
    raise exception 'Hackathon registration is not open yet';
  end if;
  if char_length(v_name) not between 1 and 80 then
    raise exception 'Team name must contain 1 to 80 characters';
  end if;
  if char_length(p_password) not between 8 and 200 then
    raise exception 'Submission password must contain 8 to 200 characters';
  end if;
  if char_length(trim(coalesce(p_leader_name, ''))) not between 1 and 60 then
    raise exception 'Team leader name is required';
  end if;
  if char_length(trim(coalesce(p_phone, ''))) not between 5 and 30 then
    raise exception 'A phone number is required';
  end if;
  if coalesce(p_email, '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'A valid email address is required';
  end if;
  if exists (select 1 from public.qff_teams where lower(trim(team_name)) = lower(v_name)) then
    raise exception 'This team name is already taken';
  end if;

  insert into public.qff_teams (team_name, password_hash, active, leader_name, leader_phone, leader_email, registered_at)
  values (v_name, extensions.crypt(p_password, extensions.gen_salt('bf', 10)), true,
          trim(p_leader_name), trim(p_phone), trim(p_email), now())
  returning id into v_id;

  return v_id;
end;
$$;

-- submit_solution now also honours the problem release and the deadline.
create or replace function public.submit_solution(
  p_team_name text,
  p_password text,
  p_qasm text,
  p_data_qubits smallint[]
)
returns table (submission_id uuid, status text, submitted_at timestamptz, ahead integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.qff_teams%rowtype;
  v_settings public.qff_settings%rowtype;
  v_name text := trim(p_team_name);
  v_wait integer;
  v_pending boolean;
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

  select * into v_settings from public.qff_settings;
  if now() < v_settings.hackathon_problem_opens_at then
    raise exception 'Submissions open when the problem is released';
  end if;
  if now() >= v_settings.hackathon_deadline_at then
    raise exception 'Submissions are closed';
  end if;

  if octet_length(p_qasm) not between 1 and 200000 then
    raise exception 'The circuit must be between 1 byte and 200 KB';
  end if;
  if array_length(p_data_qubits, 1) <> 7
     or exists (select 1 from unnest(p_data_qubits) as q where q < 0 or q >= 36)
     or (select count(distinct q) from unnest(p_data_qubits) as q) <> 7 then
    raise exception 'data_qubits must contain 7 distinct integers from 0 through 35';
  end if;

  select w.wait_seconds, w.pending into v_wait, v_pending from public.team_wait(v_team.id) as w;
  if v_pending then
    raise exception 'Previous submission is still queued or being graded';
  end if;
  if v_wait > 0 then
    raise exception 'Next submission allowed in % seconds', v_wait;
  end if;

  return query
  with ins as (
    insert into public.qff_submissions as s (team_id, qasm, data_qubits)
    values (v_team.id, p_qasm, p_data_qubits)
    returning s.id, s.status, s.submitted_at
  )
  select ins.id, ins.status, ins.submitted_at, public.queue_ahead(ins.submitted_at) from ins;
end;
$$;

-- ------------------------------------------------------------ leaderboard --
-- Deactivated teams disappear from the public board without deleting rows.
create or replace function public.team_is_active(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.qff_teams as t where t.id = p_team_id and t.active);
$$;

drop policy if exists "public leaderboard is readable" on public.qff_leaderboard;
create policy "public leaderboard is readable"
  on public.qff_leaderboard for select
  to anon, authenticated
  using (public.team_is_active(team_id));

-- ----------------------------------------------------------------- grants --
revoke all on function public.event_status() from public;
revoke all on function public.register_ideathon(text, text, text, text[], boolean, text, text, text, jsonb) from public;
revoke all on function public.list_ideathon_participants() from public;
revoke all on function public.register_hackathon_team(text, text, text, text, text) from public;
revoke all on function public.team_is_active(uuid) from public;

grant execute on function public.event_status() to anon, authenticated, service_role;
grant execute on function public.register_ideathon(text, text, text, text[], boolean, text, text, text, jsonb) to anon, authenticated, service_role;
grant execute on function public.list_ideathon_participants() to anon, authenticated, service_role;
grant execute on function public.register_hackathon_team(text, text, text, text, text) to anon, authenticated, service_role;
grant execute on function public.team_is_active(uuid) to anon, authenticated, service_role;

-- Organizer notes:
--   Set the problem link and brief any time; the site reveals them automatically
--   at hackathon_problem_opens_at:
--     update public.qff_settings set hackathon_problem_url = 'https://github.com/...',
--       hackathon_problem_brief_kr = '...', hackathon_problem_brief_en = '...';
--   Set the Ideathon submission form:
--     update public.qff_settings set ideathon_submission_url = 'https://forms.gle/...';
--   Retire the test teams at go-live (they vanish from the board, nothing is deleted):
--     update public.qff_teams set active = false where team_name like 'test-%';

-- ===== v5: emoji avatar (same statements as supabase-migrate-v5-emoji.sql) =====

alter table public.qff_ideathon_participants
  add column if not exists emoji text;

alter table public.qff_ideathon_participants
  drop constraint if exists qff_ideathon_participants_emoji_check;
alter table public.qff_ideathon_participants
  add constraint qff_ideathon_participants_emoji_check check (
    emoji is null or emoji = any (array[
      '🚀','⚛️','🧠','💡','🔬','🧪','🧲','💻','🎨','📈','📣','🎤',
      '🛠️','🧩','🌌','🪐','🔭','🤖','🦾','🐱','🐧','🦊','🐙','🍀'
    ])
  );

-- The registration function gains a p_emoji argument; the old signature goes.
drop function if exists public.register_ideathon(text, text, text, text[], boolean, text, text, text, jsonb);

create or replace function public.register_ideathon(
  p_name text,
  p_affiliation text,
  p_self_pr text,
  p_tags text[],
  p_has_team boolean,
  p_team_name text,
  p_phone text,
  p_email text,
  p_teammates jsonb,
  p_emoji text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_mate jsonb;
  v_teammates jsonb := coalesce(p_teammates, '[]'::jsonb);
begin
  if now() < (select ideathon_registration_opens_at from public.qff_settings) then
    raise exception 'Ideathon registration is not open yet';
  end if;
  if coalesce(array_length(p_tags, 1), 0) > 5
     or (select count(distinct t) from unnest(p_tags) as t) <> coalesce(array_length(p_tags, 1), 0) then
    raise exception 'Choose each tag at most once';
  end if;

  if not coalesce(p_has_team, false) then
    v_teammates := '[]'::jsonb;
  else
    if char_length(trim(coalesce(p_team_name, ''))) = 0 then
      raise exception 'Team name is required when you already have a team';
    end if;
    if jsonb_typeof(v_teammates) <> 'array' or jsonb_array_length(v_teammates) > 3 then
      raise exception 'A team may list at most three additional members';
    end if;
    for v_mate in select * from jsonb_array_elements(v_teammates) loop
      if jsonb_typeof(v_mate) <> 'object'
         or char_length(trim(coalesce(v_mate->>'name', ''))) not between 1 and 60
         or char_length(trim(coalesce(v_mate->>'phone', ''))) not between 5 and 30
         or coalesce(v_mate->>'email', '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        raise exception 'Each teammate needs a name, phone number, and email';
      end if;
    end loop;
    select coalesce(jsonb_agg(jsonb_build_object(
             'name', trim(m->>'name'), 'phone', trim(m->>'phone'), 'email', trim(m->>'email'))), '[]'::jsonb)
      into v_teammates
      from jsonb_array_elements(v_teammates) as m;
  end if;

  begin
    insert into public.qff_ideathon_participants
      (name, affiliation, self_pr, tags, has_team, team_name, phone, email, teammates, emoji)
    values
      (trim(p_name), trim(p_affiliation), trim(p_self_pr), coalesce(p_tags, '{}'),
       coalesce(p_has_team, false),
       case when coalesce(p_has_team, false) then trim(p_team_name) end,
       trim(p_phone), trim(p_email), v_teammates, nullif(trim(coalesce(p_emoji, '')), ''))
    returning id into v_id;
  exception
    when unique_violation then
      raise exception 'This email address is already registered';
    when check_violation then
      raise exception 'Please check the length and format of each field';
  end;

  return v_id;
end;
$$;

-- Public cards now carry the emoji. Dropped first: the return columns change.
drop function if exists public.list_ideathon_participants();
create function public.list_ideathon_participants()
returns table (
  participant_id uuid,
  name text,
  affiliation text,
  self_pr text,
  tags text[],
  has_team boolean,
  emoji text,
  registered_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.name, p.affiliation, p.self_pr, p.tags, p.has_team, p.emoji, p.created_at
  from public.qff_ideathon_participants as p
  where p.active
  order by p.has_team, p.created_at;
$$;

revoke all on function public.register_ideathon(text, text, text, text[], boolean, text, text, text, jsonb, text) from public;
revoke all on function public.list_ideathon_participants() from public;
grant execute on function public.register_ideathon(text, text, text, text[], boolean, text, text, text, jsonb, text) to anon, authenticated, service_role;
grant execute on function public.list_ideathon_participants() to anon, authenticated, service_role;

-- ===== v6: any single emoji (same statements as supabase-migrate-v6-emoji-any.sql) =====
alter table public.qff_ideathon_participants
  drop constraint if exists qff_ideathon_participants_emoji_check;
alter table public.qff_ideathon_participants
  add constraint qff_ideathon_participants_emoji_check check (
    emoji is null or (
      char_length(emoji) between 1 and 8
      and emoji ~ '^[\U0001F000-\U0001FAFF☀-➿⬀-⯿‍️⃣©®™〰〽㊗㊙]+$'
    )
  );
