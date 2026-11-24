-- Invite codes (friends join a group by code), adding people who aren't on
-- the app yet, and deleting groups. Safe to run more than once.

-- 1. Every group gets a short invite code. Existing groups get one too.
create or replace function public.new_invite_code() returns text
language sql volatile as $$
  -- 8 characters, no look-alikes (0/O, 1/I/L).
  select string_agg(
    substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), ''
  )
  from generate_series(1, 8)
$$;

alter table public.groups
  add column if not exists invite_code text not null unique
  default public.new_invite_code();

-- 2. Join a group with its code. Security definer: the caller can't see the
-- group before joining, so RLS would otherwise hide it.
create or replace function public.join_group(code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  g uuid;
  me uuid := my_person_id();
begin
  if me is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  select id into g from groups
    where invite_code = upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g'));
  if g is null then
    raise exception 'No group with that code' using errcode = 'P0002';
  end if;
  insert into group_members (group_id, person_id) values (g, me)
    on conflict do nothing;
  return g;
end $$;

revoke execute on function public.join_group(text) from anon, public;
grant execute on function public.join_group(text) to authenticated;

-- 3. Any member can delete a group. Expenses, shares, comments and
-- memberships are removed with it (on delete cascade).
drop policy if exists groups_delete on public.groups;
create policy groups_delete on public.groups for delete
  using (is_group_member(id));
