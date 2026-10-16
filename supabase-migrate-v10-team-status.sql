-- Organizer helper: flip the team status of several Ideathon participants at
-- once. Match by email (case-insensitive) or by exact name. Run from the SQL
-- editor (or tools/team_status.py). Not callable with the public key.
--
--   select * from public.admin_set_team_status(array['a@snu.ac.kr','홍길동'], true);
--   select * from public.admin_set_team_status(array['a@snu.ac.kr'], true, 'Team Bell');
--   select * from public.admin_set_team_status(array['a@snu.ac.kr'], false);

create or replace function public.admin_set_team_status(
  p_keys text[],
  p_has_team boolean,
  p_team_name text default null
)
returns table (name text, email text, has_team boolean, team_name text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update public.qff_ideathon_participants as p
  set has_team = p_has_team,
      team_name = case
        when not p_has_team then null
        when p_team_name is not null then nullif(trim(p_team_name), '')
        else p.team_name end,
      teammates = case when p_has_team then p.teammates else '[]'::jsonb end
  where p.active
    and (lower(trim(p.email)) = any (select lower(trim(k)) from unnest(p_keys) as k)
         or p.name = any (select trim(k) from unnest(p_keys) as k))
  returning p.name, p.email, p.has_team, p.team_name;
end;
$$;

revoke all on function public.admin_set_team_status(text[], boolean, text) from public, anon, authenticated;
grant execute on function public.admin_set_team_status(text[], boolean, text) to service_role;
