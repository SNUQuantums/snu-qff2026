-- Registration, event timing, and the gated hackathon problem. Run once in the
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

-- Public cards. Participants still looking for a team come first.
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
