-- Keep the school/company privately while the public card shows only the
-- department (or the affiliation itself when there is no department).
-- Run once (or `supabase db query --linked -f`). Safe to rerun.

alter table public.qff_ideathon_participants
  add column if not exists organization text;

drop function if exists public.register_ideathon(text, text, text, text[], boolean, text, text, text, jsonb, text);

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
  p_emoji text default null,
  p_organization text default null
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
      (name, affiliation, self_pr, tags, has_team, team_name, phone, email, teammates, emoji, organization)
    values
      (trim(p_name), trim(p_affiliation), trim(p_self_pr), coalesce(p_tags, '{}'),
       coalesce(p_has_team, false),
       case when coalesce(p_has_team, false) then trim(p_team_name) end,
       trim(p_phone), trim(p_email), v_teammates, nullif(trim(coalesce(p_emoji, '')), ''),
       nullif(trim(coalesce(p_organization, '')), ''))
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

revoke all on function public.register_ideathon(text, text, text, text[], boolean, text, text, text, jsonb, text, text) from public;
grant execute on function public.register_ideathon(text, text, text, text[], boolean, text, text, text, jsonb, text, text) to anon, authenticated, service_role;
