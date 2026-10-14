-- Show the KakaoTalk open-chat details on the registration success screen.
-- Run once in the SQL editor (or `supabase db query --linked -f`). Safe to
-- rerun. Regenerate the _test mirror afterwards.
--
-- The details are released only against a participant id returned by a
-- successful register_ideathon(...) call. Ids are random UUIDs, so the page
-- can fetch them right after registering while the link stays out of the
-- public site repository and out of event_status().

create or replace function public.ideathon_welcome(p_participant_id uuid)
returns table (chat_url text, chat_password text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.ideathon_chat_url, s.ideathon_chat_password
  from public.qff_settings as s
  where exists (
    select 1 from public.qff_ideathon_participants as p
    where p.id = p_participant_id and p.active
  );
$$;

revoke all on function public.ideathon_welcome(uuid) from public;
grant execute on function public.ideathon_welcome(uuid) to anon, authenticated, service_role;
