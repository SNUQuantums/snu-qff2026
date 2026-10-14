-- Email notifications for new Ideathon registrations. Run once in the SQL
-- editor (or `supabase db query --linked -f`). Safe to rerun. Regenerate the
-- _test mirror afterwards.
--
-- How it works: a Google Apps Script running under the club Gmail account
-- (tools/apps-script/README.md) polls ideathon_pending_notifications(...) every
-- few minutes, emails each new participant the KakaoTalk open-chat link and
-- password (cc teammates), emails the organizers a digest, then calls
-- ideathon_mark_notified(...). Both functions require the notifier token, a
-- random secret stored only in qff_notifier and in the script's properties.
--
-- The chat link and password are set with a separate statement, never in a
-- committed file:
--   update public.qff_settings set ideathon_chat_url = '...', ideathon_chat_password = '...';
--   update public.qff_notifier set token = '<random>';

alter table public.qff_settings
  add column if not exists ideathon_chat_url text,
  add column if not exists ideathon_chat_password text;

alter table public.qff_ideathon_participants
  add column if not exists notified_at timestamptz;

create table if not exists public.qff_notifier (
  id boolean primary key default true check (id),
  token text
);
insert into public.qff_notifier (id) values (true) on conflict (id) do nothing;
alter table public.qff_notifier enable row level security;
revoke all on table public.qff_notifier from anon, authenticated;
grant all on table public.qff_notifier to service_role;

create or replace function public.notifier_token_ok(p_token text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.qff_notifier
    where token is not null and char_length(token) >= 20 and token = p_token
  );
$$;

-- Registrations not yet emailed, with everything the message needs.
create or replace function public.ideathon_pending_notifications(p_token text)
returns table (
  participant_id uuid,
  name text,
  email text,
  affiliation text,
  has_team boolean,
  team_name text,
  teammate_emails text[],
  registered_at timestamptz,
  chat_url text,
  chat_password text,
  ideathon_deadline_at timestamptz,
  ideathon_submission_url text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.notifier_token_ok(p_token) then
    raise exception 'Invalid notifier token';
  end if;
  return query
  select p.id, p.name, p.email, p.affiliation, p.has_team, p.team_name,
         coalesce((select array_agg(m->>'email') from jsonb_array_elements(p.teammates) as m
                   where coalesce(m->>'email', '') <> ''), '{}'::text[]),
         p.created_at,
         s.ideathon_chat_url, s.ideathon_chat_password, s.ideathon_deadline_at, s.ideathon_submission_url
  from public.qff_ideathon_participants as p
  cross join public.qff_settings as s
  where p.active and p.notified_at is null
  order by p.created_at
  limit 50;
end;
$$;

create or replace function public.ideathon_mark_notified(p_token text, p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not public.notifier_token_ok(p_token) then
    raise exception 'Invalid notifier token';
  end if;
  update public.qff_ideathon_participants
  set notified_at = now()
  where id = any (p_ids) and notified_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.notifier_token_ok(text) from public, anon, authenticated;
revoke all on function public.ideathon_pending_notifications(text) from public;
revoke all on function public.ideathon_mark_notified(text, uuid[]) from public;
grant execute on function public.notifier_token_ok(text) to service_role;
grant execute on function public.ideathon_pending_notifications(text) to anon, authenticated, service_role;
grant execute on function public.ideathon_mark_notified(text, uuid[]) to anon, authenticated, service_role;
